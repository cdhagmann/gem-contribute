# frozen_string_literal: true

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
      include Workflow
      include Dry::Monads[:result]

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")

      # rubocop:disable Metrics/ParameterLists
      def initialize(stdout: $stdout,
                     stderr: $stderr,
                     resolver: Resolver.new,
                     store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: GemContribute::Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     post_clone_hooks: nil,
                     config: nil,
                     pipeline: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @clone_root = clone_root
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
        @config = config || GemContribute::Config.new
        @pipeline = pipeline || Operations::FixPipeline.new(git: git)
      end
      # rubocop:enable Metrics/ParameterLists

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
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
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
        @stderr.puts "Usage: gem-contribute fix <gem>/<issue#> [-e] [-a]"
        2
      end

      def execute(adapter, project, issue, flags)
        allow_announce = !flags[:no_comment] &&
                         @config.comment_on_fix?("#{project.owner}/#{project.repo}")

        @stdout.puts "Forking #{project.owner}/#{project.repo}..."

        case @pipeline.call(adapter: adapter, project: project, issue: issue,
                            root: @clone_root, allow_announce: allow_announce)
        in Success(fork: fork_data, clone: clone_data, branch: branch_data, announce: announce_data)
          print_summary(clone_data.path, branch_data.name, fork_data)
          print_announce_outcome(announce_data, issue)
          @post_clone_hooks.call(clone_data.path, editor: flags[:editor], ai_tool: flags[:ai_tool])
          0
        in Failure(:unauthenticated)
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          1
        in Failure(:adapter_error, message)
          @stderr.puts "fix failed: #{message}"
          1
        end
      end

      def print_summary(local_path, branch_name, fork_info)
        @stdout.puts "Forked, cloned, and branched."
        @stdout.puts "  path:   #{local_path}"
        @stdout.puts "  branch: #{branch_name}"
        @stdout.puts "  upstream: #{fork_info.upstream_url}"
        @stdout.puts "  fork:     #{fork_info.fork_url}"
        @stdout.puts
        @stdout.puts "Next: cd #{local_path} && make your changes, then `gem-contribute submit`."
      end

      def print_announce_outcome(announce_result, issue)
        case announce_result
        in Success(:posted)
          @stdout.puts "Posted 'working on this' comment to issue ##{issue}."
        in Success(:skipped)
          # no output for skipped — quiet success
        in Failure(:announce_failed, message)
          @stderr.puts "Note: couldn't post 'working on this' comment to issue ##{issue}: " \
                       "#{message}. Continuing."
        end
      end
    end
  end
end
