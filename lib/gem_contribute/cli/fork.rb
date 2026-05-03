# frozen_string_literal: true

require "fileutils"

module GemContribute
  module CLI
    # `gem-contribute fork <gem|owner/repo> [-e] [-a]` and the underlying
    # bootstrap primitive used by `fix`.
    #
    # Two faces, same operation:
    # - `Fork#run(argv)` — the CLI verb. Resolve, fork+clone, summary, hooks.
    # - `Fork#call(adapter, project, viewer)` — the primitive. Idempotent
    #   fork (or reuse) + clone (or reuse) + upstream remote, returns the
    #   local clone path. `Fix` delegates to this for its bootstrap step.
    class Fork
      include Workflow

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")
      FORK_READINESS_RETRIES = 12 # 12 × 5s = 60s ceiling
      FORK_READINESS_INTERVAL = 5

      # rubocop:disable Metrics/ParameterLists
      def initialize(stdout: $stdout, stderr: $stderr,
                     resolver: Resolver.new, store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     sleeper: ->(s) { Kernel.sleep(s) },
                     post_clone_hooks: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @git = git
        @clone_root = clone_root
        @sleeper = sleeper
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
      end
      # rubocop:enable Metrics/ParameterLists

      # Public primitive. Idempotent: reuses an existing fork (via
      # `already_forked?`) and an existing local clone (via the `.git`
      # directory). Returns the local clone path.
      def call(adapter, project, viewer)
        clone_url = ensure_fork(adapter, project, viewer)
        local_path = clone_into_root(project, clone_url)
        # `submit` needs to know the canonical project to point the PR at.
        # `upstream` follows the standard fork workflow convention.
        @git.add_remote(local_path, "upstream",
                        "https://github.com/#{project.owner}/#{project.repo}.git")
        local_path
      end

      def run(argv)
        with_workflow_rescues("fork") do
          return missing_clone_root if @clone_root.nil?

          target, flags = parse_argv(argv)
          return print_usage_error if target.nil?

          adapter = build_adapter
          return 1 if adapter.nil?

          project = resolve_target(target, verb: "fork", allow_owner_repo: true)
          return 1 if project.nil?

          execute(adapter, project, flags)
        end
      end

      private

      def parse_argv(argv)
        flags = { editor: false, ai_tool: false }
        positional = []
        argv.each do |arg|
          case arg
          when "-e", "--editor" then flags[:editor] = true
          when "-a", "--ai"     then flags[:ai_tool] = true
          else positional << arg
          end
        end
        [positional.first, flags]
      end

      def print_usage_error
        @stderr.puts "Usage: gem-contribute fork <gem|owner/repo> [-e] [-a]"
        2
      end

      def execute(adapter, project, flags)
        viewer = adapter.viewer_login
        local_path = call(adapter, project, viewer)

        print_summary(local_path, project, viewer)
        @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
        0
      end

      def print_summary(local_path, project, viewer)
        @stdout.puts "Forked and cloned. You're on the default branch."
        @stdout.puts "  path:     #{local_path}"
        @stdout.puts "  upstream: https://github.com/#{project.owner}/#{project.repo}"
        @stdout.puts "  fork:     https://github.com/#{viewer}/#{project.repo}"
        @stdout.puts
        @stdout.puts "Next: cd #{local_path} && explore. When you pick an issue, " \
                     "`gem-contribute fix #{project.gem_name}/<issue#>` " \
                     "branches off the default."
      end

      # === Primitive helpers (private) ===

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

        raise GemContribute::AdapterError,
              "fork not reachable after #{FORK_READINESS_RETRIES * FORK_READINESS_INTERVAL}s"
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
  end
end
