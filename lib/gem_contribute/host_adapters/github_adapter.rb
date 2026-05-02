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
    #
    # Class length: this adapter wraps a growing surface area of GitHub
    # endpoints (issues, comments, forks, community profile, contents). The
    # 150-line metric isn't a useful constraint here — we'd just split into
    # arbitrary sub-modules — so it's disabled below with this rationale.
    # rubocop:disable Metrics/ClassLength
    class GitHubAdapter < HostAdapter
      API_BASE = "https://api.github.com"
      ACCEPT = "application/vnd.github+json"
      API_VERSION = "2022-11-28"
      MAX_REDIRECTS = 3

      RateLimit = Data.define(:limit, :remaining, :reset_at)

      attr_reader :rate_limit

      def initialize(cache: Cache.new, http: Net::HTTP, token: nil)
        super()
        @cache = cache
        @http = http
        @token = token
        @rate_limit = nil
      end

      # @return [Hash] a single issue's full payload (uncached — submit only).
      def issue(owner, repo, number)
        ensure_known_host!(Project.new(gem_name: repo, host: "github.com",
                                       owner: owner, repo: repo, metadata: {}))
        get_json("/repos/#{owner}/#{repo}/issues/#{number}")
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

      # POST /repos/:owner/:repo/forks. Returns the fork's parsed body
      # (clone_url, owner.login, name, etc.). GitHub responds 202 (accepted)
      # immediately even if the fork is still propagating; callers that need
      # to clone right after may want to poll readiness — see
      # `fork_ready?` below.
      def fork(project)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        post_json("/repos/#{project.owner}/#{project.repo}/forks")
      end

      # GET /repos/:viewer/:repo. True iff the viewer already owns a fork of
      # the upstream repo at the same name.
      def already_forked?(project)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        viewer = viewer_login
        get_json("/repos/#{viewer}/#{project.repo}")
        true
      rescue AdapterError => e
        return false if e.message.include?("404")

        raise
      end

      # GET /user. Used by `auth status` and `already_forked?`. Returns the
      # authenticated user's login string (e.g. "cdhagmann").
      def viewer_login
        raise AuthRequired, "github.com" unless @token

        body = get_json("/user")
        body.fetch("login")
      end

      # GET /repos/:viewer/:repo, returning true once GitHub has finished
      # provisioning the fork. The fork endpoint returns 202 immediately;
      # the resource may 404 for a few seconds before becoming live.
      def fork_ready?(viewer, repo_name)
        raise AuthRequired, "github.com" unless @token

        get_json("/repos/#{viewer}/#{repo_name}")
        true
      rescue AdapterError => e
        return false if e.message.include?("404")

        raise
      end

      # POST /repos/:owner/:repo/issues/:n/comments. Returns the created
      # comment payload (id, body, html_url, ...). Used by `fix` to post
      # the "working on this" announcement.
      def comment_on_issue(project, issue_number, body)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        post_json("/repos/#{project.owner}/#{project.repo}/issues/#{issue_number}/comments",
                  { "body" => body })
      end

      # GET /repos/:owner/:repo/issues/:n/comments. Returns an array of
      # comment payloads. Uncached (callers may want fresh data, e.g. to
      # check for an idempotency marker).
      def issue_comments(project, issue_number)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        get_json("/repos/#{project.owner}/#{project.repo}/issues/#{issue_number}/comments")
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

      def post_json(path, body = nil)
        response = http_post(path, body)
        record_rate_limit(response)
        decode_response(response, path)
      end

      def http_get(path, params, redirects_remaining: MAX_REDIRECTS)
        url = URI("#{API_BASE}#{path}")
        url.query = URI.encode_www_form(params) unless params.empty?
        response = @http.start(url.host, url.port, use_ssl: true) do |conn|
          conn.get(url.request_uri, request_headers)
        end

        if response.is_a?(Net::HTTPMovedPermanently) && redirects_remaining.positive?
          new_path = URI(response["Location"]).path
          return http_get(new_path, params, redirects_remaining: redirects_remaining - 1)
        end

        response
      end

      def http_post(path, body)
        url = URI("#{API_BASE}#{path}")
        @http.start(url.host, url.port, use_ssl: true) do |conn|
          request = Net::HTTP::Post.new(url.request_uri, request_headers.merge("Content-Type" => "application/json"))
          request.body = JSON.dump(body) if body
          conn.request(request)
        end
      end

      def decode_response(response, path)
        case response
        when Net::HTTPNoContent then nil
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
    # rubocop:enable Metrics/ClassLength
  end
end
