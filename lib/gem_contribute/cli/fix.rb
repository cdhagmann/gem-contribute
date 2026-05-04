# frozen_string_literal: true

require "dry/initializer"
require "dry/monads"

module GemContribute
  module CLI
    # `gem-contribute fix <gem>/<issue#> [-e] [-a] [--no-comment]`
    #
    # The issue-tied path: run `Operations::FixPipeline` (Fork → Clone →
    # Branch → Announce), then optionally open the user's editor or AI
    # tool. The verb is a thin Result-pattern-matching shell around the
    # pipeline (per ADR-0012).
    class Fix
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
      option :config, default: -> { GemContribute::Config.new }
      option :pipeline, default: -> { Operations::FixPipeline.new(git: git) }

      def run(argv)
        return missing_clone_root if @clone_root.nil?

        target, flags = parse_argv(argv)
        return print_usage_error if target.nil? || !target.include?("/")

        gem_name, issue = target.split("/", 2)

        case build_adapter
        in Success(adapter)
          project = resolve_target(gem_name, verb: "fix")
          return 1 if project.nil?

          execute(adapter, project, issue, flags)
        in Failure(:unauthenticated)
          @output.error("Not authenticated. Run `gem-contribute auth login` first.")
          1
        end
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

      def print_usage_error
        @output.error("Usage: gem-contribute fix <gem>/<issue#> [-e] [-a]")
        2
      end

      def execute(adapter, project, issue, flags)
        allow_announce = !flags[:no_comment] &&
                         @config.comment_on_fix?("#{project.owner}/#{project.repo}")

        result = @output.progress("Forking #{project.owner}/#{project.repo}...") do
          @pipeline.call(adapter: adapter, project: project, issue: issue,
                         root: @clone_root, allow_announce: allow_announce)
        end

        case result
        in Success(fork: fork_data, clone: clone_data, branch: branch_data, announce: announce_data)
          print_summary(clone_data.path, branch_data.name, fork_data)
          print_announce_outcome(announce_data, issue)
          @post_clone_hooks.call(clone_data.path, editor: flags[:editor], ai_tool: flags[:ai_tool])
          0
        in Failure(:unauthenticated)
          @output.error("Not authenticated. Run `gem-contribute auth login` first.")
          1
        in Failure(:adapter_error, message)
          @output.error("fix failed: #{message}")
          1
        end
      end

      def print_summary(local_path, branch_name, fork_info)
        @output.info("Forked, cloned, and branched.")
        @output.info("  path:   #{local_path}")
        @output.info("  branch: #{branch_name}")
        @output.info("  upstream: #{fork_info.upstream_url}")
        @output.info("  fork:     #{fork_info.fork_url}")
        @output.info("")
        @output.info("Next: cd #{local_path} && make your changes, then `gem-contribute submit`.")
      end

      def print_announce_outcome(announce_result, issue)
        case announce_result
        in Success(:posted)
          @output.info("Posted 'working on this' comment to issue ##{issue}.")
        in Success(:skipped)
          # no output for skipped — quiet success
        in Failure(:announce_failed, message)
          @output.warn("Note: couldn't post 'working on this' comment to issue ##{issue}: " \
                       "#{message}. Continuing.")
        end
      end
    end
  end
end
