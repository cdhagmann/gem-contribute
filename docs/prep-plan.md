# Pre-conference prep plan

The Blue Ridge Ruby workshop is **April 30 – May 1, 2026**. This document defines what "ready" means and the order of operations to get there.

This plan is meant to be executed agentically by Claude Code, with Chris reviewing at stage boundaries. Read [`CLAUDE.md`](../CLAUDE.md), [`docs/design.md`](design.md), and the [`ADRs`](adr/) before starting. They define the architecture and constraints.

## Honest scope estimate

The five stages below total **roughly 12–20 hours of focused work**. That's more than three weeknight evenings. The plan is structured so that **each stage produces a usefully-complete artifact** — if you run out of time, you stop at the last finished stage and the workshop still works.

Minimum viable workshop = Stages 1, 2, and 4 done. Stage 3 (the TUI) can become the workshop itself if it isn't built ahead.

## Order of work

### Stage 1 — Data pipeline end-to-end

**Goal:** A CLI script that reads `Gemfile.lock` from the current directory, resolves source URLs via RubyGems, and prints a summary table — without auth, without the TUI, without the action. Proves the data layer works.

**Acceptance:**

- [ ] `gem-contribute scan` (or equivalent) prints something like:
  ```
  47 gems · 44 on github.com · 2 on gitlab.com · 1 unknown source
  Top contributable projects (by open `good first issue` count):
    sidekiq           5  github.com/sidekiq/sidekiq
    standard          3  github.com/standardrb/standard
    ...
  ```
- [ ] `LockfileParser` wraps `Bundler::LockfileParser` (per ADR-0002), returns `Gem` structs
- [ ] `Resolver` hits RubyGems v1 API anonymously, prefers `bug_tracker_uri` (per ADR-0003), falls back per the ADR
- [ ] `HostAdapter` interface defined; `GitHubAdapter` implements the unauthenticated read methods (`issues`, `community_profile`, `file_contents`)
- [ ] Disk caching at `~/.cache/gem-contribute/` per the design doc
- [ ] Unit tests for the parser and resolver. VCR cassettes for the adapter. All commit-clean.
- [ ] `bin/rspec` and `bin/rubocop` pass

**Deliberately not in this stage:**
- No auth code. Anonymous GitHub API only.
- No TUI. CLI output via plain `puts`.
- No fork-clone-branch. That's Stage 2.
- No Rooibos dependency yet.

**Stop here and check in with Chris.** Demo the script against `gem-contribute`'s own `Gemfile.lock`. The output should make Chris want to keep going.

### Stage 2 — Auth and the action

**Goal:** Add device-flow auth and the fork-clone-branch action. Still no TUI; everything is CLI flags. Proves the auth and action layers work.

**Acceptance:**

- [ ] `Auth` module implements the OAuth 2.0 Device Authorization Grant against `github.com` per ADR-0004
- [ ] OAuth App client ID is a public constant in source (no secret); document the registration step in a `MAINTAINER.md` or similar
- [ ] Token storage at `~/.config/gem-contribute/auth.json`, mode 0600
- [ ] Polling respects `slow_down` errors and the 15-minute device-code expiry
- [ ] `gem-contribute auth login` and `gem-contribute auth status` CLI commands work
- [ ] `GitHubAdapter` gains `fork`, `already_forked?` methods that raise `AuthRequired` if no token
- [ ] A `fork-clone-branch` CLI subcommand takes a `gem/issue_number` argument, performs the full sequence, prints the local path
- [ ] Unit tests for the auth state machine (the protocol is deterministic — test it)
- [ ] Integration test gated on `GEM_CONTRIBUTE_INTEGRATION=1` against a small friendly gem
- [ ] **Use the tool to open one real PR** — even a typo fix in a README. The proof that the architecture works.

**Deliberately not in this stage:**
- No TUI. The workflow is multiple CLI invocations.
- No JIT prompting. If unauthenticated, error and tell the user to run `auth login`.
- Scope is `public_repo` only.

**Stop here and check in with Chris.** Demo the full CLI flow end-to-end. If the architecture has problems, this is when they show up.

### Stage 3 — TUI with Rooibos

**Goal:** The full TUI per the design doc. Four fragments + auth overlay. JIT auth working through MVU state transitions. This is the v0.1 the workshop attendees see.

**Acceptance:**

- [ ] `rooibos` pinned to `~> 0.7.0` in the gemspec (verify the pinned version against current rubygems.org before committing)
- [ ] `ProjectList` fragment: lists gems from the lockfile with issue counts (lazy-loaded via `Command.http`)
- [ ] `IssueList` fragment: open issues for selected project, labels rendered verbatim per ADR-0005
- [ ] `IssueDetail` fragment: body, labels, action keys (`f`, `c`, `o`)
- [ ] `ContributingViewer` fragment: rendered markdown per ADR-0007
- [ ] `AuthOverlay` fragment: device-flow prompt that fires on `:auth_required`, retries the original action on success
- [ ] All async work goes through Rooibos Commands. No `Thread.new`, no `Async`.
- [ ] `Update` tests for every fragment, covering at minimum each key handler and each command-result message
- [ ] At least one snapshot test for the main flow (project list → issue list → issue detail)
- [ ] Status bar showing rate limit remaining
- [ ] `q` quits, `Ctrl+C` quits, `?` shows help overlay (or note help is unimplemented in the README)
- [ ] `bin/gem-contribute` from any directory with a `Gemfile.lock` launches the TUI

**Deliberately not in this stage:**
- No label normalization (ADR-0005)
- No CONTRIBUTING parsing (ADR-0007)
- No private-repo support
- No `Worker` orchestrator class — fork-clone-branch is a state machine in `Update`

**Stop and check in with Chris.** This is the demo for the workshop opening.

### Stage 4 — Workshop issues

**Goal:** Twelve good-first-issue tickets that workshop attendees can pick from. The meta-joke: a tool for finding good first issues that itself has good first issues.

**Acceptance:**

- [ ] Twelve markdown files in `docs/workshop-issues/`, one per issue, using the template at `.github/ISSUE_TEMPLATE/workshop-issue.md`
- [ ] Each issue is genuinely scoped to ~30 minutes by someone who hasn't seen the codebase
- [ ] Each issue points at a specific file or module
- [ ] Each issue has acceptance criteria that are testable
- [ ] Each issue links to relevant ADRs if a decision constrains the implementation
- [ ] Mix of difficulty: ~4 trivial (status bar tweak, empty state copy, new keybinding), ~6 moderate (new feature, small refactor, additional adapter method), ~2 stretch (rate-limit handling, accessibility pass)

**Suggested topics** (pick the strongest 12, generate more if needed):

- Rate-limit indicator in the status bar
- `homepage_uri` fallback for unresolved gems
- `r` to refresh the current view
- CONTRIBUTING preview in the issue detail pane
- `--version` flag
- Better empty state when no gems have GitHub URLs
- Highlight preferred labels (per config) in the issue list
- `?` help overlay
- "Authenticated as @user" indicator
- Sort gems by issue count
- Skip path/git source gems with a clear status line
- Confirmation dialog before fork-clone-branch
- `o` to open the gem's homepage in browser
- "Last updated" warning for stale-looking gems

**Deliberately not in this stage:**
- Don't create the actual GitHub issues yet. Markdown files in the repo. Chris will create the GitHub issues himself once the repo is public, using these as the source.

### Stage 5 — Workshop tutorial polish

**Goal:** Polish `docs/workshop.md` so attendees can follow it end-to-end without help. Add anything attendees need that isn't already in the README.

**Acceptance:**

- [ ] `docs/workshop.md` covers: pre-arrival setup (Ruby version, Rust toolchain, GitHub account), repo clone, `bundle install`, first-run device flow, the workshop arc
- [ ] Pre-reading section linking to Rooibos's "Why Rooibos" and Rails-developer guide
- [ ] Setup troubleshooting section for common build failures (`ratatui_ruby` Rust toolchain, `rooibos` installation issues, GitHub OAuth quirks)
- [ ] A "first PR template" — a 5-step walkthrough for an attendee who's never opened a PR, using one of the workshop issues as the example
- [ ] README's Quick Start section mirrors the workshop setup steps so non-attendees have the same path

**Deliberately not in this stage:**
- No video or screencast. Words on a page is fine.
- No deep Ratatui or Rooibos tutorial — link out to upstream docs.

## Definition of "ready for the workshop"

You're ready when, on a fresh laptop:

1. `git clone … && cd gem-contribute && bundle install` succeeds
2. `bin/gem-contribute` launches the TUI against a real `Gemfile.lock`
3. `f` on an issue completes the fork-clone-branch flow with the device-flow prompt firing
4. The workshop issues are visible on the public GitHub repo with the `workshop` label
5. `docs/workshop.md` reads cleanly to someone who hasn't seen the project

Anything else is a stretch goal.

## What to do if you're behind schedule

Cut in this order:

1. **Skip Stage 5 polish.** Workshop README at minimum-viable quality is fine.
2. **Cut Stage 4 to 6 issues instead of 12.** Quality matters more than count.
3. **Cut Stage 3 fragments.** `ContributingViewer` is the most droppable; users can read CONTRIBUTING in their browser. `AuthOverlay` can fall back to a CLI prompt during `f` action.
4. **If Stage 3 doesn't ship at all:** the workshop becomes "let's build the TUI together." This is honestly fine and might be a *better* workshop. Be ready to pivot the framing.

Don't cut tests to save time. Tests are how this gets maintained after you're tired.
