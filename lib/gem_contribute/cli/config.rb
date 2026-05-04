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
          clone_root           Directory where forks are cloned. Set with
                               `gem-contribute init` (interactive) or
                               `gem-contribute config set clone_root <path>`.
          editor               Editor command for `fix -e`. Falls back to $EDITOR.
                               Example: gem-contribute config set editor code
          ai_tool              Shell command for `fix -a` (run in clone dir).
                               Example: gem-contribute config set ai_tool "claude ."
          comment_on_fix       Whether `fix` posts a "working on this" comment.
                               Default: true. Per-repo overrides via
                               `comment_on_fix_overrides` in the YAML.
      USAGE

      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     config: GemContribute::Config.new)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
        @config = config
      end

      def run(argv)
        case argv.shift
        when "set"  then set(argv)
        when "get"  then get(argv)
        when "list" then list
        when nil, "help", "-h", "--help"
          @output.info(USAGE)
          0
        else
          @output.error("gem-contribute: unknown config subcommand")
          @output.error(USAGE)
          2
        end
      end

      private

      def set(argv)
        key = argv.shift
        value = argv.shift
        if key.nil? || value.nil?
          @output.error("Usage: gem-contribute config set <key> <value>")
          return 2
        end

        @config.set(key, value)
        @output.info("#{key} = #{value}")
        0
      rescue ArgumentError => e
        @output.error(e.message)
        1
      end

      def get(argv)
        key = argv.shift
        if key.nil?
          @output.error("Usage: gem-contribute config get <key>")
          return 2
        end

        unless GemContribute::Config::KNOWN_KEYS.include?(key)
          @output.error("unknown config key #{key.inspect}")
          return 1
        end

        @output.info(@config.to_h.fetch(key, "(not set; run `gem-contribute init`)"))
        0
      end

      def list
        @output.info("Configuration (#{GemContribute::Config.default_path}):")
        @output.info("  clone_root = #{@config.clone_root || "(not set; run `gem-contribute init`)"}")
        @output.info("  editor = #{@config.editor || "(not set)"}")
        @output.info("  ai_tool = #{@config.ai_tool || "(not set)"}")
        @output.info("  comment_on_fix = #{@config.comment_on_fix?}")
        overrides = @config.to_h["comment_on_fix_overrides"]
        if overrides.is_a?(Hash) && !overrides.empty?
          @output.info("  comment_on_fix_overrides:")
          overrides.each { |repo, val| @output.info("    #{repo}: #{val}") }
        end
        0
      end
    end
  end
end
