# ADR 0002: Use Bundler's lockfile parser

**Status:** Accepted
**Date:** 2026-04-27

## Context

We need to read `Gemfile.lock` and produce a list of gems with names, versions, and source types (rubygems / git / path).

## Decision

Use `Bundler::LockfileParser` from the `bundler` gem.

## Reasoning

Bundler is already a dependency of any project that has a Gemfile.lock, and it ships a parser that handles every edge case the lockfile format has accumulated over a decade. Writing our own parser is a guaranteed source of bugs that would mostly manifest on other people's machines, with their unusual lockfiles.

The parser API is stable and documented:

```ruby
parser = Bundler::LockfileParser.new(File.read("Gemfile.lock"))
parser.specs  # => Array of Bundler::LazySpecification
```

Each spec has `.name`, `.version`, `.source` — exactly what we need.

## Alternatives considered

- **Write our own line-by-line parser.** Tempting because the format looks simple, but it isn't. Plugins, git sources, path sources, platform-specific gems, and lockfile version differences all complicate it. Rejected.
- **Regex over the file.** No.

## Consequences

- `bundler` is a runtime dependency. It's already on every Ruby developer's machine, but worth declaring explicitly.
- We're coupled to Bundler's internal API. If they change `LazySpecification`, we adapt. The risk is low and the upside is large.
