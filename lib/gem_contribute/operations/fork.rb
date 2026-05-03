# frozen_string_literal: true

module GemContribute
  module Operations
    # Bootstrap step 1: ensure the viewer owns a fork of `project` (creating
    # one if needed), and report what happened. Does no filesystem work —
    # that's `Operations::Clone`'s job.
    #
    # Result fields mirror the adapter's `ForkResult` plus `upstream_url` (a
    # convenience for the CLI summary so it doesn't have to ask the adapter
    # again).
    class Fork
      Result = Data.define(:clone_url, :fork_url, :upstream_url, :viewer, :reused)

      def initialize(stdout: $stdout)
        @stdout = stdout
      end

      def call(adapter:, project:)
        @stdout.puts "Forking #{project.owner}/#{project.repo}..."
        fork = adapter.fork(project)
        @stdout.puts status_line(fork, project)
        Result.new(
          clone_url: fork.clone_url,
          fork_url: fork.fork_url,
          upstream_url: adapter.repo_url(project.owner, project.repo),
          viewer: fork.viewer,
          reused: fork.reused
        )
      end

      private

      def status_line(fork, project)
        if fork.reused
          "  Reusing existing fork at #{fork.viewer}/#{project.repo}."
        else
          "  Forked → #{fork.viewer}/#{project.repo}."
        end
      end
    end
  end
end
