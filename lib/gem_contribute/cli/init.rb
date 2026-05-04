# frozen_string_literal: true

require "tty-prompt"

module GemContribute
  module CLI
    # `gem-contribute init` — interactive one-time setup. Writes the user's
    # `clone_root` to ~/.config/gem-contribute/config.yml and, if no GitHub
    # token is cached, offers to run `auth login`.
    #
    # Without init, `fix` errors with a hint to run init. The point is to
    # avoid creating directories or assuming auth without explicit consent.
    #
    # Prompt input/output goes through `TTY::Prompt` (per ADR-0012 Phase 2,
    # commit #31). The injected `prompt:` keyword lets tests pass a
    # `TTY::Prompt.new(input:, output:)` with StringIO streams.
    class Init
      USAGE = <<~USAGE
        Usage: gem-contribute init

        Interactively set the directory where forks are cloned (clone_root),
        then offer to authenticate with GitHub if you haven't already.
        Re-run any time to change.
      USAGE

      DEFAULT_SUGGESTION = "~/code/oss"
      AUTH_HOST = "github.com"

      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     config: GemContribute::Config.new,
                     store: GemContribute::TokenStore.new,
                     auth: nil,
                     prompt: nil)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
        @config = config
        @store = store
        @auth = auth || GemContribute::CLI::Auth.new(output: @output, store: store)
        @prompt = prompt || TTY::Prompt.new
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
        chosen = @prompt.ask("Where should I clone repos?", default: default)
        @config.set("clone_root", chosen)
        @output.info("Clone root set to #{File.expand_path(chosen)}")
      end

      def maybe_authenticate
        if @store.token_for(AUTH_HOST)
          @output.info("GitHub: already authenticated.")
          return
        end

        if @prompt.yes?("Authenticate with GitHub now?", default: true)
          @auth.run(["login"])
        else
          @output.info("Skipping auth. Run `gem-contribute auth login` when you're ready.")
        end
      end

      def print_usage
        @output.info(USAGE)
        0
      end
    end
  end
end
