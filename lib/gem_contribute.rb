# frozen_string_literal: true

require_relative "gem_contribute/version"
require_relative "gem_contribute/errors"

module GemContribute
  autoload :LockedGem, "gem_contribute/locked_gem"
  autoload :Project, "gem_contribute/project"
  autoload :LockfileParser, "gem_contribute/lockfile_parser"
  autoload :Cache, "gem_contribute/cache"
  autoload :Resolver, "gem_contribute/resolver"
  autoload :HostAdapter, "gem_contribute/host_adapter"
  autoload :Auth, "gem_contribute/auth"
  autoload :TokenStore, "gem_contribute/token_store"
  autoload :CLI, "gem_contribute/cli"

  module HostAdapters
    autoload :GitHubAdapter, "gem_contribute/host_adapters/github_adapter"
  end
end
