# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute scan [path]` — Stage 1's command.
    #
    # Reads a Gemfile.lock, resolves each rubygems-sourced gem, hits the
    # GitHub adapter for `good first issue`-tagged issue counts on every
    # github.com project, and prints:
    #
    #   <N> gems · <N> on github.com · <N> on <other> · <N> unknown source
    #
    #   Top contributable projects (by open `good first issue` count):
    #     <gem-name>  <count>  <github.com/owner/repo>
    #     ...
    class Scan
      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     resolver: Resolver.new,
                     adapter: HostAdapters::GitHubAdapter.new,
                     config: GemContribute::Config.new)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
        @resolver = resolver
        @adapter = adapter
        @config = config
      end

      # @param argv [Array<String>] passed-in args (no leading "scan")
      # @return [Integer] exit status
      def run(argv)
        path = argv.first || "Gemfile.lock"
        gems = LockfileParser.parse(path)
        @output.progress("Scanning #{path} (#{gems.size} gems)...")

        projects = gems.map { |gem| @resolver.resolve(gem) }
        # Summary tally reflects only the lockfile contents — the
        # self-injection is intentionally additive, not part of the count.
        print_summary(tally_hosts(projects), gems.size)
        scan_github_projects(projects)
        RateLimitFooter.print(adapter: @adapter, output: @output)
        0
      rescue LockfileNotFound => e
        @output.error("gem-contribute: #{e.message}")
        1
      rescue Errno::ECONNREFUSED, SocketError => e
        @output.error("gem-contribute: network unreachable (#{e.class}: #{e.message})")
        @output.error("Re-run when you have connectivity, or use cached data with --refresh disabled.")
        1
      end

      private

      def inject_self(github_projects)
        return github_projects if github_projects.any? { |p| p.gem_name == GemContribute::SELF_PROJECT.gem_name }

        github_projects + [GemContribute::SELF_PROJECT]
      end

      def scan_github_projects(projects)
        github_from_lockfile = projects.select { |p| p.host == "github.com" }
        @output.info("\nNo github.com projects in this lockfile.") if github_from_lockfile.empty?

        ranked = rank_by_issue_count(inject_self(github_from_lockfile))
        return if ranked.empty?

        claim_index = IssueAnnouncer.fetch_claim_index(@adapter)
        print_ranked(ranked, claim_index)
      end

      def tally_hosts(projects)
        counts = Hash.new(0)
        projects.each { |p| counts[p.host] += 1 }
        counts
      end

      def print_summary(host_counts, total)
        parts = ["#{total} gems"]
        host_counts.each do |host, count|
          label = host == :unknown ? "unknown source" : "on #{host}"
          parts << "#{count} #{label}"
        end
        @output.info(parts.join(" · "))
      end

      def rank_by_issue_count(projects)
        issues_by_repo = fetch_issues_for_projects(projects)
        results = projects.map do |project|
          count = (issues_by_repo["#{project.owner}/#{project.repo}"] || []).size
          [project, count]
        end
        results.reject { |_, count| count.zero? }.sort_by { |_, count| -count }
      end

      def fetch_issues_for_projects(projects)
        @adapter.issues_matching_labels(projects, labels: @config.preferred_labels)
      rescue AdapterError, AuthRequired => e
        @output.warn("  warning: issue search failed: #{e.message}")
        {}
      end

      def print_ranked(ranked, claim_index)
        @output.info("")
        @output.info("Top contributable projects (by open `good first issue` count):")
        col_name = ranked.map { |p, _| p.gem_name.length }.max
        ranked.each do |project, count|
          location = "#{project.host}/#{project.owner}/#{project.repo}"
          claimed = claim_index["#{project.owner}/#{project.repo}"] || []
          suffix = claimed.empty? ? "" : "  · #{claimed.size} claimed"
          @output.info(format("  %-#{col_name}s  %3d  %s%s", project.gem_name, count, location, suffix))
        end
      end
    end
  end
end
