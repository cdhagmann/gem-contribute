# gem-contribute

[![CI](https://github.com/cdhagmann/gem-contribute/actions/workflows/ci.yml/badge.svg)](https://github.com/cdhagmann/gem-contribute/actions/workflows/ci.yml)

Find contributable issues in the gems your project already depends on.

```
$ gem-contribute scan
Scanning Gemfile.lock (44 gems)...
44 gems · 42 on github.com · 2 unknown source

Top contributable projects (by open contributable issue count):
  rubocop          4  github.com/rubocop/rubocop
  rspec            1  github.com/rspec/rspec
  rspec-core       1  github.com/rspec/rspec
  reline           1  github.com/ruby/reline
  ...
  gem-contribute   1  github.com/cdhagmann/gem-contribute
```

The premise: the gems in your `Gemfile.lock` are the projects you have the most context on. If you depend on `sidekiq`, you have opinions about Sidekiq. That's a better starting point for open-source contribution than scanning all of GitHub for `good-first-issue` tags and hoping one looks interesting.

## Status

v0.x; the first 1.0-track release ships via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) on rubygems.org once the polish phase lands.

The 1.0 surface is the standalone CLI shown above. The roadmap that follows it:

- **v1.x** — `bundle contribute` and `gem contribute` plugins (so the tool is reachable from whatever invocation surface you're already in), plus multi-host adapters (GitLab, gem.coop). Same CLI shape; additional entry points and additional sources.
- **v2.0** — Rooibos TUI as the bare-invocation experience for `gem-contribute`. Major version because bare-invocation behavior changes when the TUI auto-launches. ([issue #2](https://github.com/cdhagmann/gem-contribute/issues/2))

[`docs/ROADMAP.md`](docs/ROADMAP.md) has the detail; [ADR-0015](docs/adr/0015-descope-v1-cli-only.md) explains why this sequencing.

## Install

```
gem install gem-contribute
```

Requires Ruby 3.2 or later.

## Usage

The CLI is a small set of subcommands:

```
gem-contribute init                   One-time interactive setup (sets clone_root, then auth).
gem-contribute scan [path]            Summarize the contributable surface of a Gemfile.lock.
gem-contribute issues <gem|all>       List contributable issues for one gem (or all).
gem-contribute auth login             Authenticate with GitHub via OAuth device flow.
gem-contribute fork <gem|owner/repo>  Fork and clone any GitHub repo, land on the default branch.
gem-contribute fix <gem>/<issue#>     Fork, clone, and branch from main for a specific issue.
gem-contribute submit                 Push the branch and open a pre-filled PR in the browser.
gem-contribute config set <key> <val> Persist user preferences (e.g. clone_root).
```

A typical session:

```sh
$ gem-contribute init                    # one-time: sets clone_root, then auth via GitHub device flow
$ gem-contribute scan                    # see what's worth contributing to
$ gem-contribute issues rubocop          # drill into one project's issues
$ gem-contribute fix rubocop/12345       # fork, clone, branch
$ cd ~/code/oss/rubocop/rubocop          # whatever clone_root you set during init
# ... make your change, commit ...
$ gem-contribute submit                  # push + open the PR compare page in your browser
```

Or, when you want to look around a project before picking an issue, use `fork`:

```sh
$ gem-contribute fork rubocop                       # fork-and-clone a gem by name
$ gem-contribute fork rubyevents/rubyevents -e      # fork-and-clone any GitHub repo and open your editor
```

`fork` does the same fork-clone-upstream sequence as `fix` but stops on the default branch — no issue branch, no comment. Handy for "build it locally and decide what to fix later." When you've picked an issue, `gem-contribute fix <gem>/<issue#>` branches off cleanly.

The auth step (run automatically by `init`, or directly via `gem-contribute auth login`) opens GitHub's device-flow page in your browser and copies the one-time code to your clipboard — same UX as `gh auth login`, no token paste, no client secret. Tokens cache at `~/.config/gem-contribute/auth.json` (mode 0600).

## Configuration

User config lives at `~/.config/gem-contribute/config.yml`. The interactive way to set it is `gem-contribute init`; for scripted setup, use `gem-contribute config`:

```sh
gem-contribute config set clone_root ~/Projects/oss
gem-contribute config list
```

| Key                | Default | Notes |
|--------------------|---------|-------|
| `clone_root`       | _(none)_ | Where `fix` and `fork` clone repos (`<root>/<owner>/<repo>`). Set via `init` or `config set`. `fix` errors if unset. |
| `editor`           | `$EDITOR` | Editor launched by `fix -e` / `fork -e`. Falls back to `$EDITOR` if unset. |
| `ai_tool`          | _(none)_ | AI coding tool launched by `fix -a` / `fork -a` with the clone directory as cwd. |
| `comment_on_fix`   | `true` | Post a "working on this" comment on the issue when `fix` runs. Set to `false` to opt out globally; use `--no-comment` to opt out per invocation. |
| `preferred_labels` | `["good first issue", "good-first-issue", "help wanted"]` | Labels `scan` and `issues` query when counting contributable work. Each label is fetched separately (GitHub's API applies AND logic when labels are joined), then deduplicated by issue number. Pass a comma-separated string or set a YAML list directly. |

Per-repo comment overrides (`comment_on_fix_overrides`) are YAML-only — edit `~/.config/gem-contribute/config.yml` directly:

```yaml
comment_on_fix_overrides:
  owner/repo: false
```

## Design

See [`docs/design.md`](docs/design.md) for the architecture overview and [`docs/adr/`](docs/adr/) for individual decisions with their reasoning. The short version: scan first, auth lazily, abstract the source host so GitHub isn't the only option forever, render the data as the maintainer wrote it (don't normalize labels, don't summarize CONTRIBUTING).

## Contributing

The tool is *for* finding contributable projects, so it had better be one. See [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues tagged [`good first issue`](https://github.com/cdhagmann/gem-contribute/labels/good%20first%20issue) are real and reviewed; issues with [`v1.x`](https://github.com/cdhagmann/gem-contribute/labels/v1.x) and [`v2.0`](https://github.com/cdhagmann/gem-contribute/labels/v2.0) labels indicate which release they're targeted at.

## Disclosure

Built with substantial assistance from Claude (Anthropic). Architecture, design decisions, and code review are mine; a fair amount of the typing isn't. Decisions are documented in `docs/adr/` partly so the reasoning is auditable independent of who or what produced the diff.

## License

MIT.
