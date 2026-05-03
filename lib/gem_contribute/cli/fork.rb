# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute fork <gem|owner/repo> [-e] [-a]`. Resolve the target,
    # bootstrap a fork+clone via `Operations::Fork` + `Operations::Clone`,
    # print a summary, run post-clone hooks. The CLI verb is a thin
    # composition; the host-API ceremony lives in the adapter and the
    # filesystem policy lives in Operations (ADR-0011).
    class Fork
      include Workflow

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")

      # rubocop:disable Metrics/ParameterLists
      def initialize(stdout: $stdout, stderr: $stderr,
                     resolver: Resolver.new, store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: GemContribute::Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     post_clone_hooks: nil,
                     fork_op: nil, clone_op: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @clone_root = clone_root
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
        @fork_op = fork_op || Operations::Fork.new(stdout: stdout)
        @clone_op = clone_op || Operations::Clone.new(git: git, stdout: stdout)
      end
      # rubocop:enable Metrics/ParameterLists

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

      # The bootstrap primitive Fix shares: fork (or reuse) → clone (or
      # reuse) → upstream remote. Returns `[local_path, fork_info]` where
      # `fork_info` is an `Operations::Fork::Result`.
      def bootstrap(adapter, project)
        fork_info = @fork_op.call(adapter: adapter, project: project)
        local_path = @clone_op.call(adapter: adapter, project: project,
                                    fork_clone_url: fork_info.clone_url, root: @clone_root)
        [local_path, fork_info]
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
        local_path, fork_info = bootstrap(adapter, project)

        print_summary(local_path, project, fork_info)
        @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
        0
      end

      def print_summary(local_path, project, fork_info)
        @stdout.puts "Forked and cloned. You're on the default branch."
        @stdout.puts "  path:     #{local_path}"
        @stdout.puts "  upstream: #{fork_info.upstream_url}"
        @stdout.puts "  fork:     #{fork_info.fork_url}"
        @stdout.puts
        @stdout.puts "Next: cd #{local_path} && explore. When you pick an issue, " \
                     "`gem-contribute fix #{project.gem_name}/<issue#>` " \
                     "branches off the default."
      end
    end
  end
end
