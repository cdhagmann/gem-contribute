# ADR 0009: Top-level namespace is `GemContribute`, not `Gem::Contribute`

**Status:** Accepted
**Date:** 2026-04-27

## Context

Running `bundle gem gem-contribute` (and, by extension, `rooibos new .` on a hyphenated gem name) produces a skeleton that nests the project under `Gem::Contribute`. The first commit of this repo did exactly that: `lib/gem/contribute.rb`, `module Gem; module Contribute`.

`Gem` is the namespace of Ruby's stdlib package-management library (`Gem::Specification`, `Gem::Version`, `Gem::Requirement`, `Gem::Dependency`, etc., plus the global `Gem` module method on every spec file we ship). Reopening it for our own application code mixes two unrelated namespaces.

The design doc and ADRs (0001–0008) consistently describe the modules with bare names — `LockfileParser`, `Resolver`, `HostAdapter`, `GitHubAdapter`, `Auth` — never `Gem::Contribute::LockfileParser`. The prose treats them as siblings, not children of `Gem`.

## Decision

Top-level namespace is `GemContribute`. Files live under `lib/gem_contribute/`, with a primary `lib/gem_contribute.rb` entry point. The gem name on RubyGems stays `gem-contribute` (the binary stays `gem-contribute`); only the in-code constant changes.

## Reasoning

**Avoids stdlib collisions.** Inside `module Gem::Contribute`, every reference to `Gem` resolves to *our* reopened module first, not to stdlib. This is fine until it isn't — the moment we reach for `Gem::Specification` or `Gem::Version` (entirely plausible in a tool that talks to RubyGems) we get either a confusing constant lookup or a Rubocop `Lint/ConstantDefinitionInBlock` style warning. Cheaper to never start.

**Matches the design doc's vocabulary.** ADRs and `docs/design.md` describe modules as if they live in their own namespace. Naming the namespace `GemContribute` makes the code read the way the docs read.

**Internal `LockedGem` struct.** The design doc's prose uses "Gem" for the parsed lockfile entry. To keep that meaning without collision-prone identifiers (`GemContribute::Gem` would shadow stdlib's `::Gem` inside the module body), the value object is named `GemContribute::LockedGem` and the user-facing prose still calls it "a gem from the lockfile."

## Alternatives considered

- **Keep `Gem::Contribute`.** What `bundle gem` produces by default. Rejected for the reasons above. The default is a default; defaults are sometimes wrong.
- **Top-level `Contribute` module.** Short and clean, but `Contribute` as a top-level constant is presumptuous — too many other tools could plausibly use it.
- **`BlueRidge::GemContribute` or `Workshop::GemContribute`.** Workshop-flavored, but the gem outlives the workshop. Rejected.

## Consequences

- All Ruby files use `GemContribute::Whatever`. RBS signatures match.
- `lib/` layout is `lib/gem_contribute.rb` + `lib/gem_contribute/*.rb`, not `lib/gem/contribute.rb`.
- The gemspec's `require "gem_contribute/version"` replaces `require "gem/contribute/version"`.
- Existing skeleton files from `rooibos new .` (`lib/gem/`, `sig/gem/`, `test/gem/`) are removed; this is a pre-stage-1 reset, not a refactor mid-stream.
