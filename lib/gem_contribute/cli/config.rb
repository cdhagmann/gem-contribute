# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute config <subcommand>`
    #
    # Subcommands:
    #   set <key> <value>   Write a value to ~/.config/gem-contribute/config.yml
    #   get <key>           Print the current value of a key
    #   list                Print all configured values
    class Config
      USAGE = <<~USAGE
        Usage: gem-contribute config <subcommand>

        Subcommands:
          set <key> <value>    Set a configuration value.
          get <key>            Print the current value of a key.
          list                 Print all configured values.

        Keys:
          clone_root           Directory where forks are cloned (default: ~/code/oss).
                               Example: gem-contribute config set clone_root ~/Projects/oss
      USAGE

      def initialize(stdout: $stdout, stderr: $stderr, config: GemContribute::Config.new)
        @stdout = stdout
        @stderr = stderr
        @config = config
      end

      def run(argv)
        case argv.shift
        when "set"  then set(argv)
        when "get"  then get(argv)
        when "list" then list
        when nil, "help", "-h", "--help"
          @stdout.puts USAGE
          0
        else
          @stderr.puts "gem-contribute: unknown config subcommand"
          @stderr.puts USAGE
          2
        end
      end

      private

      def set(argv)
        key = argv.shift
        value = argv.shift
        if key.nil? || value.nil?
          @stderr.puts "Usage: gem-contribute config set <key> <value>"
          return 2
        end

        @config.set(key, value)
        @stdout.puts "#{key} = #{value}"
        0
      rescue ArgumentError => e
        @stderr.puts e.message
        1
      end

      def get(argv)
        key = argv.shift
        if key.nil?
          @stderr.puts "Usage: gem-contribute config get <key>"
          return 2
        end

        unless GemContribute::Config::KNOWN_KEYS.include?(key)
          @stderr.puts "unknown config key #{key.inspect}"
          return 1
        end

        @stdout.puts @config.to_h.fetch(key, "(not set — default applies)")
        0
      end

      def list
        @stdout.puts "Configuration (#{GemContribute::Config.default_path}):"
        @stdout.puts "  clone_root = #{@config.clone_root}"
        0
      end
    end
  end
end
