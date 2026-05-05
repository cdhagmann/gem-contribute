# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module Operations
    # Bootstrap step 3: ensure the per-issue working branch exists and is
    # checked out in the clone. The branch name is `gem-contribute/issue-<N>`.
    # Output-free per ADR-0012. Idempotent: if the branch already exists
    # locally it is checked out (not re-created), so re-running `fix` on the
    # same issue lands you on the same branch without errors (closes #54).
    class Branch
      include Dry::Monads[:result]

      Result = Data.define(:name, :reused)
      PREFIX = "gem-contribute/issue-"

      def initialize(git: Git.new)
        @git = git
      end

      def call(path:, issue:)
        name = "#{PREFIX}#{issue}"
        if @git.branch_exists?(path, name)
          @git.switch_branch(path, name)
          Success(Result.new(name: name, reused: true))
        else
          @git.checkout_branch(path, name)
          Success(Result.new(name: name, reused: false))
        end
      rescue GemContribute::AdapterError => e
        Failure([:adapter_error, e.message])
      end
    end
  end
end
