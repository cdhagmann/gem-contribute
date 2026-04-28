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
    those repositories, and offers a one-keystroke fork-clone-branch flow so a
    developer can go from "I noticed an issue" to "I have a working branch" in
    seconds. v0.1 supports GitHub-hosted gems with OAuth device-flow auth.
  DESC
  spec.homepage = "https://github.com/cdhagmann/gem-contribute"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://cdhagmann.com/gem-contribute/"
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
end
