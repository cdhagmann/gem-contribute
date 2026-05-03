# ADR 0006: Standalone gem, not a Bundler plugin

**Status:** Partially superseded — the standalone-gem decision stands; the no-Bundler-plugin decision is **reversed by [ADR-0014](0014-ship-bundler-and-rubygems-plugins.md)**. Earlier amendment by [ADR-0012](0012-output-free-service-objects-three-interface-architecture.md) (which added a RubyGems plugin) is now itself superseded by ADR-0014's single-gem packaging.
**Date:** 2026-04-27

## Context

Bundler supports plugins that extend `bundle` with new subcommands. A natural-feeling distribution would be `bundle contribute`, mirroring `bundle fund`. Alternatively, we ship as a standalone gem invoked as `gem-contribute`.

## Decision

Standalone gem at v1. Bundler plugin path is not foreclosed; it just isn't v1's problem.

## Reasoning

Bundler plugin authoring has its own learning curve, its own API surface, and its own debugging story. None of that is the part of this project we want attendees of the Blue Ridge Ruby workshop to learn. They're here to learn Ratatui and OAuth and GitHub's API. The Bundler plugin packaging concerns would actively distract.

A standalone gem also keeps the dev loop shorter: clone, `bundle install`, `bin/gem-contribute`. Plugin development requires installing into Bundler's plugin directory and reasoning about how Bundler isolates plugin gems.

The user-facing UX difference is small. `bundle contribute` is two characters shorter than `gem-contribute` and feels more native. That's not zero, but it's not v1's priority either.

## Alternatives considered

- **Plugin from day one.** Rejected: scope creep for the workshop; harder to maintain; harder for new contributors to dive into.
- **Both.** Rejected: more API surface to keep aligned, double the support burden.

## Consequences

- The CLI binary is `gem-contribute`, not `bundle contribute`.
- Users who want the `bundle contribute` UX can write a one-line shell alias.
- A future ADR can revisit this if the tool sees real adoption and the plugin UX becomes the bottleneck.
