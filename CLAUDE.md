# CLAUDE.md

This file is read by Claude Code when working in this repository. Treat it as the contract for how to make changes here.

## Project shape

`gem-contribute` is a terminal UI that reads a project's `Gemfile.lock`, surfaces open contributable issues from the gems' source repositories, and offers a one-keystroke `fix` flow.

Read `docs/design.md` and the ADRs in `docs/adr/` before making non-trivial changes. The design doc describes the architecture and the ADRs explain why specific decisions were made. If a change conflicts with an ADR, propose updating the ADR first; don't silently violate it.

## Working agreement

- **Decisions before code.** When uncertain about an architectural question, surface the question and the alternatives instead of picking one and writing code. The ADR pattern in `docs/adr/` is how those decisions get recorded.
- **Small PRs.** Each change should be reviewable in one sitting. Multi-commit PRs are fine; multi-concern PRs are not.
- **Test what's testable.** Parsers, resolvers, adapters, and `Update` functions all get tests. View tests assert colors and modifiers. System tests inject events and snapshot results. (The earlier "no TUI tests at v1" stance is obsolete; see ADR-0008.)
- **Match existing style.** Run `bin/rubocop` before opening a PR.
- **Don't reach across boundaries.** The TUI layer talks to the data layer only through Commands and messages. Adapters don't read config files; they receive what they need as arguments. The boundaries exist for testability and for the offline mode.
- **Async work is always a Rooibos Command.** Don't spawn threads. Don't use `Async`. Don't shell out synchronously. If it can take longer than ~50ms, it's a Command.

## What's deliberately out of scope

The following are not bugs, they are design decisions. Don't "fix" them without first proposing an ADR update:

- Label normalization (ADR-0005)
- CONTRIBUTING.md parsing or summarization (ADR-0007)
- Bundler plugin packaging (ADR-0006)
- Direct threading or non-Rooibos async (ADR-0008)
- PR creation from inside the TUI
- Private repos or private gems at v1
- A standalone `Worker` orchestrator class. Fork-clone-branch is a state machine in `Update` driven by Commands. No orchestrator.

## Tooling notes

- Ruby 3.2+ (Ractor support is required for Rooibos's thread-safe state)
- `ratatui_ruby` requires a Rust toolchain to build
- `rooibos` is the TUI framework on top of `ratatui_ruby`; pinned to `~> 0.7.0`
- Cache lives at `~/.cache/gem-contribute/`; nuke it with `gem-contribute --refresh`
- Auth tokens at `~/.config/gem-contribute/auth.json`, mode 0600
- Config at `~/.config/gem-contribute/config.yml`

## When proposing changes

If you're adding a feature: which ADR(s) does it touch? If it doesn't touch any, do you need a new one?

If you're fixing a bug: is there a regression test? If not, why not?

If you're refactoring: what's the user-facing benefit? "Cleaner code" is not a benefit by itself.
