# frozen_string_literal: true

module GemContribute
  module Output
    # Semantic output abstraction for CLI verbs (per ADR-0012). Wraps
    # stdout/stderr behind verb-shaped methods so the look-and-feel can
    # evolve independently of the service layer.
    #
    # `#progress` is currently equivalent to `#info`; commit #30 swaps in
    # `tty-spinner` for interactive terminals (and falls back to a plain
    # line in non-TTY contexts).
    #
    # `#warn` and `#error` both write to stderr without prefixing — the
    # caller's message already carries its own framing ("Note: ...",
    # "warning: ...", "fix failed: ..."). The semantic split exists so a
    # later styling pass (color, severity icons) has somewhere to hang.
    class Standard
      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      def info(message)
        @out.puts(message)
      end

      def progress(message)
        @out.puts(message)
      end

      def warn(message)
        @err.puts(message)
      end

      def error(message)
        @err.puts(message)
      end
    end
  end
end
