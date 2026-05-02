# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute fork <gem> [-e] [-a]`
    #
    # The look-around-first path: fork + clone + upstream remote, leave
    # the user on the default branch. Use this when you want to explore
    # a project before committing to a specific issue.
    # `gem-contribute fix <gem>/<issue>` is the issue-tied counterpart;
    # both compose the same `ForkClone` primitive.
    class Fork
      include Workflow

      DEFAULT_CLONE_ROOT = File.expand_path("~/code/oss")

      # rubocop:disable Metrics/ParameterLists
      def initialize(stdout: $stdout, stderr: $stderr,
                     resolver: Resolver.new, store: TokenStore.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     git: Git.new,
                     clone_root: DEFAULT_CLONE_ROOT,
                     sleeper: ->(s) { Kernel.sleep(s) },
                     fork_clone: nil,
                     post_clone_hooks: nil)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @store = store
        @adapter_factory = adapter_factory
        @clone_root = clone_root
        @fork_clone = fork_clone || ForkClone.new(stdout: stdout, git: git,
                                                  clone_root: clone_root, sleeper: sleeper)
        @post_clone_hooks = post_clone_hooks || PostCloneHooks.new(stdout: stdout, stderr: stderr)
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
        local_path = @fork_clone.call(adapter, project, viewer)

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
    end
  end
end
