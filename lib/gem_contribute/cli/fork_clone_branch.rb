# frozen_string_literal: true

require "open3"

module GemContribute
  module CLI
    # `gem-contribute fork-clone-branch <gem>/<issue#>`
    #
    # Performs the full sequence the TUI's `f` keybinding will trigger in
    # Stage 3:
    #
    #   1. Resolve <gem> via the RubyGems Resolver (no lockfile required;
    #      the lockfile is for discovery via `scan`, not gating here).
    #   2. Read the cached GitHub token; raise AuthRequired with a clear
    #      `auth login` hint if missing.
    #   3. Look up the viewer's login.
    #   4. If they don't already have a fork, fork the upstream repo.
    #   5. Poll until the fork is reachable (forks return 202 immediately
    #      but the resource may 404 for a few seconds).
    #   6. `git clone` the fork to `<clone_root>/<owner>/<repo>`.
    #   7. `git checkout -b gem-contribute/issue-<N>` from the default branch.
    #   8. Print the local path on stdout.
    #
    # The shell-outs use Open3 with explicit args (not strings) to avoid any
    # shell-injection surface.
    class ForkCloneBranch
      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")
      BRANCH_PREFIX = "gem-contribute/issue-"
      FORK_READINESS_RETRIES = 12 # 12 × 5s = 60s ceiling
      FORK_READINESS_INTERVAL = 5

      def initialize(stdout: $stdout,
                     stderr: $stderr,
                     resolver: Resolver.new,
                     store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     sleeper: ->(s) { Kernel.sleep(s) })
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @git = git
        @clone_root = clone_root
        @sleeper = sleeper
      end

      def run(argv)
        target = argv.shift
        return print_usage_error if target.nil? || !target.include?("/")

        gem_name, issue = target.split("/", 2)
        adapter = build_adapter
        return 1 if adapter.nil?

        project = resolve_or_fail(gem_name)
        return 1 if project.nil?

        execute(adapter, project, issue)
      rescue AuthRequired
        @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
        1
      rescue AdapterError => e
        @stderr.puts "fork-clone-branch failed: #{e.message}"
        1
      end

      private

      def print_usage_error
        @stderr.puts "Usage: gem-contribute fork-clone-branch <gem>/<issue#>"
        2
      end

      def build_adapter
        token = @store.token_for("github.com")
        if token.nil?
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          return nil
        end
        @adapter_factory.call(token: token)
      end

      def resolve_or_fail(gem_name)
        gem = LockedGem.new(name: gem_name, version: "*", source_type: :rubygems, source_uri: "https://rubygems.org/")
        project = @resolver.resolve(gem)

        if project.host != "github.com"
          @stderr.puts "Cannot fork-clone-branch: #{gem_name} resolves to #{project.host} " \
                       "(only github.com is supported at v0.1)"
          return nil
        end

        project
      end

      def execute(adapter, project, issue)
        viewer = adapter.viewer_login
        clone_url = ensure_fork(adapter, project, viewer)
        local_path = clone_into_root(project, clone_url)
        branch_name = "#{BRANCH_PREFIX}#{issue}"
        @git.checkout_branch(local_path, branch_name)
        # `submit` needs to know the canonical project to point the PR at.
        # Naming it `upstream` follows the standard fork workflow convention.
        @git.add_remote(local_path, "upstream",
                        "https://github.com/#{project.owner}/#{project.repo}.git")

        @stdout.puts "Forked, cloned, and branched."
        @stdout.puts "  path:   #{local_path}"
        @stdout.puts "  branch: #{branch_name}"
        @stdout.puts "  upstream: https://github.com/#{project.owner}/#{project.repo}"
        @stdout.puts "  fork:     https://github.com/#{viewer}/#{project.repo}"
        @stdout.puts
        @stdout.puts "Next: cd #{local_path} && make your changes, then `gem-contribute submit`."
        0
      end

      def ensure_fork(adapter, project, viewer)
        if adapter.already_forked?(project)
          @stdout.puts "You already have a fork at #{viewer}/#{project.repo}. Skipping fork."
          return "https://github.com/#{viewer}/#{project.repo}.git"
        end

        @stdout.puts "Forking #{project.owner}/#{project.repo} → #{viewer}/#{project.repo}..."
        body = adapter.fork(project)
        wait_until_ready(adapter, viewer, project.repo)
        body.fetch("clone_url")
      end

      def wait_until_ready(adapter, viewer, name)
        ready = FORK_READINESS_RETRIES.times.any? do |i|
          break true if adapter.fork_ready?(viewer, name)

          @sleeper.call(FORK_READINESS_INTERVAL) unless i == FORK_READINESS_RETRIES - 1
          false
        end
        return if ready

        raise AdapterError, "fork not reachable after #{FORK_READINESS_RETRIES * FORK_READINESS_INTERVAL}s"
      end

      def clone_into_root(project, clone_url)
        target = File.join(@clone_root, project.owner, project.repo)
        if File.directory?(File.join(target, ".git"))
          @stdout.puts "Reusing existing clone at #{target}."
          return target
        end

        FileUtils.mkdir_p(File.dirname(target))
        @stdout.puts "Cloning into #{target}..."
        @git.clone(clone_url, target)
        target
      end
    end

    # Thin wrapper around git so the spec can swap in a fake without shelling
    # out. The real implementation uses Open3 with arg-list invocation — no
    # shell, so no injection surface.
    class Git
      def clone(url, target)
        run!(["git", "clone", url, target])
      end

      def checkout_branch(path, branch)
        run!(["git", "-C", path, "checkout", "-b", branch])
      end

      def add_remote(path, name, url)
        # Idempotent: if the remote already exists (e.g. reusing a clone)
        # we silently succeed rather than fail the whole flow.
        return if remote_exists?(path, name)

        run!(["git", "-C", path, "remote", "add", name, url])
      end

      def remote_exists?(path, name)
        out, _err, status = Open3.capture3("git", "-C", path, "remote")
        status.success? && out.split("\n").include?(name)
      end

      def run!(argv)
        _stdout, stderr_str, status = Open3.capture3(*argv)
        return if status.success?

        raise GemContribute::AdapterError, "git #{argv[1..].join(" ")} failed: #{stderr_str.strip}"
      end
    end
  end
end
