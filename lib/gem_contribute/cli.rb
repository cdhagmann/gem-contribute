# frozen_string_literal: true

require "optparse"

module GemContribute
  module CLI
    autoload :Scan, "gem_contribute/cli/scan"
    autoload :Auth, "gem_contribute/cli/auth"
    autoload :ForkCloneBranch, "gem_contribute/cli/fork_clone_branch"
    autoload :Git, "gem_contribute/cli/fork_clone_branch"
    USAGE = <<~USAGE
      Usage: gem-contribute <command> [options]

      Commands:
        scan [path]              Summarize the contributable surface of a Gemfile.lock.
                                 Path defaults to ./Gemfile.lock.
        auth login               Authenticate with GitHub via OAuth device flow.
        auth status              Show whether you're authenticated.
        auth logout              Remove the cached token for github.com.
        fork-clone-branch <gem>/<issue#>
                                 Fork the gem's repo, clone the fork, branch from main.

      Global options:
        --refresh                Invalidate caches before running.
        -h, --help               Show this help.
        --version                Print the version and exit.
    USAGE

    module_function

    # Entry point for exe/gem-contribute. Returns an integer exit status so the
    # caller can `exit GemContribute::CLI.run(ARGV)`.
    def run(argv, stdout: $stdout, stderr: $stderr)
      argv = argv.dup
      handle_global_flags!(argv, stdout: stdout)

      command = argv.shift
      case command
      when nil, "help", "-h", "--help"
        stdout.puts USAGE
        0
      when "scan"
        Scan.new(stdout: stdout, stderr: stderr).run(argv)
      when "auth"
        Auth.new(stdout: stdout, stderr: stderr).run(argv)
      when "fork-clone-branch"
        ForkCloneBranch.new(stdout: stdout, stderr: stderr).run(argv)
      else
        stderr.puts "gem-contribute: unknown command #{command.inspect}"
        stderr.puts USAGE
        2
      end
    end

    def handle_global_flags!(argv, stdout:)
      if argv.include?("--version")
        stdout.puts "gem-contribute #{GemContribute::VERSION}"
        exit 0
      end

      return unless argv.delete("--refresh")

      Cache.new.clear!
      stdout.puts "Cache cleared at #{Cache.default_root}"
    end
  end
end
