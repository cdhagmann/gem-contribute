# frozen_string_literal: true

require "open3"

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
    # The PR itself is NOT opened via API. We push, then open the host's
    # compare/MR page in the browser with title and body pre-filled. This
    # mirrors the `auth login` UX (browser handles the human step) and means
    # the user always reviews the PR text before submitting. The host-specific
    # URL is built by the adapter (ADR-0011).
    class Submit
      include PlatformTools

      BRANCH_REGEX = %r{\Agem-contribute/issue-(\d+)\z}

      def initialize(stdout: $stdout, stderr: $stderr, output: nil,
                     git: GemContribute::Git.new,
                     adapter_factory: ->(token:) { HostAdapters::GitHubAdapter.new(token: token) },
                     store: TokenStore.new,
                     browser_opener: nil,
                     working_dir: Dir.pwd)
        @output = output || Output::Standard.new(out: stdout, err: stderr)
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

        origin = parse_remote("origin", required: true)
        return 1 if origin.nil?

        # When the user owns the upstream (e.g. self-dogfooding) there's no
        # separate fork and no `upstream` remote — fall back to origin and
        # build a same-repo PR.
        upstream = parse_remote("upstream", required: false) || origin
        execute(branch, issue_number, origin, upstream)
      rescue AdapterError => e
        @output.error("submit failed: #{e.message}")
        1
      end

      private

      def execute(branch, issue_number, origin, upstream)
        adapter = @adapter_factory.call(token: @store.token_for("github.com"))
        upstream_project = project_for(upstream)
        title = fetch_issue_title(adapter, upstream_project, issue_number)
        push_branch(branch)
        url = adapter.pull_request_url(
          upstream_project,
          head_owner: origin[:owner],
          head_branch: branch,
          title: pr_title(issue_number, title),
          body: pr_body(issue_number)
        )
        open_and_print(url)
        0
      end

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

        @output.error("submit: branch #{branch.inspect} doesn't match #{BRANCH_REGEX.source}.")
        @output.error("Run `gem-contribute fix <gem>/<issue#>` first to set up the branch.")
        nil
      end

      def parse_remote(name, required:)
        out, _err, status = Open3.capture3("git", "-C", @working_dir, "remote", "get-url", name)
        return missing_remote_error(name) if !status.success? && required
        return nil unless status.success?

        owner_repo_from_url(out.strip)
      end

      def missing_remote_error(name)
        @output.error("submit: no `#{name}` remote configured. Are you inside a git clone?")
        nil
      end

      # Accepts both https://github.com/owner/repo(.git) and git@github.com:owner/repo.git
      def owner_repo_from_url(url)
        if (m = url.match(%r{github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?\z}))
          { owner: m[1], repo: m[2] }
        else
          @output.error("submit: can't parse GitHub owner/repo from #{url.inspect}")
          nil
        end
      end

      def project_for(owner_repo)
        Project.new(
          gem_name: owner_repo[:repo], host: "github.com",
          owner: owner_repo[:owner], repo: owner_repo[:repo], metadata: {}
        )
      end

      def fetch_issue_title(adapter, upstream_project, number)
        adapter.issue(upstream_project, number).fetch("title", nil)
      rescue AdapterError => e
        @output.warn("submit: couldn't fetch issue title (#{e.message}). Continuing without it.")
        nil
      end

      def pr_title(issue_number, title)
        title ? "Fix ##{issue_number}: #{title}" : "Fix ##{issue_number}"
      end

      def pr_body(issue_number)
        "Closes ##{issue_number}.\n\n_Opened via `gem-contribute submit`._"
      end

      def push_branch(branch)
        @output.progress("Pushing #{branch} to origin...")
        @git.push(@working_dir, "origin", branch)
      end

      def open_and_print(url)
        opened = @browser_opener.call(url)
        @output.info(opened ? "Opened browser to:" : "Open this URL to file the PR:")
        @output.info("  #{url}")
      end
    end
  end
end
