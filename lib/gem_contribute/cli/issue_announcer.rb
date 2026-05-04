# frozen_string_literal: true

module GemContribute
  module CLI
    # CLI-side helpers for the "I'm working on this" claim machinery.
    #
    # The actual posting (and gating) lives in `Operations::Announce`
    # (output-free, Result-returning) — see ADR-0012. What remains here
    # is the index-fetching used by `scan` and `issues` to flag claimed
    # issues in their output. Both halves share `Operations::Announce::WORKING_MARKER`.
    module IssueAnnouncer
      MARKER = Operations::Announce::WORKING_MARKER

      module_function

      # Builds a lookup hash of {"owner/repo" => Set<issue_number>} from
      # GitHub's issue search for our marker. Used by `scan` and `issues`
      # to flag claimed issues. One search call per process (the adapter
      # caches the result for the issues TTL). Degrades to an empty hash
      # if the search fails (anonymous rate limits, network, etc.).
      def fetch_claim_index(adapter)
        items = adapter.search_issues("\"#{MARKER}\" is:issue is:open")
        items.each_with_object(Hash.new { |h, k| h[k] = [] }) do |item, index|
          parsed = parse_issue_url(item["html_url"])
          next unless parsed

          owner, repo, number = parsed
          index["#{owner}/#{repo}"] << number
        end
      rescue GemContribute::AdapterError, GemContribute::AuthRequired
        {}
      end

      def parse_issue_url(url)
        match = url.to_s.match(%r{github\.com/([^/]+)/([^/]+)/issues/(\d+)})
        return nil unless match

        [match[1], match[2], match[3].to_i]
      end
    end
  end
end
