# ADR 0015: Descope v1.0 to standalone CLI; plugins to v1.x; TUI to v2.0

**Status:** Accepted
**Date:** 2026-05-04
**Amends:** [ADR-0014](0014-ship-bundler-and-rubygems-plugins.md)

## Context

The current v1.0 plan (ROADMAP as of 2026-05-04, before this ADR) ships three entry points:

1. Standalone CLI binary (`gem-contribute`) — bare invocation launches the Rooibos TUI
2. Bundler plugin (`bundle contribute`) — CLI-only
3. RubyGems plugin (`gem contribute`) — CLI-only

[ADR-0014](0014-ship-bundler-and-rubygems-plugins.md) (2026-05-03) committed to that scope. It amended [ADR-0006](0006-standalone-gem-not-plugin.md)'s "no Bundler plugin" decision and [ADR-0012](0012-output-free-service-objects-three-interface-architecture.md)'s "three separate gems" sketch. The reasoning was sound: workshop is over, the plugin shims are small, one gem with three entry points is cheap to maintain.

What ADR-0014 didn't examine is **shipping order**. It treated all three entry points as v1.0 prerequisites because that was the existing v1 frame. Phases 3 (TUI), 4 (Bundler plugin), and 5 (RubyGems plugin) on the ROADMAP all sit between "service layer done" and "v1.0 ships."

Two facts shift the calculus on shipping order:

1. **Phase 3 (TUI) is the single biggest piece of remaining work.** Five fragments, an auto-launch wiring change, snapshot tests, and a Rooibos pin verification. Realistically months of work for a solo project that doesn't have it started. Holding 1.0 behind it means the gem stays unpublished while design assumptions about TUI fragments accumulate without real-user contact.

2. **Phases 4–5 (plugins) are thin shims.** Their architecture is already locked in by ADR-0014 (single gem, dispatch table is the source of truth). The remaining design questions — default verb for `bundle contribute` (per OPEN_QUESTIONS Q3a), error/output styling, where the plugin install smoke test sits — are exactly the kind of UX questions that benefit from "what do real CLI users actually do." Building plugin UX on assumptions before any rubygems user exists is a worse trade than shipping the CLI, watching usage, then committing to plugin shape with information.

The Blue Ridge Ruby workshop concluded 2026-05-02 (the same context that drove [ADR-0013](0013-revert-to-rooibos.md) and [ADR-0014](0014-ship-bundler-and-rubygems-plugins.md)). Workshop-era decisions about scope are revisitable.

## Decision

**v1.0 ships the standalone CLI alone.** Three entry points become a release sequence rather than a launch bundle:

- **v1.0** — `gem-contribute` standalone CLI on rubygems.org. Output-free service layer (Phase 1, done), CLI output abstraction (Phase 2, in flight), release infrastructure, README rewrite, and the polish issues that are real papercuts on the core flow.

- **v1.x** — Bundler plugin (`bundle contribute`) and RubyGems plugin (`gem contribute`) ship as point releases. Multi-host adapters (GitLab — issue [#8](https://github.com/cdhagmann/gem-contribute/issues/8); gem.coop — issue [#50](https://github.com/cdhagmann/gem-contribute/issues/50)) also live in this lane. Each of these can be its own minor (1.1, 1.2, …) or rolled together; sequencing is a runtime call.

- **v2.0** — Rooibos TUI. Bare `gem-contribute` invocation switches from "print USAGE" to "launch TUI" at 2.0. Five fragments per design.md, the world-map fragment, the auto-launch wiring change. Treated as a major version because bare-invocation behavior is a user-visible behavior change (existing scripts that pipe `gem-contribute` would now block on a TUI startup).

The "single gem with three entry points" architecture decision in ADR-0014 is **preserved**. Plugins still ship inside the `gem-contribute` gem; they don't become separate gems. What changes is *when*, not *what*.

## Reasoning

**Real users beat planned roadmap.** Every month before the gem hits rubygems.org is a month of design assumptions about TUI fragments, plugin defaults, and edge cases that no real user has stress-tested. Shipping a CLI 1.0 in days converts that uncertainty into evidence. The TUI design that ships in 2.0 will be informed by what real users actually do; the plugin shape that ships in 1.x will be informed by what CLI patterns turn out to matter.

**ADR-0014's architectural decision survives intact.** The v1 commitment to "plugins live inside gem-contribute, not as separate gems" was the load-bearing call. Whether they ship at v1.0, v1.1, or v1.2 doesn't affect the architecture — the dispatch table is already the single source of truth, the plugin entry-point files (`plugins.rb`, `rubygems_plugin.rb`) are tiny additions when the time comes. Deferring is purely sequencing.

**TUI as 2.0 reflects the actual size of the change.** A TUI is not a polish layer; it's a different interaction model. Treating it as a major-version event matches the user-visible weight: bare-invocation behavior changes, dependencies grow (`rooibos`, `ratatui_ruby` move from optional to default), terminal-capability assumptions enter the install path. SemVer-clean.

**Plugins as 1.x because the CLI surface stays compatible.** `bundle contribute` and `gem contribute` are additive — they expose the existing CLI verbs through new entry points. No breaking change for users on `gem-contribute` directly. SemVer-minor fits.

**Repo adapters as 1.x because they extend reach without changing existing behavior.** GitLab and gem.coop adapters expand which gems are scannable; they don't change how scanning works for github.com gems. SemVer-minor fits.

## Alternatives considered

- **Keep ADR-0014's bundle: ship CLI + plugins + TUI all at v1.0.** Rejected: described in detail above. The TUI alone holds 1.0 for an indeterminate period. Plugins built without real-user data lock in UX assumptions early.

- **Ship CLI + plugins at v1.0; defer TUI to v2.0.** Tempting middle ground. Rejected: still puts plugin-UX decisions before rubygems publication, just with a slightly faster timeline. Plugins are a small enough chunk that the lockstep with CLI 1.0 doesn't earn the wait.

- **Ship CLI + TUI at v1.0; defer plugins to v1.x.** Rejected: TUI is the bottleneck regardless. If TUI is in v1.0, plugins-with-it doesn't materially extend the timeline, but TUI alone does.

- **Drop plugins entirely; ADR-0014 supersession instead of amendment.** Rejected: ADR-0014's reasoning for plugins (discoverability via `bundle X` / `gem X`) is still correct. The argument is *when* not *whether*. Supersession would re-litigate a settled question.

- **Drop TUI entirely; remove from roadmap.** Rejected: the TUI is the differentiated UX of the gem (per design.md and the workshop framing). Dropping it loses the project's "render the data the maintainer wrote it" narrative, which is hard to do in CLI alone (CONTRIBUTING viewer especially). 2.0 preserves the commitment with realistic timing.

## Consequences

**On the v1 statement at the top of `docs/ROADMAP.md`** (line 3-9 currently): rewrite. The "single gem, three entry points" framing moves to 2.0; v1.0 is a CLI-on-rubygems release.

**On phase numbering and labels:**

- `phase:1` (DONE), `phase:2` (in flight), `phase:6` (renumbered to **Phase 3** in the new ROADMAP since it's the third remaining v1.0 phase) make up v1.0.
- `phase:3` (TUI) issues — [#2](https://github.com/cdhagmann/gem-contribute/issues/2), [#13](https://github.com/cdhagmann/gem-contribute/issues/13), [#32](https://github.com/cdhagmann/gem-contribute/issues/32) through [#37](https://github.com/cdhagmann/gem-contribute/issues/37) — relabel to `v2.0`.
- `phase:4` (Bundler plugin) issue [#38](https://github.com/cdhagmann/gem-contribute/issues/38) and `phase:5` (RubyGems plugin) issue [#39](https://github.com/cdhagmann/gem-contribute/issues/39) — relabel to `v1.x`.
- Existing v1.x candidates without phase labels — [#8](https://github.com/cdhagmann/gem-contribute/issues/8), [#50](https://github.com/cdhagmann/gem-contribute/issues/50) — also gain `v1.x`.

**On `ADR-0014`:** add an "Amended by ADR-0015" header note. The body of ADR-0014 stays valid — the architectural commitment to "single gem, plugins-not-separate-gems" is unchanged. Only the implicit "all three entry points at v1.0" assumption is amended.

**On `README.md` (`#46` rewrite):** the v1 audience messaging frames the gem as a CLI tool. TUI gets a "coming in v2" mention; plugins get a "coming in v1.x." Avoids over-promising what 1.0 actually delivers.

**On `OPEN_QUESTIONS.md`:** Q3a (default verb for `bundle contribute`) becomes a v1.x decision. Doesn't block 1.0.

**On `MAINTAINER.md`:** the per-release checklist applies identically to 1.x point releases as to 1.0. No changes needed.

**On the existing PR queue:** [PR #51](https://github.com/cdhagmann/gem-contribute/pull/51) (Phase 2) and [PR #55](https://github.com/cdhagmann/gem-contribute/pull/55) (release infra + 0.3.1) are both unaffected — their content is in v1.0 either way. No re-scoping needed for in-flight PRs.

**On polish issues:**

- [#1](https://github.com/cdhagmann/gem-contribute/issues/1), [#9](https://github.com/cdhagmann/gem-contribute/issues/9), [#10](https://github.com/cdhagmann/gem-contribute/issues/9), [#46](https://github.com/cdhagmann/gem-contribute/issues/46), [#54](https://github.com/cdhagmann/gem-contribute/issues/54) — kept in v1.0. Real papercuts on the core flow.
- [#3](https://github.com/cdhagmann/gem-contribute/issues/3) (open verb), [#47](https://github.com/cdhagmann/gem-contribute/issues/47) (meta-PR dogfooding) — pushed to v1.x. Nice to have, not papercuts.

## What this *doesn't* change

- **[ADR-0014](0014-ship-bundler-and-rubygems-plugins.md) architectural decision.** Plugins still live inside `gem-contribute`, not as separate gems. The dispatch table stays the source of truth. Plugin entry points stay TUI-free.
- **[ADR-0013](0013-revert-to-rooibos.md) framework choice.** Rooibos is still the TUI framework when TUI ships at 2.0.
- **[ADR-0012](0012-output-free-service-objects-three-interface-architecture.md) service-layer contract.** Output-free, `Result`-returning operations are what makes the CLI / plugin / TUI split work. The contract is identical whether plugins ship at 1.0 or 1.x.
- **[ADR-0011](0011-host-adapter-owns-host-verbs.md) host adapter design.** Multi-host adapters (GitLab, gem.coop) ship at v1.x using the same architecture.
- **The product thesis.** "Find contributable issues in the gems your project depends on" is unchanged. v1.0 just delivers it in CLI form first.
