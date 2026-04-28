# frozen_string_literal: true

require "bundler"

module GemContribute
  # Wraps Bundler::LockfileParser. See ADR-0002.
  #
  # Input: a path to a Gemfile.lock.
  # Output: an Array of LockedGem.
  module LockfileParser
    module_function

    # @param path [String, Pathname] path to a Gemfile.lock
    # @return [Array<LockedGem>]
    def parse(path)
      contents = read_lockfile(path)
      parser = Bundler::LockfileParser.new(contents)

      parser.specs.map { |spec| build_locked_gem(spec) }
    rescue Bundler::LockfileError => e
      raise LockfileParseError, "could not parse #{path}: #{e.message}"
    end

    def read_lockfile(path)
      File.read(path)
    rescue Errno::ENOENT
      raise LockfileNotFound, "no Gemfile.lock at #{path}"
    end

    def build_locked_gem(spec)
      LockedGem.new(
        name: spec.name,
        version: spec.version.to_s,
        source_type: classify_source(spec.source),
        source_uri: source_uri(spec.source)
      )
    end

    def classify_source(source)
      case source
      when Bundler::Source::Rubygems then :rubygems
      when Bundler::Source::Git then :git
      when Bundler::Source::Path then :path
      else :unknown
      end
    end

    def source_uri(source)
      case source
      when Bundler::Source::Rubygems
        # Bundler::Source::Rubygems can have multiple remotes; pick the first.
        # In practice this is rubygems.org for almost every gem.
        source.remotes.first&.to_s
      when Bundler::Source::Git
        source.uri
      when Bundler::Source::Path
        source.path.to_s
      end
    end
  end
end
