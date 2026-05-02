# frozen_string_literal: true

require "fileutils"

module GemContribute
  module CLI
    # The fork + clone + upstream-remote primitive shared by `fix` and
    # `fork`. Idempotent: reuses existing forks (via `already_forked?`)
    # and existing local clones (via the `.git` directory check).
    class ForkClone
      FORK_READINESS_RETRIES = 12 # 12 × 5s = 60s ceiling
      FORK_READINESS_INTERVAL = 5

      def initialize(clone_root:, stdout: $stdout, git: nil,
                     sleeper: ->(s) { Kernel.sleep(s) })
        @stdout = stdout
        @git = git || Git.new
        @clone_root = clone_root
        @sleeper = sleeper
      end

      # Fork (or reuse), clone (or reuse), add upstream remote.
      # Returns the local clone path.
      def call(adapter, project, viewer)
        clone_url = ensure_fork(adapter, project, viewer)
        local_path = clone_into_root(project, clone_url)
        # `submit` needs to know the canonical project to point the PR at.
        # `upstream` follows the standard fork workflow convention.
        @git.add_remote(local_path, "upstream",
                        "https://github.com/#{project.owner}/#{project.repo}.git")
        local_path
      end

      private

      def ensure_fork(adapter, project, viewer)
        if adapter.already_forked?(project)
          @stdout.puts "You already have a fork at #{viewer}/#{project.repo}. Skipping fork."
          return "https://github.com/#{viewer}/#{project.repo}.git"
        end

        @stdout.puts "Forking #{project.owner}/#{project.repo} → #{viewer}/#{project.repo}..."
        body = adapter.fork(project)
        wait_until_ready(adapter, viewer, project.repo)
        body.fetch("clone_url")
      end

      def wait_until_ready(adapter, viewer, name)
        ready = FORK_READINESS_RETRIES.times.any? do |i|
          break true if adapter.fork_ready?(viewer, name)

          @sleeper.call(FORK_READINESS_INTERVAL) unless i == FORK_READINESS_RETRIES - 1
          false
        end
        return if ready

        raise GemContribute::AdapterError,
              "fork not reachable after #{FORK_READINESS_RETRIES * FORK_READINESS_INTERVAL}s"
      end

      def clone_into_root(project, clone_url)
        target = File.join(@clone_root, project.owner, project.repo)
        if File.directory?(File.join(target, ".git"))
          @stdout.puts "Reusing existing clone at #{target}."
          return target
        end

        FileUtils.mkdir_p(File.dirname(target))
        @stdout.puts "Cloning into #{target}..."
        @git.clone(clone_url, target)
        target
      end
    end
  end
end
