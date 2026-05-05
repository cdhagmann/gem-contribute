# Open Questions — Roadmap to v1

Working list of unresolved planning questions for the v1 roadmap (TUI + CLI + `bundle contribute` + `gem contribute`). Walked through one at a time with the maintainer; each gets crossed off and folded into the ROADMAP / ADRs as it's answered.

Order is rough priority — top items block downstream design, bottom items are polish.

---

## Q1. ~~What is the "world map view"?~~ — ANSWERED 2026-05-03

A near-easter-egg view showing the locations of people who've kicked the tires on `gem-contribute`. Tracked as [issue #5](https://github.com/cdhagmann/gem-contribute/issues/5). Not a primary fragment — a hidden/discoverable view.

**Implications this surfaces:**
- Requires some form of opt-in usage reporting (the tool has to phone home with *something* to populate the map). New component: a tire-kicker reporting backend.
- Privacy/consent UX needs to live somewhere — likely first-run prompt or `init` flow.
- Backend service is itself a v1 dependency *if* the map ships in v1.

→ See **Q1a** below.

---

## Q1a. ~~Does the world map ship in v1?~~ — ANSWERED 2026-05-03

No. Preserving the option by choosing Rooibos now; tire-kicker map waits until there's enough adoption to make the data interesting. No backend work in v1 scope.

**ADR-0013 reasoning lock-in:**
1. Workshop onboarding cost — the main argument for bubbletea — is no longer a constraint (workshop ended 2026-05-02)
2. Preserving the world map view (issue #5) as a future option
3. ADR-0008's original technical reasoning still stands (Command primitives matched our verbs, snapshot test helpers, fractal Router architecture)
4. Bubbletea-ruby's testing story was unverified per ADR-0010; Rooibos shipped tested helpers

---

## Q2. ~~Packaging shape~~ — ANSWERED 2026-05-03

One gem. `gem-contribute` ships the standalone CLI, the Bundler plugin hooks, and the RubyGems plugin hooks all together. ADR-0012's mention of a future `rubygems-contribute` gem is overridden by ADR-0014 (the new plugin ADR).

---

## Q3. ~~What do `bundle contribute` / `gem contribute` do?~~ — ANSWERED 2026-05-03

CLI only — no TUI from the plugins. Reasoning: Bundler and RubyGems plugins aren't typically interactive; they're CLI subcommands. The TUI is a property of the standalone `gem-contribute` binary.

- `gem-contribute` (no args) → TUI
- `bundle contribute` (no args) → CLI default (`scan` or `list all` — see **Q3a**)
- `gem contribute` (no args) → CLI default (same)
- `<any>` `<verb>` → CLI verb

**Architectural consequence:** the plugin entry points never need to load Rooibos. Keeps plugin install lightweight.

---

## Q3a. ~~Bare-call default for the plugins: `scan` or `list all`?~~ — ANSWERED 2026-05-05

`scan`. Matches `bundle fund` — runs immediately and prints a ranked summary, no subcommand needed. Tracked as [#63](https://github.com/cdhagmann/gem-contribute/issues/63).

---

## Q4. ~~Default behavior of bare `gem-contribute`~~ — ANSWERED 2026-05-03

Packwerk-style launcher: `gem-contribute` (no args) opens a mini TUI that lists subcommands; arrow keys + enter pick one. `gem-contribute <verb>` runs the verb directly with no TUI in the way.

→ See **Q4a**: this reframes what the "full TUI" is.

---

## Q4a. ~~What happens to the design.md "full TUI"?~~ — ANSWERED 2026-05-03

Bare `gem-contribute` launches the design.md four-fragment TUI (ProjectList → IssueList → IssueDetail → ContributingViewer + AuthOverlay + the eventual WorldMap). The packwerk reference was establishing "yes, raw command launches a TUI" as precedent — not a directive to mirror packwerk's exact subcommand-picker shape. Subcommands stay CLI.

Phase 3 of ROADMAP doesn't need rewriting; just confirm the entry-point wiring in `cli.rb` (no-arg → launch TUI vs print USAGE).

---

## Q5. ~~Multi-host adapters in v1?~~ — ANSWERED 2026-05-03

GitHub-only at v1.0. v1.x point releases will add adapters (GitLab, Codeberg, etc.). ADR-0011's architecture is the bet that paying off.

---

## Q6. ~~Does ADR-0012's dry-rb adoption survive the framework revert?~~ — ANSWERED 2026-05-03

Yes. We need both a CLI and a TUI; output-free service objects with `Result` returns are what lets both consume the same service layer. ADR-0013 (Rooibos revert) doesn't touch ADR-0012.

Sub-question on `dry-cli` adoption is **deferred to Phase 4/5** when the plugin entry points get wired — easier to decide once the plugin shape is concrete.

---

## Q7. Rooibos 0.7.x verification — ASSIGNED TO ME

Pre-Phase-3 task (no user decision needed): confirm Rooibos's current version on rubygems.org, verify Command primitives still exist, verify snapshot test helpers still ship. Folded into ROADMAP Phase 3.

---

## Q8. ~~Workshop docs disposition~~ — MY CALL: archive

Moving workshop-era docs (`workshop.md`, `talk/`, `workshop-issues/`, `prep-plan.md`) to `docs/archive/` in Phase 6. Preserves history without polluting the active doc surface. Flag if you'd rather delete or keep them in place.

---

## Q9. ~~Test framework + cassette policy~~ — MY CALL: keep design.md's strategy as-is

RSpec, VCR cassettes committed, no formal coverage target (just "every public method, every Update branch"). Snapshot helpers come from Rooibos — verified in Q7. Flag if you want a different testing posture for v1.

---

## Q10. ~~v1 out-of-scope confirmation~~ — MY CALL: existing exclusions stand

All ADR-mandated out-of-scope items remain out for v1.0:
- Private repos / `repo` OAuth scope
- PR creation from inside the TUI (browser-based stays per ADR-0011)
- AI-anything
- Label normalization
- CONTRIBUTING parsing
- Multi-host adapters (per Q5; v1.x territory)
- World map view (per Q1a; post-v1)

Flag if anything moves into v1.

---

## Q11. Branding / homepage — DEFER

Pre-release polish; revisit during Phase 6.

---

## Q12. CHANGELOG.md / CONTRIBUTING.md / MAINTAINER.md — task list, not decision

Folded into ROADMAP Phase 6. No decision needed.

---

## Q13. ~~OAuth App identity for v1 release~~ — ANSWERED 2026-05-03

Stay on the personal-account OAuth App for v1.0. Migrate to a dedicated identity when rate limits actually bite. Pragmatic — fits the rest of the v1 scope (don't pay for problems we don't have yet).

---

## Q14. ~~CI / release automation~~ — ANSWERED 2026-05-03

GitHub Actions, two workflows:

**CI (`ci.yml`)** — runs on push/PR:
- rubocop
- rspec
- integration tests gated behind `GEM_CONTRIBUTE_INTEGRATION=1` (off by default)
- smoke test: `bundle plugin install` + `gem install` on a clean Ruby image, verify both plugin entry points dispatch a verb

**Release (`release.yml`)** — runs on `v*` tag push:
- **Trusted Publishing via OIDC.** No API key stored as a secret; rubygems.org issues a short-lived token from the GitHub Actions OIDC claim. Compatible with `rubygems_mfa_required = true` (which the gemspec already sets).
- Setup: configure a trusted publisher entry on rubygems.org (gem name + repo + workflow filename) before the first automated release.

Multi-Ruby matrix and signed gems are post-v1.0 unless they become a real ask.

---

## Notes / parking lot

- `docs/ideas.md` has one stray idea: "Make sure it respects PR templates" — file as a v1 issue.
- `docs/index.md` and `docs/_config.yml` suggest a Jekyll site; not yet investigated.
- `docs/claude-code-prompt.md` — not yet investigated.
