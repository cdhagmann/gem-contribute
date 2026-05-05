# ADR 0013: Revert TUI framework to Rooibos

**Status:** Accepted
**Date:** 2026-05-03
**Supersedes:** [ADR-0010](0010-charm-ruby-tui-framework.md)
**Restores substance of:** [ADR-0008](0008-rooibos-tui-framework.md) (with a new framing)

## Context

[ADR-0010](0010-charm-ruby-tui-framework.md) (2026-05-02) chose bubbletea-ruby + lipgloss-ruby over Rooibos. Two reasons drove that decision:

1. **Workshop onboarding cost.** Rooibos's lambda-as-constant style (`Init = ->`, `View = ->`) was identified in ADR-0008 itself as unfamiliar to Rails developers. ADR-0010 cited this as a real cost for Blue Ridge Ruby 2026 attendees.
2. **Idiomatic Ruby surface.** Bubbletea-ruby's class/mixin shape (`include Bubbletea::Model`) was framed as a more natural Ruby surface for the workshop audience.

The Blue Ridge Ruby workshop concluded 2026-05-02. ADR-0010's primary justification is no longer load-bearing. At the same time, a new feature has entered the v1 roadmap: a near-easter-egg "world map" view ([issue #5](https://github.com/cdhagmann/gem-contribute/issues/5)) showing the locations of users who've kicked the tires on the tool. The feature itself ships post-v1 (until adoption is large enough for the data to be interesting), but the framework choice locks in now.

Stage 3 (the TUI work) has not started. The cost of changing the framework decision is at its lifetime minimum.

## Decision

Use **Rooibos** as the TUI framework. `ratatui_ruby` is the rendering layer Rooibos sits on top of. This is the framework choice originally made in ADR-0008.

## Reasoning

**The workshop-onboarding argument is gone.** The single biggest reason ADR-0010 gave for switching no longer applies. The lambda-as-constant style is a mild stylistic cost for any Ruby developer; it's not a structural barrier. Maintainers and contributors going forward will be self-selected developers who chose to work on this codebase, not workshop attendees parachuted in for a weekend.

**Preserving the world-map view as a future option.** Rooibos sits on `ratatui_ruby`, which exposes the full Ratatui widget surface (canvas, custom blocks, programmable rendering). Bubbletea-ruby is a binding to a different rendering model with a narrower extension story. We don't want to bet against a feature we already know we want to build.

**ADR-0008's original technical reasoning still stands.**

- `Command.http`, `Command.system`, `Command.wait`, `Command.cancel` map exactly to the project's verbs (HTTP to GitHub, shelling out to `git`, polling the device-flow endpoint). Bubbletea-ruby followed the Go idiom of "a Command is a closure that returns a message" and required us to write our own thin helpers for these.
- Rooibos shipped pure-function `Update` testing, snapshot helpers, and a headless terminal style-assertion harness at 0.7. ADR-0010 explicitly flagged bubbletea-ruby's testing story as unverified and a risk to mitigate post-decision.
- Rooibos's Router DSL maps to the four-fragment design directly. Bubbletea-ruby required us to build the routing.

**Same maintainer as `ratatui_ruby`.** Reduces the chance of cross-library impedance mismatch — the same property ADR-0008 cited.

## Tradeoffs accepted

- **Pre-1.0 framework risk** (same as ADR-0008). Rooibos at 0.7 has "APIs may change before 1.0." Mitigation: pin to a known-good version, bump deliberately, ADR if a bump requires meaningful changes.
- **Rust toolchain on source-build platforms.** `ratatui_ruby` is precompiled for the common platforms but builds from source on Linux musl, Linux arm64, and macOS x86_64. Document in `MAINTAINER.md` and the README.
- **Lambda-as-constant style** stays, but is now a maintainer/contributor concern rather than a workshop-attendee concern. Acceptable.

## Alternatives considered

- **Stay on bubbletea-ruby (ADR-0010).** Rejected: the workshop justification has expired, the Command primitives don't match the project's verbs without writing our own helpers, and the world-map view is a non-trivial extension on top of the bubbletea rendering model.
- **Wait for Rooibos 1.0.** Same logic ADR-0008 used to reject this: 1.0 timeline unknown, the architectural fit is too good to defer, pinning is sufficient mitigation.

## Consequences

**On dependencies:** add `rooibos` (`~> 0.7.0`) and `ratatui_ruby` to the gemspec. Remove `bubbletea` and `lipgloss` (which were never actually added — ADR-0010 was a paper decision, no code shipped against it).

**On `docs/design.md`:** Already framed in Rooibos terms (the bubbletea revision in ADR-0010 was never propagated through). Minor cleanup needed where doc text mentions bubbletea.

**On `docs/design-interface-layer.md`:** The TUI pipeline section refers to "bubbletea Command" and "bubbletea-ruby" — replace with Rooibos terminology. The Result-pattern-matching contract is unchanged (per ADR-0012, which is unaffected).

**On `CLAUDE.md`:** Already says Rooibos. No change needed.

**On the workshop docs:** Workshop is over; archive `docs/archive/workshop.md` and any workshop-specific framing.

**On ADR-0010:** marked Superseded by ADR-0013.

**On ADR-0008:** Already superseded by ADR-0010; that link stands. The fact that ADR-0013 restores ADR-0008's *substance* is captured in this ADR's header rather than reopening the older one.

## What this *doesn't* change

- ADR-0001 (just-in-time auth). Same MVU-shaped flow.
- ADR-0002, ADR-0003, ADR-0004, ADR-0005, ADR-0007, ADR-0009 (data layer / display rules). Outside the TUI.
- ADR-0006 (standalone gem). Packaging concern; orthogonal.
- ADR-0011 (HostAdapter owns host verbs). Service layer; orthogonal.
- ADR-0012 (output-free service objects, dry-monads). The contract is framework-independent — Rooibos has the same "Commands return messages, not stdout" property bubbletea did, so the substance carries over unchanged.
- ADR-0014 (Bundler + RubyGems plugins as v1 interfaces). Orthogonal — plugins are CLI-only.
