# frozen_string_literal: true

module GemContribute
  class Error < StandardError; end

  class LockfileNotFound < Error; end

  class LockfileParseError < Error; end

  class ResolveError < Error
    attr_reader :gem_name

    def initialize(gem_name, message)
      @gem_name = gem_name
      super("#{gem_name}: #{message}")
    end
  end

  class AdapterError < Error; end

  # Raised by host adapters when an authenticated call is attempted without a
  # cached token for that host. The TUI catches this and triggers device flow;
  # CLI callers print a "run auth login" hint. See ADR-0001.
  class AuthRequired < Error
    attr_reader :host

    def initialize(host)
      @host = host
      super("authentication required for #{host}")
    end
  end
end
