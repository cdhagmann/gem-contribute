# frozen_string_literal: true

module GemContribute
  module Output
    # No-op output sink. Inject into CLI verbs in tests that don't care
    # about output (or want to assert on a separate capturing double).
    #
    # `#progress` accepts a block (mirroring `Output::Standard#progress`)
    # and yields it; the spinner machinery is skipped entirely.
    class Null
      def info(_message) = nil
      def warn(_message) = nil
      def error(_message) = nil

      def progress(_message)
        block_given? ? yield : nil
      end
    end
  end
end
