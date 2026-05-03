# ADR 0012: Output-free service objects, dry-monads Result contract, three-interface architecture

**Status:** Accepted — partially amended by [ADR-0014](0014-ship-bundler-and-rubygems-plugins.md). The output-free service-layer / dry-monads / dry-operation contract stands. Packaging is changed: ADR-0014 collapses the planned separate `rubygems-contribute` gem into a single `gem-contribute` gem with three entry points, and adds a Bundler plugin alongside.
**Date:** 2026-05-03
**Amends:** [ADR-0006](0006-standalone-gem-not-plugin.md) — adds a RubyGems plugin as a third interface; the Bundler plugin decision was unchanged at the time of this ADR (subsequently reversed by ADR-0014).

## Context

`Operations::Fork` and `Operations::Clone` accept `stdout:` and print progress lines as side effects during `call`. This couples service objects to a specific output model and breaks down across the three interfaces now in scope:

- **CLI** (`gem-contribute`): stdout/stderr strings, synchronous.
- **TUI** (bubbletea, ADR-0010): no output stream — results travel as messages delivered by Commands to `Update`, which renders model state.
- **gem plugin** (`gem contribute`): a RubyGems plugin (not a Bundler plugin — see ADR-0006) that reuses the CLI pipeline but is a distinct interface layer.

Injecting an `Output::Tui` into service objects would require it to dispatch callbacks back into bubbletea's async event loop from a synchronous call site inside a Command. That is complex, depends on unverified bubbletea-ruby API surface (ADR-0010 flagged this explicitly), and routes information through a mechanism it doesn't belong in.

Separately, several places in the codebase signal failure by returning `nil` and printing to `stderr` as a side effect (notably `Workflow#build_adapter`). This mixes concerns: the service layer decides what to say, and callers are left checking `nil` without knowing why.

Workshop constraints (Blue Ridge Ruby 2026) that previously argued against dry-rb ecosystem dependencies no longer apply — the workshop concluded 2026-05-02.

## Decision

1. **Service objects are output-free.** `Operations::*` and all data-layer classes accept no `stdout:` or `stderr:` parameter and produce no I/O side effects.

2. **Service objects return `dry-monads` `Result` types.** `Success(value)` on the happy path, `Failure(reason)` for expected error conditions. Typed exceptions (`AuthRequired`, `AdapterError`) are no longer used as cross-layer control flow; they may still be raised and rescued within a single layer.

3. **Multi-step pipelines use `dry-operation`.** The fork → clone → branch → announce sequence in `fix` is expressed as a `dry-operation` pipeline: each step receives and enriches a shared input, and failure at any step short-circuits the chain.

4. **Three interface layers share service objects and own their own output.**
   - CLI: prints around service calls using `Output::Standard` (wraps `stdout`/`stderr`; exposes `#info`, `#warn`, `#error`).
   - TUI: wraps service calls in Commands; `Update` renders the returned `Success`/`Failure` as model state.
   - gem plugin: reuses the CLI pipeline; does not launch the TUI.

5. **`Output::Standard` and `Output::Null` live in the interface layer only.** Service objects never see them.

## Reasoning

**Output-free is the only shape that works across all three interfaces.** The TUI has no output stream — injecting one requires plumbing that doesn't exist yet (bubbletea-ruby's callback story is unverified). Output-free service objects with Result return types leave each interface free to handle output in the way natural to it.

**`dry-monads` Result over exceptions for cross-layer signaling.** Auth failure and adapter errors are expected outcomes, not exceptional conditions — the adapter will regularly encounter them on the happy path (rate limits, unauthenticated users, forks that already exist). `Failure(:unauthenticated)` makes the call site enumerate every outcome explicitly rather than knowing which exceptions to rescue. Ruby 3.2 `case/in` pattern matching on `Success`/`Failure` is readable and idiomatic.

**`dry-operation` over manual step composition.** The fix pipeline currently threads state through sequential calls with early returns on `nil`. `dry-operation` names each step, makes its `Success`/`Failure` contract explicit, and allows testing each step in isolation. Adding `dry-operation` pulls in `dry-monads` transitively, so one gemspec entry covers both.

**RubyGems plugin is a distinct interface, not covered by ADR-0006.** ADR-0006 rejected the *Bundler* plugin pattern (`bundle contribute`). A RubyGems plugin (`gem contribute`) registers a `Gem::Command` in a gem named `rubygems-contribute` — a different mechanism, not considered in ADR-0006. The three-interface architecture creates a natural home for it: it reuses the CLI pipeline without touching the TUI.

## Alternatives considered

- **`Output` abstraction injected into service objects** (`Output::Standard`, `Output::Tui`). Rejected: `Output::Tui` requires a dispatch callback into bubbletea's event loop from a synchronous call site inside an async Command. Complex, unverified, routes output through the wrong abstraction.

- **Keep `stdout:` injection; pass a null output to the TUI.** Rejected: silently drops progress information that the TUI should surface as model state. Information is lost rather than translated.

- **`dry-transaction` instead of `dry-operation`.** Rejected: `dry-transaction` is deprecated by the dry-rb team. `dry-operation` is the current recommendation with the same step-composition semantics.

- **Native Ruby only (`Data.define` results + typed exceptions + `case/in`).** Valid; Ruby 3.2 has most of the surface. Rejected now that workshop constraints are lifted: `dry-monads` provides a richer failure vocabulary, Do notation reduces boilerplate in multi-step callers, and `dry-operation` formalizes pipeline shape more explicitly than manual early-returns.

## Consequences

**On `Operations::Fork` and `Operations::Clone`:** remove `stdout:`. Both return `Success(Result)` or `Failure(reason)`. `Operations::Clone::Result` gains a `reused:` field (mirroring `Operations::Fork::Result`) so CLI callers can print the appropriate message without asking the operation what happened.

**On `Workflow#build_adapter`:** remove `nil`-returning and stderr side effect. Return `Success(adapter)` or `Failure(:unauthenticated)`. Callers pattern-match.

**On `CLI::Fork#execute` and `CLI::Fix#execute`:** print progress and results around service calls using `Output::Standard` rather than raw `@stdout`/`@stderr`.

**On `CLI::Fix`:** the fork → clone → branch → announce sequence becomes a `dry-operation` pipeline.

**On dependencies:** add `dry-operation` to the gemspec (verify current version on rubygems.org before pinning; `~> 0.1` at time of writing). `dry-monads` is pulled in transitively but may be listed explicitly for clarity.

**On the gem plugin:** a future `rubygems-contribute` gem registers a `Gem::Command` and delegates to the CLI pipeline. This ADR establishes its architectural home; a separate ADR is not required for its internal structure.

**On ADR-0006:** status updated to note that the Bundler plugin decision is unchanged, but a RubyGems plugin interface is now explicitly in scope under ADR-0012.

**On `CLAUDE.md`:** the working-agreement bullet "Async work is always a bubbletea Command" gains a companion: "Service objects return `dry-monads` `Result` types and produce no output."

## What this doesn't change

- ADR-0001 (just-in-time auth). The auth flow's shape is unchanged; the signaling mechanism moves from exception to `Failure`.
- ADR-0002 through ADR-0005 (data layer). Parsers and resolvers are already output-free.
- ADR-0010 (bubbletea + lipgloss). Framework choice unchanged; this ADR defines the contract those Commands return.
- ADR-0011 (HostAdapter owns host verbs). The adapter interface is unchanged; its error conditions now propagate as `Failure` rather than raised exceptions at the cross-layer boundary.
