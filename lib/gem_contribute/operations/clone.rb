# frozen_string_literal: true

require "dry/monads"
require "fileutils"

module GemContribute
  module Operations
    # Bootstrap step 2: clone the fork into `<root>/<owner>/<repo>` (reusing
    # an existing clone if one is there), and ensure an `upstream` remote
    # points at the canonical project. Returns a `Result` carrying the
    # local path and a `reused` flag, or a tagged `Failure`.
    #
    # The "reuse if `.git` exists" rule and the upstream-remote convention
    # are gem-contribute policy on top of git, not git itself — that's why
    # they live here rather than in `Git`.
    class Clone
      include Dry::Monads[:result]

      Result = Data.define(:path, :reused)

      def initialize(git: Git.new)
        @git = git
      end

      def call(adapter:, project:, fork_clone_url:, root:)
        target = File.join(root, project.owner, project.repo)
        reused = File.directory?(File.join(target, ".git"))

        unless reused
          FileUtils.mkdir_p(File.dirname(target))
          @git.clone(fork_clone_url, target)
        end

        @git.add_remote(target, "upstream", adapter.clone_url(project.owner, project.repo))
        Success(Result.new(path: target, reused: reused))
      rescue GemContribute::AdapterError => e
        Failure([:adapter_error, e.message])
      end
    end
  end
end
