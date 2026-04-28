# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module GemContribute
  # Resolves a LockedGem to a Project (host + owner + repo) by querying the
  # RubyGems v1 API and walking the metadata URIs in preference order.
  #
  # Preference order (ADR-0003):
  #   bug_tracker_uri  →  source_code_uri  →  homepage_uri
  #
  # Recognized hosts: github.com, gitlab.com, codeberg.org. Anything else
  # (mailing-list bug tracker, internal bugzilla, etc.) is stored as the
  # `:source_url` in metadata so the user can at least see it.
  class Resolver
    API_BASE = "https://rubygems.org/api/v1/gems"
    KNOWN_HOSTS = %w[github.com gitlab.com codeberg.org].freeze

    # Reasons a resolve might come back without a host coordinate. Surfaced as
    # `metadata[:reason]` on the returned Project so the CLI/TUI can show the
    # user *why* a gem wasn't actionable.
    REASON_NON_RUBYGEMS_SOURCE = :non_rubygems_source
    REASON_API_NOT_FOUND = :api_not_found
    REASON_NO_USABLE_URI = :no_usable_uri
    REASON_UNKNOWN_HOST = :unknown_host

    def initialize(cache: Cache.new, http: Net::HTTP, clock: -> { Time.now.to_i })
      @cache = cache
      @http = http
      @clock = clock
    end

    # @param gem [LockedGem]
    # @return [Project]
    def resolve(gem)
      return unresolved(gem, REASON_NON_RUBYGEMS_SOURCE) unless gem.resolvable?

      metadata = fetch_metadata(gem)
      return unresolved(gem, REASON_API_NOT_FOUND) if metadata.nil?

      uri = preferred_uri(metadata)
      return unresolved(gem, REASON_NO_USABLE_URI) if uri.nil?

      coords = parse_host_coordinates(uri)
      return unresolved(gem, REASON_UNKNOWN_HOST, source_url: uri) if coords.nil?

      Project.new(
        gem_name: gem.name,
        host: coords[:host],
        owner: coords[:owner],
        repo: coords[:repo],
        metadata: { source_url: uri, picked_from: coords[:picked_from] }
      )
    end

    private

    def unresolved(gem, reason, **extras)
      Project.new(
        gem_name: gem.name,
        host: :unknown,
        owner: nil,
        repo: nil,
        metadata: { reason: reason, **extras }
      )
    end

    def fetch_metadata(gem)
      cached = @cache.fetch("gems", gem.name)
      return cached if cached

      response = http_get("#{API_BASE}/#{gem.name}.json")
      case response
      when Net::HTTPSuccess
        @cache.write("gems", gem.name, JSON.parse(response.body))
      when Net::HTTPNotFound
        nil
      else
        raise ResolveError.new(gem.name, "RubyGems API returned #{response.code}")
      end
    end

    def http_get(url)
      uri = URI(url)
      @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |conn|
        conn.get(uri.request_uri, "Accept" => "application/json", "User-Agent" => user_agent)
      end
    end

    def user_agent
      "gem-contribute/#{GemContribute::VERSION}"
    end

    def preferred_uri(metadata)
      # Order matters. ADR-0003.
      candidates = [
        ["bug_tracker_uri", metadata["bug_tracker_uri"]],
        ["source_code_uri", metadata["source_code_uri"]],
        ["homepage_uri", metadata["homepage_uri"]]
      ]
      candidates.each do |label, value|
        next if value.nil? || value.empty?

        @last_picked = label
        return value
      end
      nil
    end

    def parse_host_coordinates(url)
      uri = safe_uri(url)
      return nil if uri.nil? || uri.host.nil? || uri.path.nil?

      host = uri.host.sub(/\Awww\./, "")
      return nil unless KNOWN_HOSTS.include?(host)

      owner, repo = uri.path.delete_prefix("/").split("/", 3)
      return nil if owner.to_s.empty? || repo.to_s.empty?

      { host: host, owner: owner, repo: repo.sub(/\.git\z/, ""), picked_from: @last_picked }
    end

    def safe_uri(url)
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end
  end
end
