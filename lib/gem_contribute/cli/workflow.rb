# frozen_string_literal: true

require "dry/monads"

module GemContribute
  module CLI
    # Shared scaffolding for action-style CLI verbs (Fix, Fork, future
    # Abandon). Each verb owns its own `parse_argv`, `execute`, and
    # `print_usage_error`; this module captures the common pieces around
    # them: the missing-clone_root error, the auth-token check (as a
    # Result-returning service per ADR-0012), and the project resolver.
    #
    # Including classes are expected to hold:
    #   @stderr, @resolver, @store, @adapter_factory, @clone_root
    module Workflow
      include Dry::Monads[:result]

      private

      def missing_clone_root
        @stderr.puts "clone_root is not configured. Run `gem-contribute init` first."
        1
      end

      # Per ADR-0012: returns Success(adapter) | Failure(:unauthenticated).
      # Callers pattern-match — no nil + stderr side effect, no exceptions.
      def build_adapter
        token = @store.token_for("github.com")
        return Failure(:unauthenticated) if token.nil?

        Success(@adapter_factory.call(token: token))
      end

      # Resolves a CLI target to a `github.com` Project, or prints an
      # error and returns nil. With `allow_owner_repo: true` the slash
      # form (`owner/repo`) bypasses RubyGems and constructs the Project
      # directly — useful for verbs that don't require a published gem.
      def resolve_target(target, verb:, allow_owner_repo: false)
        if allow_owner_repo && target.include?("/")
          owner, repo = target.split("/", 2)
          return GemContribute::Project.new(
            gem_name: repo, host: "github.com",
            owner: owner, repo: repo, metadata: {}
          )
        end

        return GemContribute::SELF_PROJECT if target == GemContribute::SELF_PROJECT.gem_name

        gem = LockedGem.new(name: target, version: "*",
                            source_type: :rubygems, source_uri: "https://rubygems.org/")
        project = @resolver.resolve(gem)

        if project.host != "github.com"
          @stderr.puts "Cannot run `#{verb}`: #{target} resolves to #{project.host} " \
                       "(only github.com is supported at v0.1)"
          return nil
        end

        project
      end
    end
  end
end
