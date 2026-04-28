---
title: gem-contribute
---

# gem-contribute

Find contributable issues in the gems your project already depends on.

```sh
$ gem install gem-contribute
$ gem-contribute scan
44 gems · 42 on github.com · 2 unknown source

Top contributable projects (by open `good first issue` count):
  rubocop          4  github.com/rubocop/rubocop
  rspec            1  github.com/rspec/rspec
  reline           1  github.com/ruby/reline
  ...
```

The premise: the gems in your `Gemfile.lock` are the projects you have the most context on. If you depend on `sidekiq`, you have opinions about Sidekiq. That's a better starting point for open-source contribution than scanning all of GitHub for `good-first-issue` tags and hoping one looks interesting.

## Quick start

```sh
gem install gem-contribute            # one-time install
gem-contribute auth login             # one-time GitHub OAuth (device flow, no token paste)
gem-contribute scan                   # see what's worth contributing to
gem-contribute issues rubocop         # drill into one project's issues
gem-contribute fix rubocop/12345      # fork, clone, branch (~/code/oss/<owner>/<repo>)
# ... make your change, commit ...
gem-contribute submit                 # push, then open the PR compare page in your browser
```

[Full command reference →](#commands) ・ [Configuration →](#configuration)

## Status

- **v0.1**: a CLI with `scan`, `issues`, `auth`, `fix`, `submit`, and `config`. GitHub-only.
- **Planned**: a Rooibos TUI that does all of the above as a single keyboard-driven session ([issue #2](https://github.com/cdhagmann/gem-contribute/issues/2)).
- **Workshop project**: built for [Blue Ridge Ruby 2026](https://blueridgeruby.com).

## Commands

| Command | What it does |
|---|---|
| `gem-contribute scan [path]` | Parse `Gemfile.lock`, resolve each gem to its source repo, rank GitHub-hosted projects by open `good first issue` count. |
| `gem-contribute issues <gem>` | List the open good-first-issues for one gem with number, title, and URL. |
| `gem-contribute issues all` | Iterate every github.com gem in the lockfile; print only those with open issues. |
| `gem-contribute auth login` | Authenticate with GitHub via OAuth device flow (no token paste, no client secret). |
| `gem-contribute auth status` | Show whether the cached token is still valid. |
| `gem-contribute auth logout` | Drop the cached token. |
| `gem-contribute fix <gem>/<n>` | Fork the gem's repo, clone the fork to `<clone_root>/<owner>/<repo>`, branch from default. Alias: `fork-clone-branch`. |
| `gem-contribute submit` | From inside a clone, push the current branch and open a pre-filled PR compare page in your browser. |
| `gem-contribute config set <k> <v>` | Persist user preferences. |
| `gem-contribute config list` | Show current configuration. |

Global flags: `--refresh` (clear cache), `--version`, `-h/--help`.

## Configuration

User config lives at `~/.config/gem-contribute/config.yml`.

| Key | Default | Notes |
|---|---|---|
| `clone_root` | `~/code/oss` | Where `fix` clones forks (`<root>/<owner>/<repo>`). |

Manage with `gem-contribute config set <key> <value>` rather than editing the YAML by hand.

## Authentication

`gem-contribute auth login` uses GitHub's [OAuth device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow). The flow:

1. The CLI requests a one-time code from GitHub.
2. Your terminal prints the code and (on macOS / Linux) copies it to your clipboard and opens [github.com/login/device](https://github.com/login/device) in your browser.
3. You paste the code, click Authorize.
4. The CLI's pending poll succeeds; the token is cached at `~/.config/gem-contribute/auth.json` (mode 0600).

This is the same UX `gh auth login` uses. The OAuth App is `gem-contribute`, registered to the gem's maintainer; users do not need to register their own.

Tokens are scoped to `public_repo` only — enough to fork, clone, and read public issues, not enough to touch private repositories. If you ever want to revoke, visit [your authorized apps](https://github.com/settings/applications) and remove `gem-contribute`.

## Design

For the architecture overview, see [`design.md`](design.md). For specific decisions and the reasoning behind them, see the [ADRs](adr/).

The short version:

- **Scan first, auth lazily.** No token needed to read public issue counts.
- **Abstract the host.** GitHub today, GitLab and others later. The data model is host-agnostic.
- **Render verbatim.** Don't normalize labels. Don't summarize CONTRIBUTING.md.
- **No threads.** All async work is structured for Rooibos Commands so the TUI can wrap it without rewrites.

## Contributing

The tool is *for* finding contributable projects, so it had better be one. See [`CONTRIBUTING.md`](https://github.com/cdhagmann/gem-contribute/blob/main/CONTRIBUTING.md) and [open issues tagged `good first issue`](https://github.com/cdhagmann/gem-contribute/issues?q=is%3Aopen+label%3A%22good+first+issue%22).

If you're attending Blue Ridge Ruby 2026 and arrived here from the workshop, see [`workshop.md`](workshop.md) for the exercises.

## License

MIT. See [LICENSE](https://github.com/cdhagmann/gem-contribute/blob/main/LICENSE).
