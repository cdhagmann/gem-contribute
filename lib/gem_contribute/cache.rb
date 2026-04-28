# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module GemContribute
  # Disk cache at ~/.cache/gem-contribute/<namespace>/<key>.json.
  #
  # Honors XDG_CACHE_HOME so tests (and users with non-default XDG layouts)
  # don't pollute each other.
  #
  # Per docs/design.md the namespaces and TTLs are:
  #   gems    — RubyGems metadata           — 7 days
  #   issues  — GitHub issue lists          — 5 minutes
  #   repos   — community profile responses — 1 day
  #   files   — file contents (CONTRIBUTING) — 1 day
  #
  # The cache stores `{stored_at:, payload:}` so the TTL check is local rather
  # than dependent on filesystem mtime (which differs across platforms).
  class Cache
    DEFAULT_NAMESPACE_TTL = {
      "gems" => 7 * 24 * 60 * 60,
      "issues" => 5 * 60,
      "repos" => 24 * 60 * 60,
      "files" => 24 * 60 * 60
    }.freeze

    attr_reader :root

    def initialize(root: Cache.default_root, ttl: DEFAULT_NAMESPACE_TTL, clock: -> { Time.now.to_i })
      @root = root
      @ttl = ttl
      @clock = clock
    end

    # Look up a cached value. Returns the payload Hash or nil.
    # Expired entries are treated as misses but left on disk; the next write
    # overwrites them. (Aggressive deletion costs IO for no real gain.)
    def fetch(namespace, key)
      path = path_for(namespace, key)
      return nil unless File.file?(path)

      data = read_json(path)
      return nil if data.nil?
      return nil if expired?(namespace, data)

      data["payload"]
    end

    # Cache a payload. Returns the payload as given.
    def write(namespace, key, payload)
      path = path_for(namespace, key)
      FileUtils.mkdir_p(File.dirname(path))

      tmp = "#{path}.tmp"
      File.write(tmp, JSON.generate("stored_at" => @clock.call, "payload" => payload), encoding: "UTF-8")
      File.rename(tmp, path)
      payload
    end

    # Clear every namespace under the cache root. Powers `--refresh`.
    def clear!
      FileUtils.rm_rf(@root) if File.directory?(@root)
    end

    def self.default_root
      base = ENV["XDG_CACHE_HOME"] || File.expand_path("~/.cache")
      File.join(base, "gem-contribute")
    end

    private

    def path_for(namespace, key)
      File.join(@root, namespace, "#{safe_key(key)}.json")
    end

    def safe_key(key)
      # Keys can contain slashes (`owner/repo`); hash them so we don't have to
      # mkdir_p arbitrary trees and so collisions across namespaces stay tidy.
      Digest::SHA256.hexdigest(key.to_s)
    end

    def read_json(path)
      JSON.parse(File.read(path, encoding: "UTF-8"))
    rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      nil
    end

    def expired?(namespace, data)
      ttl = @ttl[namespace] || @ttl[namespace.to_s]
      return false if ttl.nil?

      stored_at = data["stored_at"].to_i
      (@clock.call - stored_at) > ttl
    end
  end
end
