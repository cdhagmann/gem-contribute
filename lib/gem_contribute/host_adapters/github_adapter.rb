# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module GemContribute
  module HostAdapters
    # GitHub adapter. Implements the `HostAdapter` interface for github.com.
    # Public read methods work anonymously; auth-required methods raise
    # `AuthRequired` without a cached token (ADR-0001 / ADR-0004).
    #
    # `token` is optional. When present it's sent as `Authorization: Bearer …`
    # to lift the rate limit and unlock fork / comment / etc.
    #
    # Class length: this adapter wraps a growing surface area of GitHub
    # endpoints. The 150-line metric isn't a useful constraint here — we'd
    # just split into arbitrary sub-modules — so it's disabled below with
    # this rationale.
    # rubocop:disable Metrics/ClassLength
    class GitHubAdapter < HostAdapter
      API_BASE = "https://api.github.com"
      ACCEPT = "application/vnd.github+json"
      API_VERSION = "2022-11-28"
      MAX_REDIRECTS = 3

      # GitHub's POST /forks returns 202 immediately; the fork resource may
      # 404 for a few seconds while propagation finishes. Bound the wait at
      # 12 × 5s = 60s.
      FORK_READINESS_RETRIES = 12
      FORK_READINESS_INTERVAL = 5

      RateLimit = Data.define(:limit, :remaining, :reset_at)

      attr_reader :rate_limit

      def initialize(cache: Cache.new, http: Net::HTTP, token: nil,
                     sleeper: ->(s) { Kernel.sleep(s) })
        super()
        @cache = cache
        @http = http
        @token = token
        @sleeper = sleeper
        @rate_limit = nil
      end

      # @return [Hash] a single issue's full payload (uncached — submit only).
      def issue(project, number)
        ensure_known_host!(project)
        get_json("/repos/#{project.owner}/#{project.repo}/issues/#{number}")
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

      # Idempotent, blocking fork. If the viewer already owns a fork at the
      # same name, returns it as `reused: true` without a POST. Otherwise
      # POSTs to /repos/:owner/:repo/forks and polls until the fork is
      # reachable. Returns a `HostAdapter::ForkResult`.
      def fork(project)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        viewer = viewer_login
        return existing_fork_result(viewer, project, owned_upstream: true) if viewer == project.owner
        return existing_fork_result(viewer, project) if fork_exists?(viewer, project.repo)

        body = post_json("/repos/#{project.owner}/#{project.repo}/forks")
        wait_until_fork_ready(viewer, project.repo)
        new_fork_result(viewer, project, body)
      end

      # GET /user. Used by `auth status` and internally by `fork`. Returns
      # the authenticated user's login string (e.g. "cdhagmann").
      def viewer_login
        raise AuthRequired, "github.com" unless @token

        body = get_json("/user")
        body.fetch("login")
      end

      # POST /repos/:owner/:repo/issues/:n/comments. Returns the created
      # comment payload (id, body, html_url, ...). Used by `fix` to post
      # the "working on this" announcement.
      def comment(project, issue:, body:)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        post_json("/repos/#{project.owner}/#{project.repo}/issues/#{issue}/comments",
                  { "body" => body })
      end

      # GET /repos/:owner/:repo/issues/:n/comments. Returns an array of
      # comment payloads. Uncached (callers may want fresh data, e.g. to
      # check for an idempotency marker).
      def issue_comments(project, number)
        raise AuthRequired, "github.com" unless @token

        ensure_known_host!(project)
        get_json("/repos/#{project.owner}/#{project.repo}/issues/#{number}/comments")
      end

      SEARCH_BATCH_SIZE = 10

      # Fetches open issues matching ANY of the given labels across all
      # projects, batching repos 10 at a time to stay within URL length
      # limits. Returns a Hash keyed by "owner/repo" => [issue, ...].
      #
      # Uses GitHub's Search API with OR semantics for both labels and repos:
      #   is:issue state:open (label:"A" OR label:"B") repo:o/r1 repo:o/r2 …
      #
      # The Search API caps at 1 000 total results and 30 req/min; for typical
      # Gemfile.lock sizes this is not a concern.
      def issues_matching_labels(projects, labels:)
        return {} if projects.empty? || labels.empty?

        result = Hash.new { |h, k| h[k] = [] }
        projects.each_slice(SEARCH_BATCH_SIZE) do |batch|
          fetch_label_batch(batch, labels: labels).each do |issue|
            key = repo_key_from_search_result(issue)
            result[key] << issue
          end
        end
        result
      end

      # GET /search/issues. Wraps GitHub's issue search; works without auth
      # (subject to the 60/hr anonymous rate limit). Returns an array of
      # issue payloads (the search response's `items` key). Cached under the
      # `issues` namespace using the query as the key. Used to find issues
      # already claimed via the gem-contribute marker.
      def search_issues(query)
        cache_key = "search:#{query}"
        cached = @cache.fetch("issues", cache_key)
        return cached if cached

        raw = get_json("/search/issues", q: query)
        items = raw.fetch("items", [])
        @cache.write("issues", cache_key, items)
      end

      # Builds GitHub's pre-filled compare URL. The browser-based PR flow
      # (ADR-0011) means the user reviews the title/body before submitting,
      # so this method just templates — it doesn't post.
      def pull_request_url(upstream, head_owner:, head_branch:, title:, body:)
        ensure_known_host!(upstream)
        same_repo = head_owner == upstream.owner
        head = same_repo ? head_branch : "#{head_owner}:#{head_branch}"
        params = { "expand" => "1", "title" => title, "body" => body }
        "https://github.com/#{upstream.owner}/#{upstream.repo}/compare/#{head}?" \
          "#{URI.encode_www_form(params)}"
      end

      # Pure URL templating — no auth, no network. Used by Operations to
      # construct the `upstream` remote and by CLI verbs for summary output.
      def clone_url(owner, repo)
        "https://github.com/#{owner}/#{repo}.git"
      end

      def repo_url(owner, repo)
        "https://github.com/#{owner}/#{repo}"
      end

      private

      def existing_fork_result(viewer, project, owned_upstream: false)
        ForkResult.new(
          clone_url: clone_url(viewer, project.repo),
          fork_url: repo_url(viewer, project.repo),
          viewer: viewer,
          reused: true,
          owned_upstream: owned_upstream
        )
      end

      def new_fork_result(viewer, project, body)
        ForkResult.new(
          clone_url: body.fetch("clone_url", clone_url(viewer, project.repo)),
          fork_url: body.fetch("html_url", repo_url(viewer, project.repo)),
          viewer: viewer,
          reused: false,
          owned_upstream: false
        )
      end

      # GET /repos/:viewer/:repo. True iff the viewer already owns a repo at
      # that name (which, for the fork flow, means an existing fork of the
      # upstream).
      def fork_exists?(viewer, repo_name)
        get_json("/repos/#{viewer}/#{repo_name}")
        true
      rescue AdapterError => e
        return false if e.message.include?("404")

        raise
      end

      def wait_until_fork_ready(viewer, repo_name)
        ready = FORK_READINESS_RETRIES.times.any? do |i|
          break true if fork_exists?(viewer, repo_name)

          @sleeper.call(FORK_READINESS_INTERVAL) unless i == FORK_READINESS_RETRIES - 1
          false
        end
        return if ready

        raise AdapterError,
              "fork not reachable after #{FORK_READINESS_RETRIES * FORK_READINESS_INTERVAL}s"
      end

      def fetch_label_batch(projects, labels:)
        label_q = labels.map { |l| "label:\"#{l}\"" }.join(" OR ")
        repo_q  = projects.map { |p| "repo:#{p.owner}/#{p.repo}" }.join(" ")
        query   = "is:issue state:open (#{label_q}) #{repo_q}"

        cache_key = "label_batch:#{query}"
        cached = @cache.fetch("issues", cache_key)
        return cached if cached

        raw   = get_json("/search/issues", q: query, per_page: 100)
        items = raw.fetch("items", [])
        @cache.write("issues", cache_key, items)
        items
      end

      def repo_key_from_search_result(issue)
        issue.fetch("repository_url", "")
             .delete_prefix("#{API_BASE}/repos/")
      end

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
