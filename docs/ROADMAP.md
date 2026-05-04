# Roadmap

**v1.0** ships the standalone `gem-contribute` CLI on rubygems.org against `github.com`. Output-free service layer (per [ADR-0012](adr/0012-output-free-service-objects-three-interface-architecture.md)), real release on rubygems with Trusted Publishing, CHANGELOG, CI.

**v1.x** adds Bundler plugin (`bundle contribute`), RubyGems plugin (`gem contribute`), multi-host adapters (GitLab, gem.coop), and other extensions that ride the existing CLI shape. Architecture for these is locked in (per [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md)); shipping is sequenced after 1.0 lands real users.

**v2.0** ships the Rooibos TUI as the bare-invocation experience for `gem-contribute`. Major version because bare-invocation behavior changes.

The descope of TUI and plugins from v1.0 is recorded in [ADR-0015](adr/0015-descope-v1-cli-only.md).

This document is the plan. Decisions still in flight live in [`OPEN_QUESTIONS.md`](OPEN_QUESTIONS.md) and get resolved one at a time.

> 🌱 marks a [good first issue](https://github.com/cdhagmann/gem-contribute/labels/good%20first%20issue) — small, self-contained scope, friendly for someone new to the codebase.

## Decision history (the short version)

- **Workshop is over** (2026-05-02). Decisions made primarily for workshop scope are reversed.
- **TUI framework: Rooibos** (per [ADR-0013](adr/0013-revert-to-rooibos.md), supersedes ADR-0010). Bubbletea-ruby was a workshop-driven choice; Rooibos enables the world map view (issue #5) and matches the project's verbs better.
- **Single gem with three entry points** (per [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md), amends ADR-0006 and ADR-0012). Standalone binary + Bundler plugin + RubyGems plugin all live in the `gem-contribute` gem. Architecture decision.
- **v1.0 = CLI alone; plugins at v1.x; TUI at v2.0** (per [ADR-0015](adr/0015-descope-v1-cli-only.md), amends ADR-0014). Sequencing decision; ADR-0014's architecture stands.
- **GitHub-only at v1.0.** GitLab/Codeberg/gem.coop adapters are v1.x territory. ADR-0011's architecture is the bet that pays off there.
- **Service layer is output-free** (per ADR-0012). dry-monads `Result` returns; dry-operation pipelines; no `stdout:` in operations.

---

## What's already done

- **Data layer.** `LockfileParser`, `Resolver`, `GitHubAdapter`, `Auth`, `TokenStore`, `Cache`, `Operations::Fork`, `Operations::Clone`.
- **CLI verbs.** `init`, `scan`, `issues`, `config`, `auth`, `fork`, `fix`, `submit`.
- **HostAdapter cleanup.** ADR-0011 work landed: adapter owns host verbs, Operations layer composes them, CLI verbs compose Operations.
- **ADR-0012 service layer (Phase 1).** dry-monads `Result`, dry-operation pipelines, dry-initializer initializers, output-free `Operations::*`. Merged via [PR #48](https://github.com/cdhagmann/gem-contribute/pull/48) on 2026-05-04.
- **Basic CI.** rubocop + rspec on push/PR landed via [PR #21](https://github.com/cdhagmann/gem-contribute/pull/21) (closes [#7](https://github.com/cdhagmann/gem-contribute/issues/7)). Plugin-install smoke and gated integration tests still pending under [#43](https://github.com/cdhagmann/gem-contribute/issues/43).
- **PR template + automated check** ([PR #53](https://github.com/cdhagmann/gem-contribute/pull/53)). Tooling, not part of the v1 phases per se.
- **ADR-0012 Phase 2 (CLI output pipeline).** `Output::Standard`/`Output::Null`, `tty-spinner`-backed `#progress`, `tty-prompt` in Init. Merged via [PR #51](https://github.com/cdhagmann/gem-contribute/pull/51) on 2026-05-04.

## In flight

- **Release infrastructure (Phase 6, partial)** — `release.yml` Trusted Publishing workflow + 0.3.1 cut. Open in [PR #55](https://github.com/cdhagmann/gem-contribute/pull/55).

## What hasn't started

- Remaining release infrastructure (CONTRIBUTING.md polish, README rewrite, plugin smoke tests, the v1.0 tag itself)
- v1.x work (plugins, multi-host adapters)
- v2.0 work (Rooibos TUI)

---

# v1.0 — Standalone CLI

## Phase 0 — Reset workshop-era decisions (DONE)

Two new ADRs landed:

- [ADR-0013](adr/0013-revert-to-rooibos.md) — Rooibos as the TUI framework, superseding ADR-0010.
- [ADR-0014](adr/0014-ship-bundler-and-rubygems-plugins.md) — Bundler + RubyGems plugins ship inside `gem-contribute`, single gem.

ADR header sweep done in commit `00f5a4c`. Doc sweeps:
- [x] 🌱 [#23](https://github.com/cdhagmann/gem-contribute/issues/23) — Sweep `docs/design.md` for residual bubbletea references
- [x] 🌱 [#24](https://github.com/cdhagmann/gem-contribute/issues/24) — Sweep `docs/design-interface-layer.md` for "bubbletea" → "Rooibos"

A third descope ADR landed later: [ADR-0015](adr/0015-descope-v1-cli-only.md) — moves plugins to v1.x and TUI to v2.0.

---

## Phase 1 — Service layer (ADR-0012 Phase 1) (DONE)

Made every operation output-free and Result-returning. This is what lets the eventual TUI and plugins reuse the same code paths the standalone CLI uses. Merged via [PR #48](https://github.com/cdhagmann/gem-contribute/pull/48) on 2026-05-04.

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
- [x] No `Operations::*` class accepts `stdout:` or `stderr:`
- [x] All operations return `Success` / `Failure`
- [x] `FixPipeline` exists; `CLI::Fix#execute` calls it instead of wiring steps inline
- [x] All existing tests pass (no behaviour change visible to users)
- [x] No new rubocop suppressions

**Issues:**
- [x] [#25](https://github.com/cdhagmann/gem-contribute/issues/25) — Adopt dry-rb suite; convert `Operations::Fork`/`Clone` to `Result`
- [x] [#26](https://github.com/cdhagmann/gem-contribute/issues/26) — `Workflow#build_adapter` returns `Result`; retire `with_workflow_rescues`
- [x] [#27](https://github.com/cdhagmann/gem-contribute/issues/27) — Extract `Operations::Branch` and `Operations::Announce`; build `Operations::FixPipeline`
- [x] [#28](https://github.com/cdhagmann/gem-contribute/issues/28) — Migrate `CLI::Fork`/`CLI::Fix` initializers to dry-initializer

---

## Phase 2 — CLI pipeline (ADR-0012 Phase 2) (DONE)

Moved CLI verbs to a semantic output abstraction so the look-and-feel can evolve independently of the service layer. Merged via [PR #51](https://github.com/cdhagmann/gem-contribute/pull/51) on 2026-05-04.

**Steps:**

1. Introduce `Output::Standard` (wraps stdout/stderr; `#info`, `#warn`, `#error`, `#progress`).
2. Introduce `Output::Null` (for tests).
3. Replace raw `@stdout` / `@stderr` in every CLI verb with `@output`.
4. Add `tty-spinner` for `Output::Standard#progress`.
5. Replace `CLI::Init`'s `stdout.print` + `@gets` with `tty-prompt`.

**Acceptance:**
- [x] No raw `puts` to `@stdout`/`@stderr` in `lib/gem_contribute/cli/`
- [x] Long operations show a spinner in TTY contexts and a plain line in non-TTY contexts
- [x] `Init`'s test suite no longer mocks `gets`
- [x] User-visible CLI output unchanged for non-interactive flows; spinners appear in interactive ones

**Issues:**
- [x] [#29](https://github.com/cdhagmann/gem-contribute/issues/29) — `Output::Standard` and `Output::Null`; migrate CLI verbs off raw stdout/stderr
- [x] [#30](https://github.com/cdhagmann/gem-contribute/issues/30) — `tty-spinner`-backed `#progress`
- [x] [#31](https://github.com/cdhagmann/gem-contribute/issues/31) — `CLI::Init` uses `tty-prompt`

---

## Phase 6 — Polish, release infrastructure, v1.0

Everything required to call it 1.0 and not 0.x. Phase number stays at 6 to preserve the existing `phase:6` issue labels and historical references; in the post-ADR-0015 ordering it's the third remaining v1.0 phase.

**Pre-existing user-facing issues that fold into this phase:**
- [ ] 🌱 [#1 — Add `preferred_labels` config so non-canonical good-first-issue labels are caught](https://github.com/cdhagmann/gem-contribute/issues/1)
- [ ] 🌱 [#9 — Add `--label LABEL` flag to scan and issues for one-off overrides](https://github.com/cdhagmann/gem-contribute/issues/9) (related to #1)
- [ ] 🌱 [#10 — Friendlier message when `fix` runs against a repo you own](https://github.com/cdhagmann/gem-contribute/issues/10)
- [ ] 🌱 [#54 — Make `fix` re-runs idempotent (don't error when branch already exists)](https://github.com/cdhagmann/gem-contribute/issues/54)

**Release infrastructure:**
- [ ] 🌱 [#40](https://github.com/cdhagmann/gem-contribute/issues/40) — Add CHANGELOG.md *(file exists; close when satisfied)*
- [ ] 🌱 [#41](https://github.com/cdhagmann/gem-contribute/issues/41) — Add CONTRIBUTING.md *(file exists; close when satisfied)*
- [ ] [#42](https://github.com/cdhagmann/gem-contribute/issues/42) — MAINTAINER.md (release process, OAuth App, plugin verification) *(release-process and OAuth sections done in [PR #55](https://github.com/cdhagmann/gem-contribute/pull/55); plugin verification deferred to v1.x with the plugins themselves)*
- [ ] OAuth App: stay on personal-account App for v1.0 (per Q13); migrate when rate limits bite
- [ ] [#43](https://github.com/cdhagmann/gem-contribute/issues/43) — CI workflow: rubocop + rspec done; gated integration tests still pending; plugin install smoke deferred to v1.x with plugins
- [x] [#44](https://github.com/cdhagmann/gem-contribute/issues/44) — Release workflow with **Trusted Publishing (OIDC)** (in [PR #55](https://github.com/cdhagmann/gem-contribute/pull/55), goes live with the 0.3.1 cut)
- [ ] 🌱 [#45](https://github.com/cdhagmann/gem-contribute/issues/45) — Archive workshop docs to `docs/archive/`
- [ ] [#46](https://github.com/cdhagmann/gem-contribute/issues/46) — README rewrite for v1 audience (CLI-only framing per ADR-0015; "TUI coming in v2.0", "plugins coming in v1.x")
- [ ] Tag `v1.0.0`, push to rubygems

---

## Sequencing logic for v1.0

- **Phase 0 → 1 → 2 → 6** in strict order. Each unblocks the next.
- 1.0 ships when Phase 6 is acceptably complete. Phases 0, 1, and 2 are done; the remaining work is the polish + release set in Phase 6, with [PR #55](https://github.com/cdhagmann/gem-contribute/pull/55) cutting the first publish (0.3.1) once it merges.
- v1.x and v2.0 work cannot start until 1.0 is on rubygems with at least a small user base.

---

# v1.x — Plugins, multi-host adapters, polish extensions

Each item below is independently shippable as a 1.x point release (1.1, 1.2, …). Sequencing is a runtime call informed by what 1.0 users actually ask for.

## Bundler plugin (`bundle contribute`)

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

**Issue:** [#38](https://github.com/cdhagmann/gem-contribute/issues/38) — Bundler plugin: `bundle contribute` entry point

## RubyGems plugin (`gem contribute`)

A `rubygems_plugin.rb` entry point registers a `Gem::Command` subclass per RubyGems convention. Same dispatch table.

**Constraints:**
- Same TUI-load gating as the Bundler plugin.
- Same default-verb behavior as the Bundler plugin.

**Acceptance:**
- [ ] `gem install gem-contribute` registers the `Gem::Command`
- [ ] `gem contribute --help` lists the same verbs as `gem-contribute --help`
- [ ] `gem contribute fix sidekiq/123` runs the fix verb
- [ ] Smoke test verifies plugin registration without booting the TUI

**Issue:** [#39](https://github.com/cdhagmann/gem-contribute/issues/39) — RubyGems plugin: `gem contribute` Gem::Command

## Multi-host adapters

ADR-0011's HostAdapter architecture is the bet that pays off here. Each host is its own adapter implementing the same interface (`fork`, `comment`, `pull_request_url`, etc.).

- [ ] [#8](https://github.com/cdhagmann/gem-contribute/issues/8) — GitLab adapter
- [ ] [#50](https://github.com/cdhagmann/gem-contribute/issues/50) — gem.coop-exclusive gems via Resolver fallback to the gem.coop API

## Other v1.x candidates

- [ ] 🌱 [#3](https://github.com/cdhagmann/gem-contribute/issues/3) — `gem-contribute open <gem>` to open the repo in the browser
- [ ] [#47](https://github.com/cdhagmann/gem-contribute/issues/47) — Meta-PR: use `gem-contribute` against a real downstream
- [ ] [#49](https://github.com/cdhagmann/gem-contribute/issues/49) — `gem-contribute rate <gem|owner/repo>` — Good First Repo scoring (needs an ADR before implementation; the scoring rubric is its own design problem)

---

# v2.0 — Rooibos TUI

**Umbrella issue:** [#2 — Implement Rooibos TUI on top of the v0.1 CLI](https://github.com/cdhagmann/gem-contribute/issues/2). The major work. Per design.md and ADR-0013. v2.0 because bare-invocation behavior changes (`gem-contribute` with no args goes from "print USAGE" to "launch TUI"); existing pipe-into-CLI scripts would otherwise break.

**Pre-work (Q7 verification):**
- [ ] Confirm Rooibos's current published version on rubygems.org
- [ ] Verify `Command.http`, `Command.system`, `Command.wait`, `Command.cancel` still exist in 0.7.x
- [ ] Verify Rooibos snapshot test helpers still ship
- [ ] Pin `rooibos` and `ratatui_ruby` in gemspec

**Fragments:**

- `ProjectList` — gems from the lockfile with issue counts (lazy-loaded via `Command.http`)
- `IssueList` — open issues for the selected project, labels rendered verbatim (ADR-0005)
- `IssueDetail` — body, labels, action keys (`f` fix, `c` open CONTRIBUTING, `o` open in browser)
- `ContributingViewer` — rendered markdown (ADR-0007); also surfaces the upstream PR template per [#13](https://github.com/cdhagmann/gem-contribute/issues/13)
- `AuthOverlay` — device-flow prompt that fires on `:auth_required`

(The world map fragment stays post-v2.0 — awaits adoption to make the data interesting. Framework choice locked in now per ADR-0013.)

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

**Issues (under umbrella [#2](https://github.com/cdhagmann/gem-contribute/issues/2)):**
- [ ] [#32](https://github.com/cdhagmann/gem-contribute/issues/32) — `ProjectList` fragment with lazy-loaded issue counts
- [ ] [#33](https://github.com/cdhagmann/gem-contribute/issues/33) — `IssueList` fragment
- [ ] [#34](https://github.com/cdhagmann/gem-contribute/issues/34) — `IssueDetail` fragment with action keys (f / c / o)
- [ ] [#35](https://github.com/cdhagmann/gem-contribute/issues/35) — `ContributingViewer` fragment (may absorb [#13](https://github.com/cdhagmann/gem-contribute/issues/13))
- [ ] [#36](https://github.com/cdhagmann/gem-contribute/issues/36) — `AuthOverlay` fragment for device-flow prompt
- [ ] [#37](https://github.com/cdhagmann/gem-contribute/issues/37) — No-arg `gem-contribute` launches the TUI

---

# Out of scope (any version)

- Codeberg/sourcehut adapters — no current ticket, post-v1.x.
- World-map TUI fragment — post-v2.0, awaits adoption. Tracked indirectly via [#5](https://github.com/cdhagmann/gem-contribute/issues/5)'s acceptance criteria (which also owns the `KICKED_THE_TIRES.yml` data source).
- Private repos / `repo` OAuth scope — post-v1, no issue.
- PR creation from inside the TUI — design choice, browser-based stays (ADR-0011).
- AI-anything (ADR-0007).
- Label normalization (ADR-0005).
- CONTRIBUTING parsing (ADR-0007).

🌱 [#5](https://github.com/cdhagmann/gem-contribute/issues/5) itself stays open indefinitely as a sandbox for new contributors to practice the `fix` → `submit` loop.

---

## Issue tracking

All roadmap work is tracked on the issue tracker. Filter by label:
- `phase:1`, `phase:2`, `phase:6` for v1.0 work
- `v1.x` for plugin / multi-host / polish-extension work
- `v2.0` for Rooibos TUI work

| Bucket | Issues | Notes |
|---|---|---|
| Phase 0 (DONE) | #23, #24 | Two doc sweeps |
| Phase 1 (DONE) | #25–#28 | Service layer (ADR-0012) |
| Phase 2 (DONE) | #29–#31 | CLI output pipeline |
| Phase 6 (v1.0 polish + release) | #1, #9, #10, #40–#46, #54 | Release infra + papercut polish |
| v1.x | #3, #8, #38, #39, #47, #49, #50 | Plugins, multi-host, extensions |
| v2.0 | #2 (umbrella), #13, #32–#37 | Rooibos TUI |

Out-of-scope items don't get version labels. [#5](https://github.com/cdhagmann/gem-contribute/issues/5) (sandbox) stays without phase or version labels.
