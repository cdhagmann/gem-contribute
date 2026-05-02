# frozen_string_literal: true

module GemContribute
  module CLI
    # Body templates and marker matching for issue announcements posted by
    # `gem-contribute fix` (and future `abandon`). The marker is an HTML
    # comment in the body so re-runs can detect prior posts deterministically.
    #
    # Format: `<!-- gem-contribute:<verb> v<n> -->`. The verb is namespaced so
    # multiple announcement types can coexist on one issue (a `working` and
    # later an `abandon` describe different states). The version suffix lets
    # us rev the body without invalidating the matcher.
    module IssueAnnouncer
      WORKING_MARKER = "<!-- gem-contribute:working v1 -->"
      WORKING_BODY = <<~BODY.freeze
        #{WORKING_MARKER}
        👋 I've started working on this. I'll open a PR shortly.

        <sub>Posted via [gem-contribute](https://github.com/cdhagmann/gem-contribute).</sub>
      BODY

      module_function

      # Returns:
      #   :posted  — comment was posted
      #   :skipped — viewer's prior comments contain the marker (already announced)
      #   :failed  — API call raised; warning printed to stderr
      def announce_working(adapter:, project:, issue:, stdout:, stderr:)
        return :skipped if already_announced?(adapter, project, issue, WORKING_MARKER)

        adapter.comment_on_issue(project, issue, WORKING_BODY)
        stdout.puts "Posted 'working on this' comment to issue ##{issue}."
        :posted
      rescue GemContribute::AdapterError => e
        stderr.puts "Note: couldn't post 'working on this' comment to issue ##{issue}: " \
                    "#{e.message}. Continuing."
        :failed
      end

      def already_announced?(adapter, project, issue, marker)
        comments = adapter.issue_comments(project, issue)
        comments.any? { |c| c["body"].to_s.include?(marker) }
      rescue GemContribute::AdapterError
        # If we can't fetch comments, assume not announced and let the post
        # attempt fail safely on its own.
        false
      end
    end
  end
end
