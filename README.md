# gem-contribute

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
gem-contribute scan [path]            Summarize the contributable surface of a Gemfile.lock.
gem-contribute issues <gem|all>       List "good first issue" issues for one gem (or all).
gem-contribute auth login             Authenticate with GitHub via OAuth device flow.
gem-contribute fix <gem>/<issue#>     Fork the gem's repo, clone the fork, branch from main.
gem-contribute submit                 Push the branch and open a pre-filled PR in the browser.
gem-contribute config set <key> <val> Persist user preferences (e.g. clone_root).
```

A typical session:

```sh
$ gem-contribute auth login              # one-time; uses GitHub device flow
$ gem-contribute scan                    # see what's worth contributing to
$ gem-contribute issues rubocop          # drill into one project's issues
$ gem-contribute fix rubocop/12345       # fork, clone, branch
$ cd ~/code/oss/rubocop/rubocop          # (or wherever clone_root points)
# ... make your change, commit ...
$ gem-contribute submit                  # push + open the PR compare page in your browser
```

The `auth login` step opens GitHub's device-flow page in your browser and copies the one-time code to your clipboard — same UX as `gh auth login`, no token paste, no client secret. Tokens cache at `~/.config/gem-contribute/auth.json` (mode 0600).

## Configuration

User config lives at `~/.config/gem-contribute/config.yml`. Manage it with `gem-contribute config`:

```sh
gem-contribute config set clone_root ~/Projects/oss
gem-contribute config list
```

| Key          | Default      | Notes                                            |
|--------------|--------------|--------------------------------------------------|
| `clone_root` | `~/code/oss` | Where `fix` clones forks (`<root>/<owner>/<repo>`). |

## Design

See [`docs/design.md`](docs/design.md) for the architecture overview and [`docs/adr/`](docs/adr/) for individual decisions with their reasoning. The short version: scan first, auth lazily, abstract the source host so GitHub isn't the only option forever, render the data as the maintainer wrote it (don't normalize labels, don't summarize CONTRIBUTING).

## Contributing

The tool is *for* finding contributable projects, so it had better be one. See [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues tagged `good first issue` are real and reviewed.

If you're attending Blue Ridge Ruby 2026 and arrived here from the workshop, see [`docs/workshop.md`](docs/workshop.md) for the exercises.

## Disclosure

Built with substantial assistance from Claude (Anthropic). Architecture, design decisions, and code review are mine; a fair amount of the typing isn't. Decisions are documented in `docs/adr/` partly so the reasoning is auditable independent of who or what produced the diff.

## License

MIT.
