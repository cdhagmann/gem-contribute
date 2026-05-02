# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute init` — interactive one-time setup that writes the
    # user's `clone_root` to ~/.config/gem-contribute/config.yml.
    #
    # Without this, `fix` errors with a hint to run init. The point is to
    # avoid creating directories on the user's machine without their
    # explicit consent.
    class Init
      USAGE = <<~USAGE
        Usage: gem-contribute init

        Interactively set the directory where forks are cloned (clone_root).
        Re-run any time to change.
      USAGE

      DEFAULT_SUGGESTION = "~/code/oss"

      def initialize(stdout: $stdout, stderr: $stderr,
                     config: GemContribute::Config.new,
                     gets: -> { $stdin.gets })
        @stdout = stdout
        @stderr = stderr
        @config = config
        @gets = gets
      end

      def run(argv)
        return print_usage if %w[help -h --help].include?(argv.first)

        current = @config.to_h["clone_root"]
        default = current || DEFAULT_SUGGESTION

        @stdout.print "Where should I clone repos? [#{default}]: "
        @stdout.flush
        input = @gets.call.to_s.chomp.strip
        chosen = input.empty? ? default : input

        @config.set("clone_root", chosen)
        @stdout.puts "Clone root set to #{File.expand_path(chosen)}"
        @stdout.puts "Re-run `gem-contribute init` any time to change this."
        0
      end

      private

      def print_usage
        @stdout.puts USAGE
        0
      end
    end
  end
end
