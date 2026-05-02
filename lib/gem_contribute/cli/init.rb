# frozen_string_literal: true

module GemContribute
  module CLI
    # `gem-contribute init` — interactive one-time setup. Writes the user's
    # `clone_root` to ~/.config/gem-contribute/config.yml and, if no GitHub
    # token is cached, offers to run `auth login`.
    #
    # Without init, `fix` errors with a hint to run init. The point is to
    # avoid creating directories or assuming auth without explicit consent.
    class Init
      USAGE = <<~USAGE
        Usage: gem-contribute init

        Interactively set the directory where forks are cloned (clone_root),
        then offer to authenticate with GitHub if you haven't already.
        Re-run any time to change.
      USAGE

      DEFAULT_SUGGESTION = "~/code/oss"
      AUTH_HOST = "github.com"

      def initialize(stdout: $stdout, stderr: $stderr,
                     config: GemContribute::Config.new,
                     store: GemContribute::TokenStore.new,
                     auth: nil,
                     gets: -> { $stdin.gets })
        @stdout = stdout
        @stderr = stderr
        @config = config
        @store = store
        @auth = auth || GemContribute::CLI::Auth.new(stdout: stdout, stderr: stderr, store: store)
        @gets = gets
      end

      def run(argv)
        return print_usage if %w[help -h --help].include?(argv.first)

        prompt_clone_root
        maybe_authenticate
        0
      end

      private

      def prompt_clone_root
        current = @config.to_h["clone_root"]
        default = current || DEFAULT_SUGGESTION

        @stdout.print "Where should I clone repos? [#{default}]: "
        @stdout.flush
        input = @gets.call.to_s.chomp.strip
        chosen = input.empty? ? default : input

        @config.set("clone_root", chosen)
        @stdout.puts "Clone root set to #{File.expand_path(chosen)}"
      end

      def maybe_authenticate
        if @store.token_for(AUTH_HOST)
          @stdout.puts "GitHub: already authenticated."
          return
        end

        @stdout.print "Authenticate with GitHub now? [Y/n]: "
        @stdout.flush
        answer = @gets.call.to_s.chomp.strip.downcase

        if %w[n no].include?(answer)
          @stdout.puts "Skipping auth. Run `gem-contribute auth login` when you're ready."
          return
        end

        @auth.run(["login"])
      end

      def print_usage
        @stdout.puts USAGE
        0
      end
    end
  end
end
