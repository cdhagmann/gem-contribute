# ADR 0008: Use Rooibos for the TUI layer

**Status:** Accepted
**Date:** 2026-04-27
**Supersedes parts of:** the original "TUI built directly on `ratatui_ruby`" approach implied by ADR-0001 and the `docs/design.md` v1.

## Context

`gem-contribute` is a TUI that needs to:

1. Make multiple HTTP calls (RubyGems API, GitHub API, GitHub OAuth device flow polling) without freezing the UI.
2. Shell out to `git` for fork-clone-branch, also without freezing the UI.
3. Compose four primary views (project list → issues → issue detail → CONTRIBUTING) with the auth-prompt flow able to interrupt any of them.
4. Be testable enough that the gem can be maintained past the conference without breaking on every PR.

[`ratatui_ruby`](https://www.ratatui-ruby.dev/) provides the rendering layer, but leaves state management, threading, message dispatch, and testing as exercises for the consumer. [`rooibos`](https://www.rooibos.run/) is a higher-level framework by the same maintainer (Kerrick Long) that layers Model-View-Update on top of `ratatui_ruby`, with async Commands for off-thread work and built-in snapshot testing.

## Decision

Use Rooibos as the TUI framework. `ratatui_ruby` remains a transitive dependency for rendering and widgets, but the application's state, message handling, and async work are expressed in Rooibos terms.

## Reasoning

**The async command pattern is the right abstraction for our problem.** Fork-clone-branch can take 30+ seconds against a large repo. GitHub API calls are routinely 200-500ms. Device-flow polling runs every 5 seconds for up to 15 minutes. Doing any of these on the main thread freezes the UI; doing them ourselves means hand-rolling thread management, message queues, and cancellation. Rooibos provides `Command.system`, `Command.http`, `Command.wait`, and `Command.cancel` as first-class primitives that run off-thread and deliver results back as messages. This is exactly the surface we need.

**Testing is dramatically better.** The original design doc said "no TUI tests at v1, the cost-benefit isn't there." With Rooibos, `Update` is a pure function `(message, model) → model | [model, command]`. Pure functions test trivially, no terminal, no setup, no mocking. View tests use a headless terminal with style assertions. System tests inject events and snapshot results. The pre-conference test commitment goes from "parsers and resolvers only" to "the entire state machine, including the auth flow." This isn't a stretch goal — it's free with the framework.

**The fractal architecture maps to our four-view structure.** Rooibos's Router DSL composes parent fragments out of child fragments. Each view (project list, issue list, issue detail, CONTRIBUTING viewer) becomes a fragment with its own `Model`, `View`, `Update`, and `Init`. The parent dispatches messages to children based on routing rules. This is a structure we'd have to invent and document if we built directly on `ratatui_ruby`; we get it for free.

**The auth flow becomes legible.** With imperative Ratatui, JIT auth requires interrupting the current screen, blocking on a sub-flow, and resuming. With MVU, an `:auth_required` message triggers a state transition; the device-flow polling is a sequence of Commands; the original action retries via another message after success. The whole thing is a state machine, expressed in code as a state machine, testable as a state machine. See ADR-0001 for what this changes.

**Same maintainer as `ratatui_ruby`.** Reduces the chance of cross-library impedance mismatch. Rooibos is the maintainer's opinionated answer to "how should you actually build with this rendering layer."

## Alternatives considered

- **Plain `ratatui_ruby` with our own state and threading.** What the design doc originally implied. Rejected: more code to write and maintain, worse testing story, and we'd be reinventing primitives that Rooibos already provides better. The savings from "fewer dependencies" are dwarfed by the cost of building this layer ourselves.

- **Kit.** Also by Kerrick, OOP component-based, tracked at <https://sr.ht/~kerrick/ratatui_ruby/#chapter-3-the-object-path--kit>. Reasonable for component-heavy UIs with stateful widgets. Rejected for this project: our domain is event-driven and async-heavy (HTTP, system calls, polling), which matches MVU's strengths, and pure-function `Update` is the testing story we want.

- **Wait for Rooibos 1.0.** Rooibos is currently 0.7 with "APIs may change before 1.0." Waiting is the conservative choice. Rejected: the 1.0 timeline is unknown, and the architectural fit is too good to defer. We pin to a specific version and adapt to changes when they come.

## Consequences

**On the design doc:** the "Modules" section needs revision. Views become Rooibos fragments, not bare classes. The `Worker` module disappears — fork-clone-branch is a sequence of Commands emitted from `Update`. The architecture diagram becomes MVU-shaped. Testing strategy shifts from "test the boundaries, skip the TUI" to "test the Update functions everywhere."

**On dependencies:** add `rooibos` to the gemspec. Pin to `~> 0.7.0` for v0.1 (allows patch updates within 0.7, blocks 0.8+ until we audit). Bump deliberately, with an ADR if the bump requires meaningful changes.

**On the workshop:** attendees learn MVU, not just `ratatui_ruby` widgets. This is a real cost — the lambda-as-constant style (`Init = ->`, `View = ->`) is unfamiliar to most Rails developers. Mitigation: the workshop README explicitly frames Rooibos as "the framework," explains MVU in two paragraphs, and points at the "Coming From Rails" guide on rooibos.run before the workshop. Attendees who finish a Rooibos workshop end up with an actually-transferable mental model (MVU shows up in Elm, Redux, Bubble Tea, and increasingly elsewhere).

**On Ractor:** Rooibos uses `Ractor.make_shareable` for thread-safe state. Most Ruby developers have read about Ractors but not used them. The pattern is encapsulated in `Init` and `Update.with(...)`; attendees don't need a deep Ractor mental model to write fragments. Worth a sentence in the workshop preamble, not more.

**On the maintainer relationship:** Kerrick Long maintains both `ratatui_ruby` and Rooibos. Reaching out before the workshop to mention "we're building a workshop project on Rooibos for Blue Ridge Ruby" is good practice — early flag of API changes, possible feedback, possible amplification.

## What this *doesn't* change

- Just-in-time auth (ADR-0001). Implementation cleaner; decision unchanged.
- Bundler's lockfile parser (ADR-0002). Outside the TUI layer entirely.
- Issue tracker URI preference (ADR-0003). Outside the TUI layer.
- Device flow auth (ADR-0004). The flow becomes a sequence of `Command.http` calls in `Update`, but the protocol decision is unchanged.
- Render labels verbatim (ADR-0005). Display concern; the framework rendering them doesn't matter.
- Standalone gem vs Bundler plugin (ADR-0006). Packaging concern; orthogonal.
- Display CONTRIBUTING (ADR-0007). Same.
