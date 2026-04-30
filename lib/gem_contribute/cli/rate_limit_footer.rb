# frozen_string_literal: true

module GemContribute
  module CLI
    # Prints a one-line GitHub rate-limit footer after `scan` or `issues`
    # finishes its main output, when the adapter has rate-limit data.
    #
    # Format: "GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC"
    #
    # When `adapter.rate_limit` is nil (e.g. every call was served from cache),
    # nothing is printed — see #4 acceptance criteria.
    module RateLimitFooter
      module_function

      # @param adapter [GemContribute::HostAdapters::GitHubAdapter]
      # @param stdout [IO]
      def print(adapter:, stdout: $stdout)
        rate_limit = adapter.respond_to?(:rate_limit) ? adapter.rate_limit : nil
        return if rate_limit.nil?

        remaining = format_with_separators(rate_limit.remaining)
        limit = format_with_separators(rate_limit.limit)
        reset = rate_limit.reset_at.utc.strftime("%H:%M")
        stdout.puts "GitHub rate limit: #{remaining} / #{limit} remaining · resets at #{reset} UTC"
      end

      def format_with_separators(integer)
        integer.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
    end
  end
end
