# Changelog

All notable changes to this project will be documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- README rewritten for the v1 audience. Status section now describes the v1.0 / v1.x / v2.0 sequencing (CLI at 1.0; Bundler + RubyGems plugins and multi-host adapters at 1.x; Rooibos TUI at 2.0) and points at [`docs/ROADMAP.md`](docs/ROADMAP.md) and [ADR-0015](docs/adr/0015-descope-v1-cli-only.md) for detail. Workshop framing removed (closes [#46](https://github.com/cdhagmann/gem-contribute/issues/46)).

## [0.3.1] - 2026-05-04

### Added

- Release workflow (`.github/workflows/release.yml`) — `v*` tag push triggers a publish to rubygems.org via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC). No `RUBYGEMS_API_KEY` secret involved; rubygems.org issues a short-lived token from the GitHub Actions OIDC claim. The workflow verifies the tag matches `GemContribute::VERSION` and that `CHANGELOG.md` has a dated section for it before running rubocop, rspec, and the publish step. First-time setup (rubygems.org pending-trusted-publisher entry, `release` GitHub Environment) is documented in `MAINTAINER.md` (closes [#44](https://github.com/cdhagmann/gem-contribute/issues/44)).

### Fixed

- `Gemfile.lock` regenerated to match `GemContribute::VERSION` after the 0.3.0 bump (commit `077eadb`) updated `version.rb` without running `bundle install`. CI runs bundler in deployment mode and was failing on the lockfile/gemspec mismatch. The MAINTAINER.md per-release checklist now calls out `bundle install` as an explicit step so the next bump doesn't repeat this.

## [0.3.0] - 2026-05-04

### Added

- `gem-contribute fork <gem>` — the look-around-first counterpart to `fix`: fork the gem's repo, clone it, leave you on the default branch with no issue-tied work yet. Same `-e` / `-a` flags. Use this when you want to read the code before deciding whether to commit to a specific issue (closes [#12](https://github.com/cdhagmann/gem-contribute/issues/12)).
- `gem-contribute fix -e` opens your editor in the clone directory after fork/clone/branch. Uses the new `editor` config key, falling back to `$EDITOR` (closes [#14](https://github.com/cdhagmann/gem-contribute/issues/14)).
- `gem-contribute fix -a` launches your configured AI coding tool (new `ai_tool` config key) with the clone directory as cwd. Combine with `-e` to open both — editor first, AI tool second (closes [#14](https://github.com/cdhagmann/gem-contribute/issues/14)).
- `gem-contribute fix` posts a "👋 I've started working on this" comment to the issue by default so other contributors don't double up on the same work. Opt out per-invocation with `--no-comment`, globally with `comment_on_fix: false` in config, or per-repo via `comment_on_fix_overrides` (YAML-only). Posting is soft-fail — the fork/clone/branch part still succeeds even if the comment can't be posted (closes [#18](https://github.com/cdhagmann/gem-contribute/issues/18)).
- `scan` appends `· N claimed` to project lines whose open issues have already been claimed via the working-on-this marker, so you can spot already-in-progress work at a glance (closes [#20](https://github.com/cdhagmann/gem-contribute/issues/20)).
- `issues <gem|all>` prefixes claimed issues with `[claimed]` for the same reason (closes [#20](https://github.com/cdhagmann/gem-contribute/issues/20)).
- Long-running CLI operations (`fix`'s fork → clone → branch pipeline; `submit`'s `git push`) now show a tty-spinner in interactive terminals. Non-TTY contexts (CI, piped output, redirected stderr) fall back to plain status lines — no behavior change for scripted use (closes [#30](https://github.com/cdhagmann/gem-contribute/issues/30)).

### Changed

- `gem-contribute init` reads input through `tty-prompt`. Cosmetic side effect: default values are now displayed in parens — `(~/code/oss)` — instead of brackets — `[~/code/oss]` — matching tty-prompt's convention. Y/n parsing is now built-in instead of hand-rolled (closes [#31](https://github.com/cdhagmann/gem-contribute/issues/31)).
- Internal class `ForkCloneBranch` renamed to `Fix` (the long name was cumbersome and didn't mirror the `fix` CLI verb). User-facing CLI surface unchanged.
- Internal architecture: `HostAdapter` now owns every host-API verb (`fork`, `comment`, `pull_request_url`) plus host-specific URL templating (`clone_url`, `repo_url`); the new `Operations::Fork` / `Operations::Clone` primitives compose those with `Git`; `CLI::Fork` and `CLI::Fix` are thin compositions on top. The fork-readiness polling moved into the adapter — multi-host adapters can model readiness however the host actually works. See [ADR-0011](docs/adr/0011-host-adapter-owns-host-verbs.md). User-facing CLI surface unchanged.
- Internal architecture (ADR-0012 Phase 1): `Operations::*` classes are now output-free and return `dry-monads` `Success` / `Failure` `Result` types; new `Operations::Branch` and `Operations::Announce` primitives; `Operations::FixPipeline` composes Fork → Clone → Branch → Announce via `dry-operation`; `Workflow#build_adapter` returns a `Result` and the old `with_workflow_rescues` rescue chain is gone; `CLI::Fork` / `CLI::Fix` initializers use `dry-initializer`. See [ADR-0012](docs/adr/0012-output-free-service-objects-three-interface-architecture.md). User-facing CLI surface unchanged.
- Internal architecture (ADR-0012 Phase 2): every CLI verb writes through a semantic `Output::Standard` (or `Output::Null` in tests) abstraction — `#info`, `#progress`, `#warn`, `#error` — instead of raw `@stdout.puts` / `@stderr.puts`. `#progress` accepts an optional block and wraps a `tty-spinner` in TTY contexts. Existing constructors still accept `stdout:` / `stderr:` and auto-wrap them, so test suites injecting StringIO streams keep working unchanged. New deps: `tty-spinner ~> 0.9`, `tty-prompt ~> 0.23` (both pure-Ruby) (closes [#29](https://github.com/cdhagmann/gem-contribute/issues/29)).

### Removed

- The `fork-clone-branch` CLI alias has been removed. Use `gem-contribute fix` instead — same behavior, shorter to type.

### Fixed

- `gem-contribute fork` no longer prints `cd <path> && explore` — `explore` was meant as English but read as a (non-existent) shell command, so a copy-paste produced `command not found`. The "Next:" hint is now conditional on `-e` / `-a`: with neither flag it suggests `cd <path> && $EDITOR .`; with either flag it skips the directory step (you're already in your editor) and just points at the `fix` command.

## [0.2.0] - 2026-05-02

### Added

- `gem-contribute init` — interactive first-run setup: prompts for `clone_root` and chains into `auth login` when no token is cached. Users who skip it can run each step separately at any time.
- Rate-limit footer after `scan` and `issues` runs: `GitHub rate limit: 4,587 / 5,000 remaining · resets at 14:32 UTC`. Surfaced so users know whether a degraded run is seconds or minutes away from recovering (closes [#4](https://github.com/cdhagmann/gem-contribute/issues/4)).

### Changed

- `gem-contribute fix` now errors with an `init` hint when `clone_root` is not configured, instead of silently defaulting to `~/code/oss/`. Existing users with a configured `clone_root` are unaffected (closes [#15](https://github.com/cdhagmann/gem-contribute/issues/15)).

### Fixed

- `gem-contribute submit` no longer requires an `upstream` remote. When only `origin` is present (e.g. when dogfooding on your own repo), it treats `origin` as the upstream and emits a same-repo compare URL. The cross-fork path is unchanged for normal contributors.

## [0.1.0] - 2026-04-28

### Added

- `gem-contribute scan [path]` — parse a `Gemfile.lock`, resolve each gem to its source repository, and rank GitHub-hosted projects by open `good first issue` count.
- `gem-contribute issues <gem|all>` — list open good-first-issues for a single gem or every github.com-hosted gem in the lockfile.
- `gem-contribute auth login|status|logout` — OAuth device-flow authentication with GitHub. Token cached at `~/.config/gem-contribute/auth.json` (mode 0600). The login flow auto-copies the one-time code to the clipboard and opens the verification URL in the browser.
- `gem-contribute fix <gem>/<issue#>` (alias: `fork-clone-branch`) — fork the gem's repo, clone the fork to `<clone_root>/<owner>/<repo>`, create a `gem-contribute/issue-<N>` branch from the default, and add an `upstream` remote pointing at the canonical project.
- `gem-contribute submit` — push the current branch to the user's fork and open a pre-filled GitHub compare page in the browser. The PR title and body are pre-populated from the issue (`Closes #<N>.`); the user reviews and submits via the web UI.
- `gem-contribute config set|get|list` — persistent user configuration at `~/.config/gem-contribute/config.yml`. `clone_root` controls where `fix` puts forks.
- `gem-contribute --refresh` — clear the disk cache before running (useful when source repositories have changed faster than the cache TTLs).
- gem-contribute auto-injects itself into its own `scan` and `issues` results, so the tool you're using is always one of the contribution targets you can see.
- Follows GitHub 301 redirects automatically when a repository has been renamed (e.g. `rainbow` → `ku1ik/rainbow`), so renamed projects keep their place in the rankings.

### Notes

- v0.1 is GitHub-only. The `HostAdapter` interface is already in place so GitLab and others can land later without disturbing the data model.
- A Rooibos TUI on top of these commands is planned (see [issue #2](https://github.com/cdhagmann/gem-contribute/issues/2)).
