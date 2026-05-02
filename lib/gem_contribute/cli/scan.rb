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
      # GitHub's `labels=foo,bar` query is an AND, not an OR, so passing the
      # full set of beginner-friendly variants returns almost nothing. Stage 1
      # uses the canonical `good first issue` label only — the "render labels
      # verbatim" promise in ADR-0005 belongs to display, not to server-side
      # filtering. Future stages can call once per label and dedupe.
      DEFAULT_LABEL = "good first issue"

      def initialize(stdout: $stdout, stderr: $stderr, resolver: Resolver.new, adapter: HostAdapters::GitHubAdapter.new)
        @stdout = stdout
        @stderr = stderr
        @resolver = resolver
        @adapter = adapter
      end

      # @param argv [Array<String>] passed-in args (no leading "scan")
      # @return [Integer] exit status
      def run(argv)
        path = argv.first || "Gemfile.lock"
        gems = LockfileParser.parse(path)
        @stdout.puts "Scanning #{path} (#{gems.size} gems)..."

        projects = gems.map { |gem| @resolver.resolve(gem) }
        # Summary tally reflects only the lockfile contents — the
        # self-injection is intentionally additive, not part of the count.
        print_summary(tally_hosts(projects), gems.size)
        scan_github_projects(projects)
        RateLimitFooter.print(adapter: @adapter, stdout: @stdout)
        0
      rescue LockfileNotFound => e
        @stderr.puts "gem-contribute: #{e.message}"
        1
      rescue Errno::ECONNREFUSED, SocketError => e
        @stderr.puts "gem-contribute: network unreachable (#{e.class}: #{e.message})"
        @stderr.puts "Re-run when you have connectivity, or use cached data with --refresh disabled."
        1
      end

      private

      def inject_self(github_projects)
        return github_projects if github_projects.any? { |p| p.gem_name == GemContribute::SELF_PROJECT.gem_name }

        github_projects + [GemContribute::SELF_PROJECT]
      end

      def scan_github_projects(projects)
        github_from_lockfile = projects.select { |p| p.host == "github.com" }
        @stdout.puts "\nNo github.com projects in this lockfile." if github_from_lockfile.empty?

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
        @stdout.puts parts.join(" · ")
      end

      def rank_by_issue_count(projects)
        # We hit the API anonymously here. With a 60/hr unauthenticated rate
        # limit, scanning a 50-gem lockfile is the dominant pressure on this
        # CLI. The 7-day RubyGems and 5-min issues caches absorb most repeats.
        results = projects.map do |project|
          count = issue_count(project)
          [project, count]
        end.compact

        results.reject { |_, count| count.zero? }.sort_by { |_, count| -count }
      end

      def issue_count(project)
        issues = @adapter.issues(project, labels: [DEFAULT_LABEL])
        issues.size
      rescue AdapterError, AuthRequired => e
        @stderr.puts "  warning: #{project.gem_name} (#{project.host}/#{project.owner}/#{project.repo}): #{e.message}"
        0
      end

      def print_ranked(ranked, claim_index)
        @stdout.puts
        @stdout.puts "Top contributable projects (by open `good first issue` count):"
        col_name = ranked.map { |p, _| p.gem_name.length }.max
        ranked.each do |project, count|
          location = "#{project.host}/#{project.owner}/#{project.repo}"
          claimed = claim_index["#{project.owner}/#{project.repo}"] || []
          suffix = claimed.empty? ? "" : "  · #{claimed.size} claimed"
          @stdout.printf("  %-#{col_name}s  %3d  %s%s\n", project.gem_name, count, location, suffix)
        end
      end
    end
  end
end
