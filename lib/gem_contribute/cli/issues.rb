# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute issues <gem|all>` — list open "good first issue" issues.
    #
    # With a gem name: lists issues for that gem.
    # With "all":     iterates every github.com gem in Gemfile.lock.
    #
    # Issue numbers appear prominently so they can be passed directly to
    # `fix <gem>/<issue#>`.
    class Issues
      DEFAULT_LABEL = "good first issue"

      def initialize(stdout: $stdout, stderr: $stderr,
                     resolver: Resolver.new,
                     adapter: HostAdapters::GitHubAdapter.new,
                     lockfile_path: "Gemfile.lock")
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @adapter = adapter
        @lockfile_path = lockfile_path
      end

      def run(argv)
        target = argv.shift
        return print_usage if target.nil?

        @claim_index = IssueAnnouncer.fetch_claim_index(@adapter)

        status = if target == "all"
                   run_all
                 else
                   project = resolve_or_fail(target)
                   if project.nil?
                     1
                   else
                     list_issues(project)
                   end
                 end
        RateLimitFooter.print(adapter: @adapter, stdout: @stdout)
        status
      rescue AdapterError => e
        @stderr.puts "gem-contribute: #{e.message}"
        1
      end

      private

      def print_usage
        @stderr.puts "Usage: gem-contribute issues <gem|all>"
        2
      end

      def run_all
        gems = LockfileParser.parse(@lockfile_path)
        projects = gems.filter_map do |gem|
          project = @resolver.resolve(gem)
          project if project.host == "github.com"
        end

        @stdout.puts "Scanning #{projects.size} github.com gems from #{@lockfile_path}...\n\n"

        any = false
        projects.each do |project|
          issues = fetch_issues(project)
          next if issues.empty?

          any = true
          print_project_issues(project, issues)
        end

        @stdout.puts "(no good first issues found across #{projects.size} gems)" unless any
        0
      rescue LockfileNotFound => e
        @stderr.puts "gem-contribute: #{e.message}"
        1
      end

      def fetch_issues(project)
        @adapter.issues(project, labels: [DEFAULT_LABEL])
      rescue AdapterError => e
        @stderr.puts "  warning: #{project.gem_name}: #{e.message}"
        []
      end

      def resolve_or_fail(gem_name)
        # gem-contribute isn't on RubyGems yet; short-circuit to the canonical
        # self-project so the tool's own issues are reachable today.
        return GemContribute::SELF_PROJECT if gem_name == GemContribute::SELF_PROJECT.gem_name

        gem = LockedGem.new(name: gem_name, version: "*",
                            source_type: :rubygems, source_uri: "https://rubygems.org/")
        project = @resolver.resolve(gem)

        if project.host != "github.com"
          @stderr.puts "#{gem_name}: resolves to #{project.host} (only github.com is supported)"
          return nil
        end

        project
      end

      def list_issues(project)
        issues = @adapter.issues(project, labels: [DEFAULT_LABEL])
        print_project_issues(project, issues)
        @stdout.puts "To contribute: gem-contribute fix #{project.gem_name}/<issue#>"
        0
      end

      def print_project_issues(project, issues)
        repo_url = "https://github.com/#{project.owner}/#{project.repo}"
        @stdout.puts "#{project.gem_name} — #{issues.size} open \"#{DEFAULT_LABEL}\" issues (#{repo_url})"

        if issues.empty?
          @stdout.puts "  (none — browse #{repo_url}/issues directly)"
        else
          @stdout.puts
          print_issue_list(project, issues)
        end
      end

      def print_issue_list(project, issues)
        claimed = @claim_index["#{project.owner}/#{project.repo}"] || []
        issues.each do |issue|
          label = claimed.include?(issue["number"]) ? "[claimed] " : ""
          @stdout.puts "  ##{issue["number"]}  #{label}#{issue["title"]}"
          @stdout.puts "        #{issue["html_url"]}"
          @stdout.puts
        end
      end
    end
  end
end
