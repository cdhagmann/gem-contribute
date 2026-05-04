# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module Operations
    # Bootstrap step 4: post (or skip) a "working on this" comment on the
    # upstream issue. The marker is an HTML comment in the body so re-runs
    # detect prior posts deterministically.
    #
    # Format: `<!-- gem-contribute:<verb> v<n> -->`. Output-free per
    # ADR-0012; callers render the outcome.
    #
    # Returns:
    #   Success(:posted)  — comment was posted
    #   Success(:skipped) — gating said no, OR the marker was already present
    #   Failure([:announce_failed, message]) — adapter raised; the caller
    #     usually treats this as a non-fatal warning rather than a fix failure
    class Announce
      include Dry::Monads[:result]

      WORKING_MARKER = "<!-- gem-contribute:working v1 -->"
      WORKING_BODY = <<~BODY.freeze
        #{WORKING_MARKER}
        👋 I've started working on this. I'll open a PR shortly.

        <sub>Posted via [gem-contribute](https://github.com/cdhagmann/gem-contribute).</sub>
      BODY

      def call(adapter:, project:, issue:, allow:)
        return Success(:skipped) unless allow
        return Success(:skipped) if already_announced?(adapter, project, issue)

        adapter.comment(project, issue: issue, body: WORKING_BODY)
        Success(:posted)
      rescue GemContribute::AdapterError => e
        Failure([:announce_failed, e.message])
      end

      private

      def already_announced?(adapter, project, issue)
        comments = adapter.issue_comments(project, issue)
        comments.any? { |c| c["body"].to_s.include?(WORKING_MARKER) }
      rescue GemContribute::AdapterError
        # If we can't fetch comments, assume not announced and let the
        # post attempt fail safely on its own.
        false
      end
    end
  end
end
