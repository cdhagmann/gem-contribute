# frozen_string_literal: true

module GemContribute
  # Abstract host adapter. Concrete implementations (GitHubAdapter, future
  # GitLabAdapter, future CodebergAdapter) conform to this interface so the
  # TUI doesn't have to special-case anything beyond looking up the right
  # adapter for a project's host.
  #
  # Public-API methods (no auth needed):
  #   issues(project, labels:)
  #   community_profile(project)
  #   file_contents(project, path)
  #
  # Auth-required methods (raise AuthRequired without a cached token):
  #   fork(project)
  #   already_forked?(project)
  #
  # See ADR-0001 for the JIT auth contract.
  class HostAdapter
    def issues(_project, labels: nil)
      raise NotImplementedError
    end

    def community_profile(_project)
      raise NotImplementedError
    end

    def file_contents(_project, _path)
      raise NotImplementedError
    end

    def fork(_project)
      raise NotImplementedError
    end

    def already_forked?(_project)
      raise NotImplementedError
    end
  end
end
