# Changelog

All notable changes to this project will be documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
