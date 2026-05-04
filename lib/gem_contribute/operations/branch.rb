# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module Operations
    # Bootstrap step 3: create the per-issue working branch in the fork
    # clone. The branch name is `gem-contribute/issue-<N>`. Output-free
    # per ADR-0012.
    #
    # Note: `git checkout -b` fails if the branch already exists, which
    # surfaces as `Failure([:adapter_error, ...])` here. That preserves
    # the pre-extraction behaviour where re-running `fix` on an issue
    # whose branch already exists locally errored out — see [#10] for
    # the friendlier-message follow-up.
    class Branch
      include Dry::Monads[:result]

      Result = Data.define(:name)
      PREFIX = "gem-contribute/issue-"

      def initialize(git: Git.new)
        @git = git
      end

      def call(path:, issue:)
        name = "#{PREFIX}#{issue}"
        @git.checkout_branch(path, name)
        Success(Result.new(name: name))
      rescue GemContribute::AdapterError => e
        Failure([:adapter_error, e.message])
      end
    end
  end
end
