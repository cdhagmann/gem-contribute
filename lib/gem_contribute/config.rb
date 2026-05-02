# frozen_string_literal: true

require "fileutils"
require "yaml"

module GemContribute
  # Reads and writes ~/.config/gem-contribute/config.yml.
  # Honors XDG_CONFIG_HOME so tests stay hermetic and unusual layouts work.
  # Missing or corrupt files are treated as an empty config (no crash).
  class Config
    KNOWN_KEYS = %w[clone_root].freeze

    def initialize(path: self.class.default_path)
      @path = path
      @data = load_file
    end

    def clone_root
      raw = @data["clone_root"]
      raw ? File.expand_path(raw) : nil
    end

    def set(key, value)
      raise ArgumentError, "unknown config key #{key.inspect}. Known keys: #{KNOWN_KEYS.join(", ")}" \
        unless KNOWN_KEYS.include?(key)

      @data[key] = value
      write_file
    end

    def to_h
      @data.dup
    end

    def self.default_path
      base = ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config"))
      File.join(base, "gem-contribute", "config.yml")
    end

    private

    def load_file
      return {} unless File.exist?(@path)

      parsed = YAML.safe_load(File.read(@path, encoding: "UTF-8"))
      parsed.is_a?(Hash) ? parsed : {}
    rescue Psych::Exception, Errno::EACCES
      {}
    end

    def write_file
      FileUtils.mkdir_p(File.dirname(@path))
      tmp = "#{@path}.tmp"
      File.write(tmp, YAML.dump(@data), encoding: "UTF-8")
      File.rename(tmp, @path)
    end
  end
end
