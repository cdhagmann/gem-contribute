# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module CLI
    # `gem-contribute fix <gem>/<issue#> [-e] [-a] [--no-comment]`
    #
    # The issue-tied path: bootstrap a fork+clone (delegated to `CLI::Fork`'s
    # primitive, which composes `Operations::Fork` and `Operations::Clone`),
    # then branch to `gem-contribute/issue-<N>`, post a "working on this"
    # comment (skippable), optionally open the user's editor or AI tool.
    class Fix
      include Workflow
      include Dry::Monads[:result]

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")
      BRANCH_PREFIX = "gem-contribute/issue-"

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
                     fork: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @git = git
        @clone_root = clone_root
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
        @config = config || GemContribute::Config.new
        @fork = fork || Fork.new(stdout: stdout, stderr: stderr,
                                 resolver: resolver, store: store,
                                 adapter_factory: adapter_factory,
                                 git: @git, clone_root: clone_root,
                                 post_clone_hooks: @post_clone_hooks)
      end
      # rubocop:enable Metrics/ParameterLists

      def run(argv)
        with_workflow_rescues("fix") do
          return missing_clone_root if @clone_root.nil?

          target, flags = parse_argv(argv)
          return print_usage_error if target.nil? || !target.include?("/")

          gem_name, issue = target.split("/", 2)
          adapter = build_adapter
          return 1 if adapter.nil?

          project = resolve_target(gem_name, verb: "fix")
          return 1 if project.nil?

          execute(adapter, project, issue, flags)
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
        was_resuming = branch_exists_locally?(project, issue)

        case @fork.bootstrap(adapter, project)
        in Success(local_path, fork_info)
          finish_fix(adapter, project, issue, flags, local_path, fork_info, was_resuming: was_resuming)
        in Failure(:unauthenticated)
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          1
        in Failure(:adapter_error, message)
          @stderr.puts "fix failed: #{message}"
          1
        end
      end

      def finish_fix(adapter, project, issue, flags, local_path, fork_info, was_resuming:)
        branch_name = "#{BRANCH_PREFIX}#{issue}"
        @git.checkout_branch(local_path, branch_name)

        print_summary(local_path, branch_name, fork_info)
        announce_or_skip(adapter, project, issue, fork_info.viewer,
                         was_resuming: was_resuming, flags: flags)
        @post_clone_hooks.call(local_path, editor: flags[:editor], ai_tool: flags[:ai_tool])
        0
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

      # True if `gem-contribute/issue-<N>` already exists locally — the
      # user is resuming this specific issue (the clone is shared across
      # issues in the same repo, but the branch is per-issue).
      def branch_exists_locally?(project, issue)
        target = File.join(@clone_root, project.owner, project.repo)
        return false unless File.directory?(File.join(target, ".git"))

        @git.branch_exists?(target, "#{BRANCH_PREFIX}#{issue}")
      end

      def announce_or_skip(adapter, project, issue, viewer, was_resuming:, flags:)
        return unless should_announce?(project, viewer, was_resuming: was_resuming, flags: flags)

        IssueAnnouncer.announce_working(
          adapter: adapter, project: project, issue: issue,
          stdout: @stdout, stderr: @stderr
        )
      end

      def should_announce?(project, viewer, was_resuming:, flags:)
        !flags[:no_comment] &&
          !was_resuming &&
          viewer != project.owner &&
          @config.comment_on_fix?("#{project.owner}/#{project.repo}")
      end
    end
  end
end
