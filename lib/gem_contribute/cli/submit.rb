# frozen_string_literal: true

require "open3"
require "uri"

module GemContribute
  module CLI
    # `gem-contribute submit` — push the current branch to the user's fork and
    # open a pre-filled PR compare page in the browser.
    #
    # Run from inside a clone created by `gem-contribute fix`. Reads:
    #   - origin remote   → fork owner/repo (where the branch is pushed)
    #   - upstream remote → canonical owner/repo (where the PR is filed)
    #   - current branch  → must match `gem-contribute/issue-<N>`
    #
    # The PR itself is NOT opened via API. We push, then open GitHub's compare
    # page in the browser with title and body pre-filled. This mirrors the
    # `auth login` UX (browser handles the human step) and means the user
    # always reviews the PR text before submitting.
    class Submit
      BRANCH_REGEX = %r{\Agem-contribute/issue-(\d+)\z}

      def initialize(stdout: $stdout, stderr: $stderr,
                     git: Git.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     store: TokenStore.new,
                     browser_opener: nil,
                     working_dir: Dir.pwd)
        @stdout = stdout
        @stderr = stderr
        @git = git
        @adapter_factory = adapter_factory
        @store = store
        @browser_opener = browser_opener || method(:default_browser_opener)
        @working_dir = working_dir
      end

      def run(_argv)
        branch = current_branch
        issue_number = parse_issue_number(branch)
        return 1 if issue_number.nil?

        origin = parse_remote("origin")
        upstream = parse_remote("upstream")
        return 1 if origin.nil? || upstream.nil?

        title = fetch_issue_title(upstream, issue_number)
        push_branch(branch)
        url = compare_url(upstream, origin, branch, issue_number, title)
        open_and_print(url)
        0
      rescue AdapterError => e
        @stderr.puts "submit failed: #{e.message}"
        1
      end

      private

      def current_branch
        # symbolic-ref works even on a fresh branch with no commits;
        # rev-parse --abbrev-ref doesn't.
        out, _err, status = Open3.capture3("git", "-C", @working_dir, "symbolic-ref", "--short", "HEAD")
        raise AdapterError, "not inside a git repository (or HEAD is detached)" unless status.success?

        out.strip
      end

      def parse_issue_number(branch)
        match = BRANCH_REGEX.match(branch)
        return match[1].to_i if match

        @stderr.puts "submit: branch #{branch.inspect} doesn't match #{BRANCH_REGEX.source}."
        @stderr.puts "Run `gem-contribute fix <gem>/<issue#>` first to set up the branch."
        nil
      end

      def parse_remote(name)
        out, _err, status = Open3.capture3("git", "-C", @working_dir, "remote", "get-url", name)
        unless status.success?
          @stderr.puts "submit: no `#{name}` remote configured. " \
                       "Was this clone created by `gem-contribute fix`?"
          return nil
        end

        owner_repo_from_url(out.strip)
      end

      # Accepts both https://github.com/owner/repo(.git) and git@github.com:owner/repo.git
      def owner_repo_from_url(url)
        if (m = url.match(%r{github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?\z}))
          { owner: m[1], repo: m[2] }
        else
          @stderr.puts "submit: can't parse GitHub owner/repo from #{url.inspect}"
          nil
        end
      end

      def fetch_issue_title(upstream, number)
        token = @store.token_for("github.com")
        adapter = @adapter_factory.call(token: token)
        adapter.issue(upstream[:owner], upstream[:repo], number).fetch("title", nil)
      rescue AdapterError => e
        @stderr.puts "submit: couldn't fetch issue title (#{e.message}). Continuing without it."
        nil
      end

      def push_branch(branch)
        @stdout.puts "Pushing #{branch} to origin..."
        @git.push(@working_dir, "origin", branch)
      end

      def compare_url(upstream, origin, branch, issue_number, title)
        # GitHub compare URL form for cross-fork PR creation:
        #   /<upstream>/compare/<base>...<fork-owner>:<branch>?expand=1
        # We don't know the upstream default branch without an extra API call,
        # so we let GitHub auto-resolve it by omitting `<base>...` and using
        # the simpler form. `expand=1` opens the PR creation form pre-filled.
        head = "#{origin[:owner]}:#{branch}"
        full_title = title ? "Fix ##{issue_number}: #{title}" : "Fix ##{issue_number}"
        params = {
          "expand" => "1",
          "title" => full_title,
          "body" => "Closes ##{issue_number}.\n\n_Opened via `gem-contribute submit`._"
        }

        "https://github.com/#{upstream[:owner]}/#{upstream[:repo]}/compare/#{head}?" \
          "#{URI.encode_www_form(params)}"
      end

      def open_and_print(url)
        opened = @browser_opener.call(url)
        @stdout.puts opened ? "Opened browser to:" : "Open this URL to file the PR:"
        @stdout.puts "  #{url}"
      end

      def default_browser_opener(uri)
        cmd = case RbConfig::CONFIG["host_os"]
              when /darwin/             then "open"
              when /linux/              then "xdg-open"
              when /mswin|mingw|cygwin/ then "start"
              end
        cmd && Kernel.system(cmd, uri)
      rescue StandardError
        false
      end
    end
  end
end
