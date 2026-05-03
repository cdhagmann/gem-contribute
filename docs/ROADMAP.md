# Roadmap to v1

**Goal:** v1 of `gem-contribute` ships a single gem with three entry points against `github.com`:

1. **Standalone CLI** — `gem-contribute <verb>`. Bare invocation (no subcommand) launches the **Rooibos TUI** (project list → issue list → issue detail → CONTRIBUTING viewer + auth overlay).
2. **Bundler plugin** — `bundle contribute [verb]`. CLI-only. Bare invocation runs a default summary verb (TBD: `scan` or `list all`).
3. **RubyGems plugin** — `gem contribute [verb]`. CLI-only. Same shape as Bundler plugin.

All three share the same output-free service layer (per [ADR-0012](adr/0012-output-free-service-objects-three-interface-architecture.md)). All three are tested. v1 has a real release on rubygems.org, a CHANGELOG, and CI.

This document is the plan. Decisions still in flight live in [`OPEN_QUESTIONS.md`](OPEN_QUESTIONS.md) and get resolved one at a time.

## Decision history (the short version)

- **Workshop is over** (2026-05-02). Decisions made primarily for workshop scope are reversed.
- **TUI framework: Rooibos** (per [ADR-0013](adr/0013-revert-to-rooibos.md), supersedes ADR-0010). Bubbletea-ruby was a workshop-driven choice; Rooibos enables the post-v1 world map view (issue #5) and matches the project's verbs better.
- **Three entry points, one gem** (per [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md), amends ADR-0006 and ADR-0012). Standalone binary + Bundler plugin + RubyGems plugin all live in the `gem-contribute` gem.
- **GitHub-only at v1.0.** GitLab/Codeberg adapters are v1.x territory. ADR-0011's architecture is the bet that pays off there.
- **Service layer is output-free** (per ADR-0012). dry-monads `Result` returns; dry-operation pipelines; no `stdout:` in operations.

---

## What's already done

- **Data layer.** `LockfileParser`, `Resolver`, `GitHubAdapter`, `Auth`, `TokenStore`, `Cache`, `Operations::Fork`, `Operations::Clone`.
- **CLI verbs.** `init`, `scan`, `issues`, `config`, `auth`, `fork`, `fix`, `submit`.
- **HostAdapter cleanup.** ADR-0011 work landed: adapter owns host verbs, Operations layer composes them, CLI verbs compose Operations.
- **ADR-0012 design.** Service-layer contract is documented (`design-interface-layer.md`); implementation hasn't started.

## What hasn't started

- TUI
- Bundler plugin
- RubyGems plugin
- ADR-0012 implementation (dry-monads, dry-operation, output-free operations)
- Release infrastructure (CI, CHANGELOG, MAINTAINER doc)

---

## Phase 0 — Reset workshop-era decisions (DONE)

Two new ADRs landed:

- [ADR-0013](adr/0013-revert-to-rooibos.md) — Rooibos as the TUI framework, superseding ADR-0010.
- [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md) — Bundler + RubyGems plugins ship at v1, single gem.

Outstanding cleanup:
- [ ] Update ADR-0006 status header to note ADR-0014 amends it.
- [ ] Update ADR-0010 status header to "Superseded by ADR-0013".
- [ ] Update ADR-0012 status header to note ADR-0014 amends it.
- [ ] Sweep `docs/design.md` for residual bubbletea references (mostly already Rooibos).
- [ ] Sweep `docs/design-interface-layer.md` for "bubbletea" → "Rooibos" and update the gem-plugin section to reflect single-gem packaging.

---

## Phase 1 — Service layer (ADR-0012 Phase 1)

Make every operation output-free and Result-returning. This is what lets the TUI and the two plugins reuse the same code paths the standalone CLI uses.

**Steps:**

1. Add `dry-monads`, `dry-operation`, `dry-initializer` to gemspec.
2. Remove `stdout:` from `Operations::Fork` and `Operations::Clone`.
3. Define `Operations::Clone::Result = Data.define(:path, :reused)` (currently returns a bare path).
4. Convert both operations to return `Success(Result)` / `Failure(reason)`.
5. Convert `Workflow#build_adapter` to return `Success(adapter)` / `Failure(:unauthenticated)`.
6. Extract `Operations::Branch` (from inline branch logic in `CLI::Fix`) and `Operations::Announce` (from `CLI::IssueAnnouncer`).
7. Build `Operations::FixPipeline` using `dry-operation` to compose Fork → Clone → Branch → Announce.
8. Replace verbose initializers in `CLI::Fork`/`CLI::Fix` with `dry-initializer` (kills the rubocop suppressions).
9. Update CLI verbs to pattern-match on `Result`. Retire `Workflow#with_workflow_rescues`.

**Acceptance:**
- [ ] No `Operations::*` class accepts `stdout:` or `stderr:`
- [ ] All operations return `Success` / `Failure`
- [ ] `FixPipeline` exists; `CLI::Fix#execute` calls it instead of wiring steps inline
- [ ] All existing tests pass (no behaviour change visible to users)
- [ ] No new rubocop suppressions

---

## Phase 2 — CLI pipeline (ADR-0012 Phase 2)

Move CLI verbs to a semantic output abstraction so the look-and-feel can evolve independently of the service layer.

**Steps:**

1. Introduce `Output::Standard` (wraps stdout/stderr; `#info`, `#warn`, `#error`, `#progress`).
2. Introduce `Output::Null` (for tests).
3. Replace raw `@stdout` / `@stderr` in every CLI verb with `@output`.
4. Add `tty-spinner` for `Output::Standard#progress`.
5. Replace `CLI::Init`'s `stdout.print` + `@gets` with `tty-prompt`.

**Acceptance:**
- [ ] No raw `puts` to `@stdout`/`@stderr` in `lib/gem_contribute/cli/`
- [ ] Long operations show a spinner in TTY contexts and a plain line in non-TTY contexts
- [ ] `Init`'s test suite no longer mocks `gets`
- [ ] User-visible CLI output unchanged for non-interactive flows; spinners appear in interactive ones

---

## Phase 3 — Rooibos TUI

The major work. Per design.md and ADR-0013.

**Pre-work (Q7 verification):**
- [ ] Confirm Rooibos's current published version on rubygems.org
- [ ] Verify `Command.http`, `Command.system`, `Command.wait`, `Command.cancel` still exist in 0.7.x
- [ ] Verify Rooibos snapshot test helpers still ship
- [ ] Pin `rooibos` and `ratatui_ruby` in gemspec

**Fragments:**

- `ProjectList` — gems from the lockfile with issue counts (lazy-loaded via `Command.http`)
- `IssueList` — open issues for the selected project, labels rendered verbatim (ADR-0005)
- `IssueDetail` — body, labels, action keys (`f` fix, `c` open CONTRIBUTING, `o` open in browser)
- `ContributingViewer` — rendered markdown (ADR-0007)
- `AuthOverlay` — device-flow prompt that fires on `:auth_required`

(World map fragment is post-v1; framework choice locks in now per ADR-0013.)

**Wiring:**
- [ ] `gem-contribute` (no args, with a `Gemfile.lock` in cwd) launches the TUI. This is the entry-point change in `cli.rb`.
- [ ] `gem-contribute` (no args, no `Gemfile.lock`) prints a clear "no Gemfile.lock found" message and the USAGE.

**Key contracts:**
- All async work goes through Rooibos Commands (no `Thread.new`, no `Async`)
- `Update` is a pure function tested as such (per fragment)
- Service-layer calls happen inside Commands and return `Result` types (Phase 1's contract)
- Command result messages are pattern-matched in `Update` to `Success(...)` / `Failure(...)` shapes

**Acceptance:**
- [ ] All five fragments render and route as designed
- [ ] `Update` test for every fragment, covering each key handler and each command-result branch
- [ ] At least one snapshot test for the main flow (project list → issue list → issue detail → fix)
- [ ] At least one snapshot test for the auth overlay firing mid-flow
- [ ] `q` quits, `Ctrl+C` quits, `?` shows help overlay
- [ ] Status bar shows rate limit remaining

---

## Phase 4 — Bundler plugin (`bundle contribute`)

A `plugins.rb` entry point at the root of the gem registers a Bundler plugin command per Bundler convention. Delegates to the same dispatch table the standalone CLI uses.

**Constraints:**
- Plugin entry point MUST NOT require Rooibos or `ratatui_ruby` (per ADR-0014). TUI loading is gated to the standalone binary.
- Bare `bundle contribute` runs the default verb (TBD per OPEN_QUESTIONS Q3a: `scan` or `list all`).
- `bundle contribute <verb>` mirrors `gem-contribute <verb>`.

**Acceptance:**
- [ ] `bundle plugin install gem-contribute` works against the local gem
- [ ] `bundle contribute` produces the default summary
- [ ] `bundle contribute fix sidekiq/123` runs the fix verb
- [ ] Smoke test verifies plugin registration without booting the TUI

---

## Phase 5 — RubyGems plugin (`gem contribute`)

A `rubygems_plugin.rb` entry point registers a `Gem::Command` subclass per RubyGems convention. Same dispatch table.

**Constraints:**
- Same TUI-load gating as Phase 4.
- Same default-verb behavior as Phase 4.

**Acceptance:**
- [ ] `gem install gem-contribute` registers the `Gem::Command`
- [ ] `gem contribute --help` lists the same verbs as `gem-contribute --help`
- [ ] `gem contribute fix sidekiq/123` runs the fix verb
- [ ] Smoke test verifies plugin registration without booting the TUI

---

## Phase 6 — Polish, release infrastructure, v1.0

Everything required to call it 1.0 and not 0.x.

**Steps:**
- [ ] CHANGELOG.md created and maintained from this point
- [ ] CONTRIBUTING.md (the irony of not having one is real)
- [ ] MAINTAINER.md documenting OAuth App registration, release process, rubygems push, plugin install verification
- [ ] OAuth App: stay on personal-account App for v1.0 (per Q13); migrate when rate limits bite
- [ ] CI workflow (`.github/workflows/ci.yml`): rubocop + rspec on push/PR; integration test gated behind `GEM_CONTRIBUTE_INTEGRATION=1`; smoke test for `bundle plugin install` + `gem install`
- [ ] Release workflow (`.github/workflows/release.yml`): tagged push → publish to rubygems via **Trusted Publishing (OIDC)**. No API key as secret. Configure rubygems.org trusted publisher entry before first release.
- [ ] Workshop docs moved to `docs/archive/` (`workshop.md`, `talk/`, `workshop-issues/`, `prep-plan.md`)
- [ ] README rewrite for v1 audience (no longer "workshop project"); covers all three entry points
- [ ] Verify `bundle plugin install` and `gem install` paths from a clean machine
- [ ] Open the meta-PR: use `gem-contribute` to add itself to a real project that depends on it
- [ ] Tag `v1.0.0`, push to rubygems

---

## Sequencing logic

- **Phase 0 → 1 → 2 are strictly ordered.** Each unblocks the next.
- **Phase 3, 4, 5 can in principle parallelize** once Phases 1–2 land. In practice Phase 3 (TUI) is the biggest piece and probably ships first; the plugin shims (Phases 4–5) are small once the dispatch table is the single source of truth.
- **Phase 6 happens after** all of 3/4/5 work end-to-end.

If we're behind: Phase 3 is the load-bearing one for "v1 worth releasing." Phases 4–5 can slip to v1.1 if needed (they unlock the better-discoverability story but don't change capability). Phase 6 cannot slip.

---

## Out of scope at v1.0

(Confirmed via OPEN_QUESTIONS Q10.)

- Multi-host adapters (GitLab, Codeberg) — v1.x
- World map view — post-v1, awaits adoption
- Private repos / `repo` OAuth scope — post-v1
- PR creation from inside the TUI — design choice, browser-based stays (ADR-0011)
- AI-anything (ADR-0007)
- Label normalization (ADR-0005)
- CONTRIBUTING parsing (ADR-0007)
