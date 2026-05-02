# frozen_string_literal: true

require "open3"

module GemContribute
  module CLI
    # `gem-contribute fix <gem>/<issue#> [-e] [-a]`
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
    #   9. Optionally invoke PostCloneHooks for `-e` (open editor) and/or
    #      `-a` (launch AI tool).
    #
    # The shell-outs use Open3 with explicit args (not strings) to avoid any
    # shell-injection surface.
    class Fix
      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")
      BRANCH_PREFIX = "gem-contribute/issue-"
      FORK_READINESS_RETRIES = 12 # 12 × 5s = 60s ceiling
      FORK_READINESS_INTERVAL = 5

      # rubocop:disable Metrics/ParameterLists
      def initialize(stdout: $stdout,
                     stderr: $stderr,
                     resolver: Resolver.new,
                     store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     sleeper: ->(s) { Kernel.sleep(s) },
                     post_clone_hooks: nil,
                     config: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @git = git
        @clone_root = clone_root
        @sleeper = sleeper
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
        @config = config || GemContribute::Config.new
      end
      # rubocop:enable Metrics/ParameterLists

      def run(argv)
        return missing_clone_root if @clone_root.nil?

        target, flags = parse_argv(argv)
        return print_usage_error if target.nil? || !target.include?("/")

        gem_name, issue = target.split("/", 2)
        adapter = build_adapter
        return 1 if adapter.nil?

        project = resolve_or_fail(gem_name)
        return 1 if project.nil?

        execute(adapter, project, issue, flags)
      rescue AuthRequired
        @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
        1
      rescue AdapterError => e
        @stderr.puts "fix failed: #{e.message}"
        1
      end

      private

      def parse_argv(argv)
        flags = { editor: false, ai_tool: false, no_comment: false }
        positional = []
        argv.each do |arg|
          case arg
          when "-e", "--editor" then flags[:editor] = true
          when "-a", "--ai"     then flags[:ai_tool] = true
          when "--no-comment"   then flags[:no_comment] = true
          else positional << arg
          end
        end
        [positional.first, flags]
      end

      def missing_clone_root
        @stderr.puts "clone_root is not configured. Run `gem-contribute init` first."
        1
      end

      def print_usage_error
        @stderr.puts "Usage: gem-contribute fix <gem>/<issue#> [-e] [-a]"
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
        return GemContribute::SELF_PROJECT if gem_name == GemContribute::SELF_PROJECT.gem_name

        gem = LockedGem.new(name: gem_name, version: "*", source_type: :rubygems, source_uri: "https://rubygems.org/")
        project = @resolver.resolve(gem)

        if project.host != "github.com"
          @stderr.puts "Cannot run `fix`: #{gem_name} resolves to #{project.host} " \
                       "(only github.com is supported at v0.1)"
          return nil
        end

        project
      end

      def execute(adapter, project, issue, flags)
        viewer = adapter.viewer_login
        was_resuming = clone_exists?(project)
        clone_url = ensure_fork(adapter, project, viewer)
        local_path = clone_into_root(project, clone_url)
        branch_name = "#{BRANCH_PREFIX}#{issue}"
        @git.checkout_branch(local_path, branch_name)
        # `submit` needs to know the canonical project to point the PR at.
        # Naming it `upstream` follows the standard fork workflow convention.
        @git.add_remote(local_path, "upstream",
                        "https://github.com/#{project.owner}/#{project.repo}.git")

        print_summary(local_path, branch_name, project, viewer)
        announce_or_skip(adapter, project, issue, viewer, was_resuming: was_resuming, flags: flags)
        @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
        0
      end

      def clone_exists?(project)
        target = File.join(@clone_root, project.owner, project.repo)
        File.directory?(File.join(target, ".git"))
      end

      def announce_or_skip(adapter, project, issue, viewer, was_resuming:, flags:)
        return if flags[:no_comment]
        return if was_resuming
        return if viewer == project.owner
        return unless @config.comment_on_fix?("#{project.owner}/#{project.repo}")

        IssueAnnouncer.announce_working(
          adapter: adapter, project: project, issue: issue,
          stdout: @stdout, stderr: @stderr
        )
      end

      def print_summary(local_path, branch_name, project, viewer)
        @stdout.puts "Forked, cloned, and branched."
        @stdout.puts "  path:   #{local_path}"
        @stdout.puts "  branch: #{branch_name}"
        @stdout.puts "  upstream: https://github.com/#{project.owner}/#{project.repo}"
        @stdout.puts "  fork:     https://github.com/#{viewer}/#{project.repo}"
        @stdout.puts
        @stdout.puts "Next: cd #{local_path} && make your changes, then `gem-contribute submit`."
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

      def push(path, remote, branch)
        run!(["git", "-C", path, "push", "-u", remote, branch])
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
