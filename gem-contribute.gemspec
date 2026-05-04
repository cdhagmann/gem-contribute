# frozen_string_literal: true

require_relative "lib/gem_contribute/version"

Gem::Specification.new do |spec|
  spec.name = "gem-contribute"
  spec.version = GemContribute::VERSION
  spec.authors = ["Chris Hagmann"]
  spec.email = ["cdhagmann@gmail.com"]

  spec.summary = "Find and contribute to the open-source Ruby gems your project depends on."
  spec.description = <<~DESC
    gem-contribute reads a project's Gemfile.lock, resolves each gem's source
    repository via the RubyGems API, surfaces open contributable issues from
    those repositories, and offers a one-keystroke fix flow so a
    developer can go from "I noticed an issue" to "I have a working branch" in
    seconds. v0.1 supports GitHub-hosted gems with OAuth device-flow auth.
  DESC
  spec.homepage = "https://cdhagmann.com/gem-contribute/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  github_repo = "https://github.com/cdhagmann/gem-contribute"
  spec.metadata["source_code_uri"] = github_repo
  spec.metadata["bug_tracker_uri"] = "#{github_repo}/issues"
  spec.metadata["changelog_uri"] = "#{github_repo}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore spec/ .rspec .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Bundler ships with Ruby; declared explicitly because we use its lockfile parser.
  # See ADR-0002.
  spec.add_dependency "bundler", ">= 2.4"
  spec.add_dependency "dry-initializer", "~> 3.2"
  spec.add_dependency "dry-monads", "~> 1.10"
  spec.add_dependency "dry-operation", "~> 1.1"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
