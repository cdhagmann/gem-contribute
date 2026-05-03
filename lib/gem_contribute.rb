# frozen_string_literal: true

require_relative "gem_contribute/version"
require_relative "gem_contribute/errors"

module GemContribute
  autoload :LockedGem, "gem_contribute/locked_gem"
  autoload :Project, "gem_contribute/project"

  # The canonical Project for gem-contribute itself. Used by the CLI to
  # short-circuit resolution (gem-contribute isn't on RubyGems yet) and
  # to auto-inject the tool into its own scan results.
  SELF_PROJECT = Project.new(
    gem_name: "gem-contribute",
    host: "github.com",
    owner: "cdhagmann",
    repo: "gem-contribute",
    metadata: { self_injected: true }
  ).freeze
  autoload :LockfileParser, "gem_contribute/lockfile_parser"
  autoload :Cache, "gem_contribute/cache"
  autoload :Resolver, "gem_contribute/resolver"
  autoload :HostAdapter, "gem_contribute/host_adapter"
  autoload :Auth, "gem_contribute/auth"
  autoload :Config, "gem_contribute/config"
  autoload :TokenStore, "gem_contribute/token_store"
  autoload :Git, "gem_contribute/git"
  autoload :CLI, "gem_contribute/cli"

  module HostAdapters
    autoload :GitHubAdapter, "gem_contribute/host_adapters/github_adapter"
  end

  # Composable bootstrap primitives. See ADR-0011: HostAdapter owns host
  # verbs; Operations compose them with `Git`; CLI verbs compose Operations.
  module Operations
    autoload :Fork, "gem_contribute/operations/fork"
    autoload :Clone, "gem_contribute/operations/clone"
  end
end
