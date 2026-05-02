# ADR 0010: Use Charm-Ruby (bubbletea + lipgloss) for the TUI layer

**Status:** Accepted
**Date:** 2026-05-02
**Supersedes:** [ADR-0008](0008-rooibos-tui-framework.md)

## Context

[ADR-0008](0008-rooibos-tui-framework.md) chose Rooibos (on `ratatui_ruby`) as the TUI framework. That decision was made on 2026-04-27, *before* `bubbletea-ruby` (Marco Roth's Ruby bindings to Charm's Bubble Tea) existed. Bubbletea-ruby was first published on 2025-12-26 and is now at 0.1.4 (March 2026); the companion styling library, `lipgloss-ruby`, is at 0.2.2.

Stage 3 (the TUI work, [issue #2](https://github.com/cdhagmann/gem-contribute/issues/2)) has not started, so the cost of changing this decision is at its lifetime minimum.

## Decision

Use **bubbletea-ruby** as the TUI framework, with **lipgloss-ruby** for styling. This replaces Rooibos and removes `ratatui_ruby` from the dependency tree.

## Reasoning

**Idiomatic Ruby surface.** Bubbletea-ruby's API is plain Ruby — `class Foo; include Bubbletea::Model; def init; def update(msg); def view; end`. Rooibos uses lambda-as-constants (`Init = ->`, `View = ->`), which ADR-0008 itself called out as a real onboarding cost for Rails developers. For Blue Ridge Ruby 2026, lower onboarding cost matters.

**Battle-tested core.** The Go bubbletea library is the dominant TUI framework in the Go ecosystem — used by `gh`, `glow`, the Charm CLI suite, and dozens of other production tools. Bubbletea-ruby is a young binding (0.1.x), but the rendering and event-loop semantics it wraps are mature in a way that no pure-Ruby alternative is.

**Workshop transferability.** "You're learning the Ruby flavor of Bubble Tea" is a stronger pitch than "you're learning Rooibos." MVU is the transferable mental model; Bubble Tea is the largest MVU-TUI ecosystem to walk into afterward.

**Install friction is acceptable on workshop hardware.** Both frameworks ship precompiled binaries via the standard Ruby gem-platform mechanism. On a typical Mac/Linux workshop laptop, `gem install` pulls a binary; no Rust or Go toolchain on the user's machine. Verified on rubygems.org:

| Platform                   | ratatui_ruby (1.5.0) | bubbletea (0.1.4) / lipgloss (0.2.2) |
|----------------------------|-----------------------|---------------------------------------|
| macOS arm64                | precompiled           | precompiled                            |
| macOS x86_64               | source build          | precompiled                            |
| Linux x86_64 gnu           | precompiled           | precompiled                            |
| Linux x86_64 musl          | source build          | precompiled                            |
| Linux arm64 (gnu/musl)     | source build          | precompiled                            |
| Windows                    | precompiled           | source build                           |

Bubbletea wins broadly on Mac+Linux; ratatui_ruby wins on Windows. For a regional Ruby conference, that asymmetry favors bubbletea.

**Companion ecosystem.** Lipgloss-ruby provides idiomatic styling; the Charm-Ruby umbrella (charm-ruby.dev) signals an ongoing port effort, not a one-off binding.

## Tradeoffs accepted

**Project-shaped Command primitives are gone.** Rooibos provides `Command.system`, `Command.http`, `Command.wait`, `Command.cancel` as first-class primitives matching this project's exact verbs. Bubbletea-ruby follows the Go idiom: a Command is a closure that returns a message. We write thin helpers — `http_command(url, envelope:)`, `system_command(argv, envelope:)`, `wait_command(seconds, envelope:)` — once, and use them throughout. This is the only meaningful piece of Rooibos value we reproduce ourselves.

**Test helpers unverified.** Rooibos shipped pure-function-Update testing + snapshot helpers + headless terminal style assertions. Bubbletea-ruby's testing story is not yet documented in its README. Pre-merge of Stage 3, verify what bubbletea-ruby ships and either use it, port `teatest` patterns from Go's bubbletea, or build a minimal snapshot harness. Acceptable risk because pure-function `update` is testable on its own.

**Younger Ruby surface.** Bubbletea-ruby is at 0.1.4; Rooibos was at 0.7/0.8. Both are pre-1.0 with API-change risk; bubbletea-ruby has had less time to settle. Mitigation: pin bubbletea-ruby and lipgloss to known-good versions; bump deliberately with verification.

**Two native gems vs one.** Bubbletea-ruby and lipgloss-ruby are both Go-built native gems; Rooibos was pure Ruby on top of one native gem (`ratatui_ruby`). The user-visible difference is marginal — both `bundle install` to a precompiled binary on common platforms.

**Maintainer alignment.** Rooibos and `ratatui_ruby` were both Kerrick Long: one mind, one ecosystem. Charm-Ruby splits maintainership across charmbracelet (Go upstream) and Marco Roth (Ruby bindings, plus many other projects). When Go upstream bumps an API, Marco's lag determines our exposure. Mitigation: pin to a known-good version; bump deliberately.

**Windows attendees compile.** No precompiled bubbletea binary for Windows. Document the source-build path in `docs/workshop.md` for any Windows attendee.

## Alternatives considered

- **Stay on Rooibos.** ADR-0008's reasoning is no longer current. The "lambda-as-constant style is unfamiliar" cost it identified is removed by switching, and the platform matrix favors bubbletea on the workshop's expected hardware.
- **Bare bubbletea (no lipgloss).** Bubbletea handles the rendering loop; lipgloss handles styling. Skipping lipgloss means hand-building style helpers. Not worth it — lipgloss is small, well-shaped, and idiomatic to use alongside bubbletea.
- **Wait for bubbletea-ruby 1.0.** Same logic as ADR-0008 declining to wait for Rooibos 1.0: the architectural fit is good, the change cost rises every week we delay, and pinning is sufficient mitigation.

## Consequences

**On dependencies:** remove `rooibos` from the gemspec. Add `bubbletea` (`~> 0.1.4`) and `lipgloss` (`~> 0.2.2`). Drop the `ratatui_ruby` Rust-toolchain warning from `docs/workshop.md`.

**On `docs/design.md`:** the TUI-layer section needs reworking — fragments become bubbletea models composed by routing, lambda-as-constant examples are replaced with idiomatic class-with-mixin examples, the Command list (`Command.http`, etc.) is replaced with the wrapper helpers defined above.

**On `CLAUDE.md`:** the working-agreement bullet "Async work is always a Rooibos Command" becomes "Async work is always a bubbletea Command." The package-pinning note about Rooibos is replaced with bubbletea/lipgloss pins.

**On ADR-0008:** marked Superseded by ADR-0010.

**On [issue #2](https://github.com/cdhagmann/gem-contribute/issues/2):** rewritten to point at bubbletea-ruby + lipgloss-ruby instead of Rooibos.

**On the workshop:** attendees still learn MVU, but the framing is "Charm-style TUI in Ruby" — the same pattern as `gh`, `glow`, and the Charm CLIs they may already know.

**On testing:** before Stage 3 lands, verify bubbletea-ruby's test helpers. If absent, port `teatest` patterns or build a minimal snapshot harness. Pure-function `update` testability is independent of the framework choice.

**On the maintainer relationship:** reach out to Marco Roth before the workshop to mention "we're building a workshop project on bubbletea-ruby for Blue Ridge Ruby 2026" — same etiquette ADR-0008 prescribed for Kerrick Long.

## What this *doesn't* change

- ADR-0001 (just-in-time auth). MVU shape preserved; framework change.
- ADR-0002, ADR-0003, ADR-0004 (data layer). Outside the TUI.
- ADR-0005, ADR-0007 (render verbatim, no parsing). Display contract; framework choice doesn't affect it.
- ADR-0006 (standalone gem, not Bundler plugin). Packaging concern; orthogonal.
- ADR-0009 (top-level namespace). Orthogonal.
