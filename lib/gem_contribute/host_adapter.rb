# frozen_string_literal: true

module GemContribute
  # Abstract host adapter. Concrete implementations (GitHubAdapter, future
  # GitLabAdapter, future CodebergAdapter) conform to this interface so the
  # rest of the app — Operations, CLI verbs, TUI — doesn't have to special-case
  # anything beyond looking up the right adapter for a project's host.
  #
  # See ADR-0011: HostAdapter owns the host-API verbs (fork, comment,
  # pull_request_url) plus the host-specific URL templating (clone_url,
  # repo_url). Higher layers compose those primitives; they don't construct
  # host URLs themselves.
  #
  # Public-API methods (no auth needed):
  #   issues(project, labels:)
  #   issue(project, number)
  #   issue_comments(project, number)
  #   community_profile(project)
  #   file_contents(project, path)
  #   search_issues(query)
  #   clone_url(owner, repo)
  #   repo_url(owner, repo)
  #
  # Auth-required methods (raise AuthRequired without a cached token):
  #   fork(project)            — idempotent, blocks until the fork is reachable
  #   comment(project, issue:, body:)
  #   pull_request_url(upstream, head_owner:, head_branch:, title:, body:)
  #   viewer_login
  #
  # See ADR-0001 for the JIT auth contract.
  class HostAdapter
    # Result of a successful `fork(project)`.
    # - clone_url:      HTTPS URL suitable for `git clone`.
    # - fork_url:       human-readable web URL of the fork (used in summaries).
    # - viewer:         the authenticated user's login (and the fork's owner).
    # - reused:         true if the fork already existed; false if just created.
    # - owned_upstream: true when viewer == project.owner (viewer IS the upstream).
    ForkResult = Data.define(:clone_url, :fork_url, :viewer, :reused, :owned_upstream)

    def issues(_project, labels: nil)
      raise NotImplementedError
    end

    def issue(_project, _number)
      raise NotImplementedError
    end

    def issue_comments(_project, _number)
      raise NotImplementedError
    end

    def community_profile(_project)
      raise NotImplementedError
    end

    def file_contents(_project, _path)
      raise NotImplementedError
    end

    def search_issues(_query)
      raise NotImplementedError
    end

    def fork(_project)
      raise NotImplementedError
    end

    def comment(_project, issue:, body:)
      raise NotImplementedError
    end

    def pull_request_url(_upstream, head_owner:, head_branch:, title:, body:)
      raise NotImplementedError
    end

    def viewer_login
      raise NotImplementedError
    end

    def clone_url(_owner, _repo)
      raise NotImplementedError
    end

    def repo_url(_owner, _repo)
      raise NotImplementedError
    end
  end
end
