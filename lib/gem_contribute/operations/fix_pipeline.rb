# frozen_string_literal: true

require "dry/operation"
require "dry/monads"

module GemContribute
  module Operations
    # Composes the four `fix` steps — Fork → Clone → Branch → Announce —
    # using `dry-operation`. Each `step` short-circuits on Failure;
    # Announce is called outside `step` because its Failure is
    # informational (the fix has already happened) and should not
    # propagate as a pipeline-level Failure.
    #
    # The pipeline itself is output-free per ADR-0012 — no spinners, no
    # progress lines, no stdout. Callers (the CLI verb today; a TUI
    # Command tomorrow) render the outcome.
    #
    # Inputs:
    #   adapter         — HostAdapter instance (already authenticated)
    #   project         — Project struct
    #   issue           — String/Integer issue number (used in branch name)
    #   root            — Clone-root directory
    #   allow_announce  — Boolean. Verb-level gating (e.g. --no-comment,
    #                     `comment_on_fix?` config) is collapsed into this
    #                     bool by the caller. The pipeline additionally
    #                     skips announce when `viewer == project.owner`
    #                     (you don't need to announce on your own repo).
    #
    # Returns Success(hash) on the happy path:
    #   { fork: Operations::Fork::Result,
    #     clone: Operations::Clone::Result,
    #     branch: Operations::Branch::Result,
    #     announce: Result (Success(:posted | :skipped) | Failure([:announce_failed, msg])) }
    class FixPipeline < Dry::Operation
      def initialize(fork: nil, clone: nil, branch: nil, announce: nil, git: nil)
        super()
        git ||= Git.new
        @fork = fork || Operations::Fork.new
        @clone = clone || Operations::Clone.new(git: git)
        @branch = branch || Operations::Branch.new(git: git)
        @announce = announce || Operations::Announce.new
      end

      # `Dry::Operation` wraps the method's final return value in `Success`,
      # so the body returns a raw hash. `step` unwraps Success and short-
      # circuits on Failure; Announce is called outside `step` because its
      # Failure is informational (the fix has already happened).
      def call(adapter:, project:, issue:, root:, allow_announce:)
        fork_result = step @fork.call(adapter: adapter, project: project)
        clone_result = step @clone.call(
          adapter: adapter, project: project,
          fork_clone_url: fork_result.clone_url, root: root
        )
        branch_result = step @branch.call(path: clone_result.path, issue: issue)

        allow = allow_announce && fork_result.viewer != project.owner
        announce_result = @announce.call(
          adapter: adapter, project: project, issue: issue, allow: allow
        )

        {
          fork: fork_result,
          clone: clone_result,
          branch: branch_result,
          announce: announce_result
        }
      end
    end
  end
end
