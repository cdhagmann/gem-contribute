# frozen_string_literal: true

module GemContribute
  module CLI
    # Shared scaffolding for action-style CLI verbs (Fix, Fork, future
    # Abandon). Each verb still owns its own `parse_argv`, `execute`, and
    # `print_usage_error`; this module captures the common pieces around
    # them: the missing-clone_root error, the auth-token check, the
    # project resolver, and the AdapterError/AuthRequired rescue shell.
    #
    # Including classes are expected to hold:
    #   @stderr, @resolver, @store, @adapter_factory, @clone_root
    module Workflow
      private

      # Wraps the verb's run body. `return` inside the block exits the
      # enclosing run method (Ruby's non-local return); raised
      # AuthRequired/AdapterError land here and produce a 1 exit status
      # with a friendly message.
      def with_workflow_rescues(verb)
        yield
      rescue GemContribute::AuthRequired
        @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
        1
      rescue GemContribute::AdapterError => e
        @stderr.puts "#{verb} failed: #{e.message}"
        1
      end

      def missing_clone_root
        @stderr.puts "clone_root is not configured. Run `gem-contribute init` first."
        1
      end

      def build_adapter
        token = @store.token_for("github.com")
        if token.nil?
          @stderr.puts "Not authenticated. Run `gem-contribute auth login` first."
          return nil
        end
        @adapter_factory.call(token: token)
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
