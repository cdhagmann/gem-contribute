# gem-contribute

[![CI](https://github.com/cdhagmann/gem-contribute/actions/workflows/ci.yml/badge.svg)](https://github.com/cdhagmann/gem-contribute/actions/workflows/ci.yml)

Find contributable issues in the gems your project already depends on.

```
$ gem-contribute scan
Scanning Gemfile.lock (44 gems)...
44 gems · 42 on github.com · 2 unknown source

Top contributable projects (by open `good first issue` count):
  rubocop          4  github.com/rubocop/rubocop
  rspec            1  github.com/rspec/rspec
  rspec-core       1  github.com/rspec/rspec
  reline           1  github.com/ruby/reline
  ...
  gem-contribute   1  github.com/cdhagmann/gem-contribute
```

The premise: the gems in your `Gemfile.lock` are the projects you have the most context on. If you depend on `sidekiq`, you have opinions about Sidekiq. That's a better starting point for open-source contribution than scanning all of GitHub for `good-first-issue` tags and hoping one looks interesting.

## Status

Early. v0.1 is a CLI. A Rooibos TUI is planned (see [issue #2](https://github.com/cdhagmann/gem-contribute/issues/2)). This is being built as a workshop project for **[Blue Ridge Ruby 2026](https://blueridgeruby.com)**. Expect rough edges through the conference.

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
gem-contribute issues <gem|all>       List "good first issue" issues for one gem (or all).
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

| Key          | Notes                                                                              |
|--------------|------------------------------------------------------------------------------------|
| `clone_root` | Where `fix` clones forks (`<root>/<owner>/<repo>`). Set via `init` or `config set`. No default — `fix` errors if unset. |

## Design

See [`docs/design.md`](docs/design.md) for the architecture overview and [`docs/adr/`](docs/adr/) for individual decisions with their reasoning. The short version: scan first, auth lazily, abstract the source host so GitHub isn't the only option forever, render the data as the maintainer wrote it (don't normalize labels, don't summarize CONTRIBUTING).

## Contributing

The tool is *for* finding contributable projects, so it had better be one. See [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues tagged `good first issue` are real and reviewed.

If you're attending Blue Ridge Ruby 2026 and arrived here from the workshop, see [`docs/workshop.md`](docs/workshop.md) for the exercises.

## Disclosure

Built with substantial assistance from Claude (Anthropic). Architecture, design decisions, and code review are mine; a fair amount of the typing isn't. Decisions are documented in `docs/adr/` partly so the reasoning is auditable independent of who or what produced the diff.

## License

MIT.
