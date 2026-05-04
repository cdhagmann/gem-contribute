# frozen_string_literal: true

require "tty-spinner"

module GemContribute
  module Output
    # Semantic output abstraction for CLI verbs (per ADR-0012). Wraps
    # stdout/stderr behind verb-shaped methods so the look-and-feel can
    # evolve independently of the service layer.
    #
    # `#warn` and `#error` both write to stderr without prefixing — the
    # caller's message already carries its own framing ("Note: ...",
    # "warning: ...", "fix failed: ..."). The semantic split exists so a
    # later styling pass (color, severity icons) has somewhere to hang.
    #
    # `#progress` has two forms:
    #
    #   * No block — equivalent to #info. Use when there's nothing to
    #     wrap, e.g. you're announcing intent before a sequence of calls.
    #   * Block form — runs the block while showing a tty-spinner in
    #     interactive terminals. In non-TTY contexts (CI, piped output,
    #     test StringIOs) it falls back to a plain line + yield. The
    #     block's return value is the method's return value.
    class Standard
      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      def info(message)
        @out.puts(message)
      end

      def progress(message, &)
        return @out.puts(message) unless block_given?
        return puts_and_yield(message, &) unless interactive?

        spin(message, &)
      end

      def warn(message)
        @err.puts(message)
      end

      def error(message)
        @err.puts(message)
      end

      private

      def interactive?
        @out.respond_to?(:tty?) && @out.tty?
      end

      def puts_and_yield(message)
        @out.puts(message)
        yield
      end

      def spin(message)
        spinner = TTY::Spinner.new("[:spinner] #{message}", output: @out, format: :dots)
        spinner.auto_spin
        begin
          yield
        ensure
          spinner.stop
        end
      end
    end
  end
end
