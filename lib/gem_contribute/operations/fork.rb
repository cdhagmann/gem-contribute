# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module Operations
    # Bootstrap step 1: ensure the viewer owns a fork of `project` (creating
    # one if needed). Returns a `Result` describing what happened, or a
    # tagged `Failure` for the caller to render. Does no filesystem work
    # — that's `Operations::Clone`'s job. Does no I/O — that's the caller's
    # job (per ADR-0012).
    class Fork
      include Dry::Monads[:result]

      Result = Data.define(:clone_url, :fork_url, :upstream_url, :viewer, :reused, :owned_upstream)

      def call(adapter:, project:)
        fork = adapter.fork(project)
        Success(
          Result.new(
            clone_url: fork.clone_url,
            fork_url: fork.fork_url,
            upstream_url: adapter.repo_url(project.owner, project.repo),
            viewer: fork.viewer,
            reused: fork.reused,
            owned_upstream: fork.owned_upstream
          )
        )
      rescue GemContribute::AuthRequired
        Failure(:unauthenticated)
      rescue GemContribute::AdapterError => e
        Failure([:adapter_error, e.message])
      end
    end
  end
end
