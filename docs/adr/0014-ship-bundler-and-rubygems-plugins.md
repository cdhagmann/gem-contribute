# ADR 0014: Ship Bundler and RubyGems plugins as v1 interfaces

**Status:** Accepted
**Date:** 2026-05-03
**Amends:** [ADR-0006](0006-standalone-gem-not-plugin.md), [ADR-0012](0012-output-free-service-objects-three-interface-architecture.md)

## Context

[ADR-0006](0006-standalone-gem-not-plugin.md) (2026-04-27) decided to ship as a standalone gem rather than a Bundler plugin. The primary reason was workshop scope — Bundler plugin authoring would distract attendees from the actual learning objectives (Ratatui, OAuth, GitHub's API). It explicitly left the door open: *"A future ADR can revisit this if the tool sees real adoption and the plugin UX becomes the bottleneck."*

[ADR-0012](0012-output-free-service-objects-three-interface-architecture.md) (2026-05-03 morning) added a RubyGems plugin (`gem contribute`) as a third interface, alongside the standalone CLI and the (then-bubbletea) TUI. It noted that the Bundler plugin decision in ADR-0006 was unchanged.

The Blue Ridge Ruby workshop concluded 2026-05-02. ADR-0006's workshop-scope concern is no longer load-bearing.

Separately: the v1 release goal now includes both `bundle contribute` *and* `gem contribute` as discoverable entry points, alongside `gem-contribute` itself. This makes the tool reachable from whatever invocation surface a user is already in.

## Decision

Ship three entry points for v1:

1. **`gem-contribute`** — standalone CLI binary. Bare invocation (no subcommand) launches the Rooibos TUI. Subcommands run as CLI verbs.
2. **`bundle contribute`** — Bundler plugin. CLI-only. Bare invocation runs a default summary verb (TBD: `scan` vs `list all`). Subcommands run as CLI verbs.
3. **`gem contribute`** — RubyGems plugin. CLI-only. Same shape as `bundle contribute`.

All three entry points ship in **a single gem** (`gem-contribute`). One `gem install gem-contribute` registers the standalone binary, the Bundler plugin, and the RubyGems plugin.

## Reasoning

**The workshop scope-creep argument has expired.** ADR-0006's central rejection was "plugin authoring would distract workshop attendees." Workshop is done; the v1 audience is end users and contributors, not workshop attendees. The remaining ADR-0006 reasoning (UX nicety of `bundle X`) actually *supports* shipping plugins.

**Plugin entry points are CLI-only, by design.** Bundler and RubyGems plugin ecosystems are built around CLI subcommands, not interactive TUIs. Users running `bundle contribute` expect the same kind of behavior as `bundle exec`, `bundle install`, etc. — text in, text out. The TUI is a property of the standalone binary; the plugins delegate into the same service-layer entry points the CLI uses.

This has a useful architectural consequence: the plugin entry points never need to load Rooibos or `ratatui_ruby`. Plugin install stays lightweight, and plugin invocations don't pay the TUI startup cost.

**One gem rather than three.** ADR-0012 sketched a future `rubygems-contribute` gem. Three gems would follow Ruby ecosystem convention (`bundler-X`, `rubygems-X`) but tripples release ceremony, version coordination, and CHANGELOG maintenance. For a project this size, that cost is not earned. One gem with three entry points: one `gem install`, one CHANGELOG, one version, all three interfaces work.

**ADR-0012's three-interface framing carries over unchanged.** The service layer (output-free, returns `Result`) is what enables three interfaces to share code. ADR-0014 doesn't add a fourth interface; it confirms the third (Bundler plugin) and locks the packaging to a single gem.

## Alternatives considered

- **Stay standalone-only (ADR-0006 unmodified).** Rejected: the original justification (workshop scope) no longer applies, and one of v1's product goals is to make the tool reachable from `bundle X` and `gem X` invocations.
- **Three separate gems.** Rejected: triples release ceremony for marginal architectural cleanliness. The plugin shims would be tiny — a Bundler `Plugin::API` registration and a `Gem::Command` subclass — not worth their own gemspec, version, and changelog.
- **Ship `bundle contribute` only, defer `gem contribute` to v1.x.** Rejected as worse-of-both-worlds: same release work, half the surface area covered. They're symmetric pieces of work.
- **TUI in plugins too.** Rejected: not idiomatic for the Bundler/RubyGems plugin ecosystems, doubles the per-invocation startup cost, and the standalone binary already serves the "I want the TUI" use case.

## Consequences

**On the gemspec:**
- Add `plugins.rb` (Bundler plugin entry point) per Bundler plugin convention.
- Add `rubygems_plugin.rb` (RubyGems plugin entry point) per RubyGems plugin convention.
- The two entry points register their respective subcommand classes (or delegate to a shared dispatch table).

**On `lib/gem_contribute/cli.rb`:**
- The dispatch table becomes the single source of truth for verb registration.
- Bare-arg behavior diverges per entry point: `gem-contribute` launches TUI; `bundle contribute` and `gem contribute` run a default CLI verb.
- Consider `dry-cli` to formalize multi-entry-point command registration (deferred decision; see OPEN_QUESTIONS Q6 sub-question).

**On the Bundler plugin entry point:** must not require Rooibos or `ratatui_ruby` at load time. TUI loading is gated to the standalone-binary entry point only.

**On `ADR-0006`:** status updated to note ADR-0014 amends it. The standalone-gem decision stands; the no-Bundler-plugin decision is reversed.

**On `ADR-0012`:** status updated to note ADR-0014 amends it. The three-interface architecture is preserved; the planned separate `rubygems-contribute` gem is replaced by a single `gem-contribute` gem with three entry points.

**On `docs/design-interface-layer.md`:** "gem plugin pipeline" section needs updating — the plugin shim is internal to the `gem-contribute` gem, not a separate `rubygems-contribute` gem. Same change for the Bundler plugin section (which doesn't yet exist; needs adding).

**On testing:** add at least one smoke test per plugin entry point that proves the plugin registers and dispatches a verb without booting the TUI. Implementation tests live in the existing CLI verb specs (verbs aren't aware of which entry point invoked them).

**On release:** the `bundle plugin install gem-contribute` and `gem install gem-contribute` paths both need verification before v1 ships. Add to Phase 6 acceptance.

## What this *doesn't* change

- ADR-0001 through ADR-0005, ADR-0007 (data layer, display rules). Plugin entry points reuse the same service layer.
- ADR-0009 (top-level namespace). Plugins live under `GemContribute::` like everything else.
- ADR-0011 (HostAdapter owns host verbs). Service layer; orthogonal.
- ADR-0013 (Rooibos as TUI framework). The plugins are CLI-only; framework choice doesn't reach them.
