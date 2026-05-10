# frozen_string_literal: true

require "optparse"

module GemContribute
  module CLI
    USAGE = <<~USAGE
      Usage: gem-contribute <command> [options]

      Commands:
        init                     One-time interactive setup (sets clone_root).
        scan [path]              Summarize the contributable surface of a Gemfile.lock.
                                 Path defaults to ./Gemfile.lock.
        issues <gem|all>         List open "good first issue" issues for a gem (or all gems).
        config set <key> <val>   Persist a configuration value.
        config get <key>         Print a configuration value.
        config list              Print all configuration values.
        auth login               Authenticate with GitHub via OAuth device flow.
        auth status              Show whether you're authenticated.
        auth logout              Remove the cached token for github.com.
        fork <gem|owner/repo>    Fork (and clone) any GitHub repo. Pass a gem name
                                 to look it up on RubyGems, or `owner/repo` for any
                                 GitHub project (e.g. `rubyevents/rubyevents`).
                                 Lands on the default branch.
                                 Flags: -e (editor), -a (AI tool).
        open <gem>               Open the gem's GitHub repo in your default browser.
                                 The URL is also printed on stdout as a fallback.
        fix <gem>/<issue#>       Fork the gem's repo, clone the fork, branch from main.
                                 Flags: -e (editor), -a (AI tool), --no-comment.
        submit                   Push the current branch and open a pre-filled
                                 PR compare page in the browser. Run from inside
                                 a clone created by `fix`.

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
      dispatch(argv.shift, argv, stdout: stdout, stderr: stderr)
    end

    def dispatch(command, argv, stdout:, stderr:)
      builder = COMMANDS[command]
      if builder.nil?
        return print_help(stdout) if [nil, "help", "-h", "--help"].include?(command)

        return unknown_command(command, stderr)
      end

      builder.call(stdout, stderr).run(argv)
    end

    COMMANDS = {
      "init" => ->(o, e) { Init.new(stdout: o, stderr: e) },
      "scan" => ->(o, e) { Scan.new(stdout: o, stderr: e, adapter: github_adapter) },
      "issues" => ->(o, e) { Issues.new(stdout: o, stderr: e, adapter: github_adapter) },
      "config" => ->(o, e) { Config.new(stdout: o, stderr: e) },
      "auth" => ->(o, e) { Auth.new(stdout: o, stderr: e) },
      "fork" => ->(o, e) { Fork.new(stdout: o, stderr: e, clone_root: GemContribute::Config.new.clone_root) },
      "open" => ->(o, e) { Open.new(stdout: o, stderr: e) },
      "fix" => lambda { |o, e|
        config = GemContribute::Config.new
        Fix.new(stdout: o, stderr: e, clone_root: config.clone_root, config: config)
      },
      "submit" => ->(o, e) { Submit.new(stdout: o, stderr: e) }
    }.freeze

    def print_help(stdout)
      stdout.puts USAGE
      0
    end

    def unknown_command(command, stderr)
      stderr.puts "gem-contribute: unknown command #{command.inspect}"
      stderr.puts USAGE
      2
    end

    def github_adapter
      token = TokenStore.new.token_for("github.com")
      HostAdapters::GitHubAdapter.new(token: token)
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
