# frozen_string_literal: true

module GemContribute
  # A single dependency parsed from Gemfile.lock.
  #
  # The design doc calls this "a Gem"; the in-code name is LockedGem to avoid
  # shadowing Ruby's stdlib ::Gem inside the GemContribute namespace.
  # See ADR-0009.
  #
  # `source_type` is one of:
  #   :rubygems  — published to a RubyGems-compatible index
  #   :git       — `gem 'foo', git: '…'`
  #   :path      — `gem 'foo', path: '…'`
  #   :bundler   — Bundler itself (only present in lockfiles via DEPENDENCIES)
  LockedGem = Data.define(:name, :version, :source_type, :source_uri) do
    def rubygems?
      source_type == :rubygems
    end

    def resolvable?
      # We can only ask the RubyGems API about things we got from RubyGems.
      # See ADR-0003 for what we do with the answer.
      rubygems?
    end
  end
end
