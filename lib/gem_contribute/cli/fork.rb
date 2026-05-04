# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module CLI
    # `gem-contribute fork <gem|owner/repo> [-e] [-a]`. Resolve the target,
    # bootstrap a fork+clone via `Operations::Fork` + `Operations::Clone`,
    # print a summary, run post-clone hooks. The CLI verb is a thin
    # composition; the host-API ceremony lives in the adapter and the
    # filesystem policy lives in Operations (ADR-0011). Operations are
    # output-free per ADR-0012; this verb does the printing.
    class Fork
      include Workflow
      include Dry::Monads[:result]

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
        @fork_op = fork_op || Operations::Fork.new
        @clone_op = clone_op || Operations::Clone.new(git: git)
      end
      # rubocop:enable Metrics/ParameterLists

      def run(argv)
        return missing_clone_root if @clone_root.nil?

        target, flags = parse_argv(argv)
        return print_usage_error if target.nil?

        case build_adapter
        in Success(adapter)
          project = resolve_target(target, verb: "fork", allow_owner_repo: true)
          return 1 if project.nil?

          execute(adapter, project, flags)
        in Failure(:unauthenticated)
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          1
        end
      end

      # The bootstrap primitive Fix shares: fork (or reuse) → clone (or
      # reuse) → upstream remote. Returns `Success([local_path, fork_info])`
      # on the happy path; `Failure(reason)` propagated from Operations
      # otherwise.
      def bootstrap(adapter, project)
        @stdout.puts "Forking #{project.owner}/#{project.repo}..."
        fork_result = @fork_op.call(adapter: adapter, project: project)
        return fork_result if fork_result.failure?

        fork_info = fork_result.value!
        @stdout.puts fork_status_line(fork_info, project)

        clone_result = @clone_op.call(adapter: adapter, project: project,
                                      fork_clone_url: fork_info.clone_url, root: @clone_root)
        return clone_result if clone_result.failure?

        clone_info = clone_result.value!
        @stdout.puts clone_status_line(clone_info)

        Success([clone_info.path, fork_info])
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
        case bootstrap(adapter, project)
        in Success(local_path, fork_info)
          print_summary(local_path, project, fork_info)
          @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
          0
        in Failure(:unauthenticated)
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          1
        in Failure(:adapter_error, message)
          @stderr.puts "fork failed: #{message}"
          1
        end
      end

      def fork_status_line(info, project)
        if info.reused
          "  Reusing existing fork at #{info.viewer}/#{project.repo}."
        else
          "  Forked → #{info.viewer}/#{project.repo}."
        end
      end

      def clone_status_line(info)
        if info.reused
          "Reusing existing clone at #{info.path}."
        else
          "Cloned into #{info.path}."
        end
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
