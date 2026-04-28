# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module GemContribute
  module HostAdapters
    # GitHub adapter. v0.1 implements the unauthenticated read methods
    # (issues, community_profile, file_contents). The auth-required methods
    # raise AuthRequired so the calling layer (CLI in Stage 2, TUI in Stage 3)
    # can trigger device flow. See ADR-0001 and ADR-0004.
    #
    # `token` is optional and reserved for Stage 2; when present it's sent as
    # `Authorization: Bearer …` to lift the rate limit and unlock fork/etc.
    class GitHubAdapter < HostAdapter
      API_BASE = "https://api.github.com"
      ACCEPT = "application/vnd.github+json"
      API_VERSION = "2022-11-28"

      RateLimit = Data.define(:limit, :remaining, :reset_at)

      attr_reader :rate_limit

      def initialize(cache: Cache.new, http: Net::HTTP, token: nil)
        super()
        @cache = cache
        @http = http
        @token = token
        @rate_limit = nil
      end

      # @return [Array<Hash>] open issues filtered to the given labels (if any)
      def issues(project, labels: nil)
        ensure_known_host!(project)

        cache_key = issue_cache_key(project, labels)
        cached = @cache.fetch("issues", cache_key)
        return cached if cached

        params = { state: "open", per_page: 50 }
        params[:labels] = Array(labels).join(",") if labels && !Array(labels).empty?
        body = get_json("/repos/#{project.owner}/#{project.repo}/issues", params)

        # GitHub's /issues endpoint mixes pull requests in. PRs have a
        # `pull_request` key; filter those out so callers see issues only.
        only_issues = body.reject { |i| i.key?("pull_request") }
        @cache.write("issues", cache_key, only_issues)
      end

      def community_profile(project)
        ensure_known_host!(project)
        cache_key = "#{project.owner}/#{project.repo}"
        cached = @cache.fetch("repos", cache_key)
        return cached if cached

        body = get_json("/repos/#{project.owner}/#{project.repo}/community/profile")
        @cache.write("repos", cache_key, body)
      end

      def file_contents(project, path)
        ensure_known_host!(project)
        cache_key = "#{project.owner}/#{project.repo}:#{path}"
        cached = @cache.fetch("files", cache_key)
        return cached if cached

        body = get_json("/repos/#{project.owner}/#{project.repo}/contents/#{path}")
        @cache.write("files", cache_key, body)
      end

      def fork(_project)
        raise AuthRequired, "github.com" unless @token

        raise NotImplementedError, "fork is implemented in Stage 2"
      end

      def already_forked?(_project)
        raise AuthRequired, "github.com" unless @token

        raise NotImplementedError, "already_forked? is implemented in Stage 2"
      end

      private

      def issue_cache_key(project, labels)
        label_segment = Array(labels).sort.join(",")
        "#{project.owner}/#{project.repo}?labels=#{label_segment}"
      end

      def ensure_known_host!(project)
        return if project.host == "github.com"

        raise AdapterError, "GitHubAdapter cannot serve project on host #{project.host.inspect}"
      end

      def get_json(path, params = {})
        response = http_get(path, params)
        record_rate_limit(response)
        decode_response(response, path)
      end

      def http_get(path, params)
        url = URI("#{API_BASE}#{path}")
        url.query = URI.encode_www_form(params) unless params.empty?
        @http.start(url.host, url.port, use_ssl: true) do |conn|
          conn.get(url.request_uri, request_headers)
        end
      end

      def decode_response(response, path)
        case response
        when Net::HTTPSuccess then JSON.parse(response.body)
        when Net::HTTPUnauthorized, Net::HTTPForbidden
          raise AuthRequired, "github.com" if @token.nil?

          raise AdapterError, "GitHub returned #{response.code}: #{response.body}"
        else
          raise AdapterError, "GitHub returned #{response.code} for #{path}"
        end
      end

      def request_headers
        headers = {
          "Accept" => ACCEPT,
          "User-Agent" => "gem-contribute/#{GemContribute::VERSION}",
          "X-GitHub-Api-Version" => API_VERSION
        }
        headers["Authorization"] = "Bearer #{@token}" if @token
        headers
      end

      def record_rate_limit(response)
        limit = response["X-RateLimit-Limit"]
        remaining = response["X-RateLimit-Remaining"]
        reset = response["X-RateLimit-Reset"]
        return if [limit, remaining, reset].any?(&:nil?)

        @rate_limit = RateLimit.new(
          limit: limit.to_i,
          remaining: remaining.to_i,
          reset_at: Time.at(reset.to_i)
        )
      end
    end
  end
end
