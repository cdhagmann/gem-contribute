# gem-contribute

A terminal UI for finding contributable issues in the gems your project already depends on.

```
$ gem-contribute
```

Reads your `Gemfile.lock`, resolves each gem to its source repository, and surfaces open issues — biased toward labels like `good first issue`, `help wanted`, and `documentation`. When you find an issue worth working on, one keystroke forks the repo, clones your fork, and creates a working branch.

The premise: the gems in your lockfile are the projects you have the most context on. If you depend on `sidekiq`, you have opinions about Sidekiq. That's a better starting point for open-source contribution than scanning all of GitHub for issues tagged `good-first-issue` and hoping one looks interesting.

## Status

Early. This is being built as a workshop project for **[Blue Ridge Ruby 2026](https://blueridgeruby.com)**. Expect rough edges through the conference. After that, expect slightly fewer rough edges.

## Install

```
gem install gem-contribute
```

Requires Ruby 3.2 or later. First run will prompt you to authorize the GitHub OAuth app via [device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow) — same UX as `gh auth login`, no token paste, no client secret.

## Usage

From any directory containing a `Gemfile.lock`:

```
gem-contribute
```

Keys:

- `↑/↓` — move
- `Enter` — drill into a gem's issues
- `c` — read CONTRIBUTING.md for the selected project
- `f` — fork, clone, and branch from the selected issue
- `/` — filter
- `q` — quit

## Design

See [`docs/design.md`](docs/design.md) for architecture, and [`docs/adr/`](docs/adr/) for specific decisions and the reasoning behind them.

The short version: scan first, auth lazily, abstract the source host so GitHub isn't the only option forever, render the data as the maintainer wrote it (don't normalize labels, don't summarize CONTRIBUTING).

## Contributing

The tool is for finding contributable projects, so it had better be one. See [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues tagged `good first issue` are real and reviewed.

If you're attending Blue Ridge Ruby 2026 and arrived here from the workshop, see [`docs/workshop.md`](docs/workshop.md) for the exercises.

## Disclosure

Built with substantial assistance from Claude (Anthropic). Architecture, design decisions, and code review are mine; a fair amount of the typing isn't. The decisions are documented in `docs/adr/` partly so the reasoning is auditable independent of who or what produced the diff.

## License

MIT.
