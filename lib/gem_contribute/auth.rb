# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module GemContribute
  # OAuth 2.0 Device Authorization Grant against github.com. See ADR-0004.
  #
  # Pure state-machine design:
  #
  #   request_device_code(client_id) → DeviceCode | raises AuthError
  #   poll(device_code, client_id)    → Result    (status: :ok | :pending |
  #                                                :slow_down | :expired |
  #                                                :denied | :error)
  #
  # The CLI orchestrates these with sleep-based polling. The future Stage 3
  # TUI wraps the same functions in Rooibos Command.http / Command.wait
  # without changing the protocol. ADR-0008 stays clean because the
  # state-transition functions don't own any I/O orchestration themselves —
  # they're pure request/response.
  module Auth
    DEVICE_CODE_URL = "https://github.com/login/device/code"
    TOKEN_URL = "https://github.com/login/oauth/access_token"
    DEFAULT_SCOPE = "public_repo"

    # OAuth App Client ID. Public by design — see ADR-0004 and MAINTAINER.md.
    # The sentinel below is intentionally unusable; replace with the real
    # value after walking through MAINTAINER.md's OAuth App registration.
    CLIENT_ID = ENV.fetch("GEM_CONTRIBUTE_CLIENT_ID", "Ov23liZNcwIo17OIVUsv")

    DeviceCode = Data.define(:device_code, :user_code, :verification_uri, :expires_at, :interval) do
      def expired?(now: Time.now)
        now >= expires_at
      end

      def with_interval(new_interval)
        self.class.new(
          device_code: device_code,
          user_code: user_code,
          verification_uri: verification_uri,
          expires_at: expires_at,
          interval: new_interval
        )
      end
    end

    # Result of one polling step.
    #
    # status:
    #   :ok        — token attached
    #   :pending   — user hasn't completed yet; poll again at the same interval
    #   :slow_down — user hasn't completed yet; back off (caller bumps interval)
    #   :expired   — device code is past its 15-minute window
    #   :denied    — user actively rejected
    #   :error     — anything else; error_message attached
    Result = Data.define(:status, :token, :scope, :error_message)

    class AuthError < GemContribute::Error
    end

    module_function

    # Step 1: request a device code.
    #
    # @return [DeviceCode]
    def request_device_code(client_id, scope: DEFAULT_SCOPE, http: Net::HTTP, clock: -> { Time.now })
      check_client_id!(client_id)

      response = post_form(DEVICE_CODE_URL, { client_id: client_id, scope: scope }, http: http)
      raise AuthError, "device code request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      raise AuthError, "device code request returned: #{body["error"]}" if body["error"]

      build_device_code(body, clock: clock)
    end

    # Step 2: one polling step. Call repeatedly until status != :pending and
    # != :slow_down.
    #
    # @return [Result]
    def poll(device_code, client_id, http: Net::HTTP)
      check_client_id!(client_id)

      response = post_form(
        TOKEN_URL,
        {
          client_id: client_id,
          device_code: device_code.device_code,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code"
        },
        http: http
      )

      build_result(response)
    end

    # Caller convention: device-flow errors are protocol states, not
    # exceptions. Network / parse errors raise. Returning a Result keeps the
    # state machine pure.
    def build_result(response)
      unless response.is_a?(Net::HTTPSuccess)
        return Result.new(status: :error, token: nil, scope: nil,
                          error_message: "HTTP #{response.code}")
      end

      body = JSON.parse(response.body)
      classify_body(body)
    end

    def classify_body(body)
      if body["access_token"]
        Result.new(status: :ok, token: body["access_token"], scope: body["scope"], error_message: nil)
      else
        case body["error"]
        when "authorization_pending"
          Result.new(status: :pending, token: nil, scope: nil, error_message: nil)
        when "slow_down"
          Result.new(status: :slow_down, token: nil, scope: nil, error_message: nil)
        when "expired_token"
          Result.new(status: :expired, token: nil, scope: nil, error_message: nil)
        when "access_denied"
          Result.new(status: :denied, token: nil, scope: nil, error_message: nil)
        else
          Result.new(status: :error, token: nil, scope: nil, error_message: body["error"] || "unknown")
        end
      end
    end

    def check_client_id!(client_id)
      return unless client_id.nil? || client_id.empty? || client_id == "FILL_ME_IN_FROM_MAINTAINER_MD"

      raise AuthError,
            "GemContribute::Auth::CLIENT_ID is not set. Walk through MAINTAINER.md to register " \
            "an OAuth App, then paste the Client ID into lib/gem_contribute/auth.rb (or set " \
            "GEM_CONTRIBUTE_CLIENT_ID in the environment for testing)."
    end

    def build_device_code(body, clock:)
      DeviceCode.new(
        device_code: body.fetch("device_code"),
        user_code: body.fetch("user_code"),
        verification_uri: body.fetch("verification_uri"),
        expires_at: clock.call + body.fetch("expires_in"),
        interval: body.fetch("interval")
      )
    end

    def post_form(url, params, http:)
      uri = URI(url)
      http.start(uri.host, uri.port, use_ssl: true) do |conn|
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = "gem-contribute/#{GemContribute::VERSION}"
        request.set_form_data(params)
        conn.request(request)
      end
    end
  end
end
