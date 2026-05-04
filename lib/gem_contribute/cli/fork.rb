# frozen_string_literal: true

require "dry/initializer"
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
      extend Dry::Initializer
      include Workflow
      include Dry::Monads[:result]

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")

      option :stdout, default: -> { $stdout }
      option :stderr, default: -> { $stderr }
      option :output, default: -> { Output::Standard.new(out: stdout, err: stderr) }
      option :resolver, default: -> { Resolver.new }
      option :store, default: -> { TokenStore.new }
      option :adapter_factory,
             default: -> { ->(token:) { HostAdapters::GitHubAdapter.new(token: token) } }
      option :git, default: -> { GemContribute::Git.new }
      option :clone_root, default: -> { DEFAULT_CLONE_ROOT }
      option :post_clone_hooks, default: -> { PostCloneHooks.new(output: output) }
      option :fork_op, default: -> { Operations::Fork.new }
      option :clone_op, default: -> { Operations::Clone.new(git: git) }

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
          @output.error("Not authenticated. Run `gem-contribute auth login` first.")
          1
        end
      end

      # The bootstrap primitive Fix shares: fork (or reuse) → clone (or
      # reuse) → upstream remote. Returns `Success([local_path, fork_info])`
      # on the happy path; `Failure(reason)` propagated from Operations
      # otherwise.
      def bootstrap(adapter, project)
        @output.progress("Forking #{project.owner}/#{project.repo}...")
        fork_result = @fork_op.call(adapter: adapter, project: project)
        return fork_result if fork_result.failure?

        fork_info = fork_result.value!
        @output.info(fork_status_line(fork_info, project))

        clone_result = @clone_op.call(adapter: adapter, project: project,
                                      fork_clone_url: fork_info.clone_url, root: @clone_root)
        return clone_result if clone_result.failure?

        clone_info = clone_result.value!
        @output.info(clone_status_line(clone_info))

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
        @output.error("Usage: gem-contribute fork <gem|owner/repo> [-e] [-a]")
        2
      end

      def execute(adapter, project, flags)
        case bootstrap(adapter, project)
        in Success(local_path, fork_info)
          print_summary(local_path, project, fork_info)
          @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
          0
        in Failure(:unauthenticated)
          @output.error("Not authenticated. Run `gem-contribute auth login` first.")
          1
        in Failure(:adapter_error, message)
          @output.error("fork failed: #{message}")
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
        @output.info("Forked and cloned. You're on the default branch.")
        @output.info("  path:     #{local_path}")
        @output.info("  upstream: #{fork_info.upstream_url}")
        @output.info("  fork:     #{fork_info.fork_url}")
        @output.info("")
        @output.info("Next: cd #{local_path} && explore. When you pick an issue, " \
                     "`gem-contribute fix #{project.gem_name}/<issue#>` " \
                     "branches off the default.")
      end
    end
  end
end
