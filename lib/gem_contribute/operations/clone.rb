# frozen_string_literal: true

require "fileutils"

module GemContribute
  module Operations
    # Bootstrap step 2: clone the fork into `<root>/<owner>/<repo>` (reusing
    # an existing clone if one is there), and ensure an `upstream` remote
    # points at the canonical project. Returns the local clone path.
    #
    # The "reuse if `.git` exists" rule and the upstream-remote convention
    # are gem-contribute policy on top of git, not git itself — that's why
    # they live here rather than in `Git`.
    class Clone
      def initialize(git: Git.new, stdout: $stdout)
        @git = git
        @stdout = stdout
      end

      def call(adapter:, project:, fork_clone_url:, root:)
        target = File.join(root, project.owner, project.repo)

        if File.directory?(File.join(target, ".git"))
          @stdout.puts "Reusing existing clone at #{target}."
        else
          FileUtils.mkdir_p(File.dirname(target))
          @stdout.puts "Cloning into #{target}..."
          @git.clone(fork_clone_url, target)
        end

        @git.add_remote(target, "upstream", adapter.clone_url(project.owner, project.repo))
        target
      end
    end
  end
end
