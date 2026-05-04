# frozen_string_literal: true

module GemContribute
  module Output
    # No-op output sink. Inject into CLI verbs in tests that don't care
    # about output (or want to assert on a separate capturing double).
    class Null
      def info(_message) = nil
      def progress(_message) = nil
      def warn(_message) = nil
      def error(_message) = nil
    end
  end
end
