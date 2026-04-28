# frozen_string_literal: true

require "fileutils"
require "json"

module GemContribute
  # Reads / writes ~/.config/gem-contribute/auth.json (mode 0600), keyed by
  # host. The per-host structure means GitLab / Codeberg adapters drop in
  # without rearranging storage. See ADR-0001 and ADR-0004.
  #
  # File schema:
  #   {
  #     "github.com": {
  #       "access_token": "gho_...",
  #       "scope": "public_repo",
  #       "stored_at": 1730000000
  #     }
  #   }
  #
  # Honors XDG_CONFIG_HOME so tests stay hermetic and unusual layouts work.
  class TokenStore
    def initialize(path: TokenStore.default_path, clock: -> { Time.now.to_i })
      @path = path
      @clock = clock
    end

    # @return [String, nil] the cached access token for the host, or nil
    def token_for(host)
      data = read
      data.dig(host, "access_token")
    end

    # @return [Hash, nil] {access_token, scope, stored_at} or nil
    def entry_for(host)
      read[host]
    end

    def store(host, access_token:, scope: nil)
      data = read
      data[host] = {
        "access_token" => access_token,
        "scope" => scope,
        "stored_at" => @clock.call
      }.compact
      write(data)
    end

    def delete(host)
      data = read
      removed = data.delete(host)
      write(data) if removed
      removed
    end

    def hosts
      read.keys
    end

    def self.default_path
      base = ENV["XDG_CONFIG_HOME"] || File.expand_path("~/.config")
      File.join(base, "gem-contribute", "auth.json")
    end

    private

    def read
      return {} unless File.file?(@path)

      JSON.parse(File.read(@path, encoding: "UTF-8"))
    rescue JSON::ParserError, Encoding::InvalidByteSequenceError
      # Corrupt store: don't lose the user's data, but don't crash either.
      # The token is recoverable by re-running `auth login`; the worst case
      # is one extra device-flow round trip.
      {}
    end

    def write(data)
      FileUtils.mkdir_p(File.dirname(@path))
      tmp = "#{@path}.tmp"
      File.write(tmp, JSON.pretty_generate(data), encoding: "UTF-8")
      File.chmod(0o600, tmp)
      File.rename(tmp, @path)
      File.chmod(0o600, @path)
    end
  end
end
