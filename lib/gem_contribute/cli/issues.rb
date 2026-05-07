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
      include Workflow

      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     resolver: Resolver.new,
                     adapter: HostAdapters::GitHubAdapter.new,
                     lockfile_path: "Gemfile.lock",
                     config: GemContribute::Config.new)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
        @resolver = resolver
        @adapter = adapter
        @lockfile_path = lockfile_path
        @config = config
      end

      def run(argv)
        target = argv.shift
        return print_usage if target.nil?

        @claim_index = IssueAnnouncer.fetch_claim_index(@adapter)
        status = target == "all" ? run_all : run_single(target)
        RateLimitFooter.print(adapter: @adapter, output: @output)
        status
      rescue AdapterError => e
        @output.error("gem-contribute: #{e.message}")
        1
      end

      private

      def print_usage
        @output.error("Usage: gem-contribute issues <gem|all>")
        2
      end

      def run_single(target)
        project = resolve_target(target, verb: "issues")
        return 1 if project.nil?

        list_issues(project)
      end

      def run_all
        gems = LockfileParser.parse(@lockfile_path)
        projects = gems.filter_map do |gem|
          project = @resolver.resolve(gem)
          project if project.host == "github.com"
        end

        @output.info("Scanning #{projects.size} github.com gems from #{@lockfile_path}...\n")

        issues_by_repo = batch_fetch_issues(projects)
        print_all_project_issues(projects, issues_by_repo)
        0
      rescue LockfileNotFound => e
        @output.error("gem-contribute: #{e.message}")
        1
      end

      def print_all_project_issues(projects, issues_by_repo)
        any = false
        projects.each do |project|
          issues = issues_by_repo["#{project.owner}/#{project.repo}"] || []
          next if issues.empty?

          any = true
          print_project_issues(project, issues)
        end
        @output.info("(no contributable issues found across #{projects.size} gems)") unless any
      end

      def batch_fetch_issues(projects)
        @adapter.issues_matching_labels(projects, labels: @config.preferred_labels)
      rescue AdapterError => e
        @output.warn("  warning: issue search failed: #{e.message}")
        {}
      end

      def issues_for_project(project)
        by_repo = @adapter.issues_matching_labels([project], labels: @config.preferred_labels)
        by_repo["#{project.owner}/#{project.repo}"] || []
      end

      def list_issues(project)
        issues = issues_for_project(project)
        print_project_issues(project, issues)
        @output.info("To contribute: gem-contribute fix #{project.gem_name}/<issue#>")
        0
      end

      def print_project_issues(project, issues)
        repo_url = "https://github.com/#{project.owner}/#{project.repo}"
        @output.info("#{project.gem_name} — #{issues.size} open contributable issues (#{repo_url})")

        if issues.empty?
          @output.info("  (none — browse #{repo_url}/issues directly)")
        else
          @output.info("")
          print_issue_list(project, issues)
        end
      end

      def print_issue_list(project, issues)
        claimed = @claim_index["#{project.owner}/#{project.repo}"] || []
        issues.each do |issue|
          label = claimed.include?(issue["number"]) ? "[claimed] " : ""
          @output.info("  ##{issue["number"]}  #{label}#{issue["title"]}")
          @output.info("        #{issue["html_url"]}")
          @output.info("")
        end
      end
    end
  end
end
