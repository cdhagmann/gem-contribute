# Design

This document describes the architecture of `gem-contribute` — what the pieces are, how they fit together, and why. It's the document you'd read before making a non-trivial change. For the *reasoning* behind specific choices, see [`adr/`](adr/).

## Goal

Help a Ruby developer contribute to the open-source projects they already depend on, with the lowest possible friction between "I noticed an issue" and "I have a working branch."

That's the only goal. It's worth restating because it disqualifies a lot of adjacent ideas: this is not a general issue browser, not a PR review tool, not a "discover new gems" tool, not a project management tool. The lockfile is the scope.

## The two halves

`gem-contribute` has a clean split between the **data layer** (parsers, resolvers, host adapters, auth) and the **TUI layer** (a Rooibos MVU app). The data layer knows nothing about the UI. The TUI layer talks to the data layer only through Commands and messages.

This split is what makes the offline mode, the test suite, and the future "GitLab adapter weekend project" tractable. Don't violate it.

## Data layer

```
                Gemfile.lock
                     │
                     ▼
            ┌─────────────────┐
            │  LockfileParser │     no network
            └────────┬────────┘
                     ▼
              [Gem, Gem, …]
                     │
                     ▼
            ┌─────────────────┐
            │   Resolver      │     anonymous RubyGems API
            └────────┬────────┘
                     ▼
       [Project(host, owner, repo), …]
                     │
                     ▼
            ┌─────────────────┐
            │   HostAdapter   │     auth checked just-in-time,
            │   (per-host)    │     per-host
            └─────────────────┘
```

Each stage produces values the next stage consumes. No reverse calls.

### `LockfileParser`

Input: a path to `Gemfile.lock`.
Output: a list of `Gem` structs (`name`, `version`, `source` — where `source` is `:rubygems`, `:git`, `:path`, etc.).

Pure parsing, no network. Wraps `Bundler::LockfileParser`. See [ADR-0002](adr/0002-bundler-lockfile-parser.md).

### `Resolver`

Input: a `Gem`.
Output: a `Project` (`host`, `owner`, `repo`, `metadata`) or `nil` if unresolvable.

Hits the RubyGems v1 API anonymously. Prefers `bug_tracker_uri` over `source_code_uri` — see [ADR-0003](adr/0003-issue-tracker-preference.md). Caches under `~/.cache/gem-contribute/`.

The `host` is parsed from the URL: `github.com`, `gitlab.com`, `codeberg.org`, or `:unknown`. Only `github.com` has a working adapter at v0.1.

### `HostAdapter` (interface) and `GitHubAdapter` (implementation)

Input: a `Project` plus, for some methods, an auth token.
Output: issues, CONTRIBUTING content, fork results, host-specific URLs.

```ruby
# Reads — no auth
def issues(project, labels:)
def issue(project, number)
def issue_comments(project, number)
def community_profile(project)
def file_contents(project, path)
def search_issues(query)

# Writes — auth required
def fork(project)                         # idempotent, blocks until ready; → ForkResult
def comment(project, issue:, body:)
def pull_request_url(upstream, head_owner:, head_branch:, title:, body:)

# Identity / URL helpers
def viewer_login                          # auth required
def clone_url(owner, repo)                # pure templating, no network
def repo_url(owner, repo)                 # pure templating, no network
```

`GitHubAdapter` checks for a cached token before any auth-required call. If there's no token, it raises `AuthRequired` with the host name. The TUI catches this through its message machinery and triggers the device flow. See [ADR-0001](adr/0001-just-in-time-auth.md).

`fork` is idempotent and blocking: if the viewer already owns the fork it returns `reused: true` without a POST; otherwise it POSTs and polls the host until the new fork is reachable. Higher layers don't see the polling. PR creation is not an API call — the adapter's `pull_request_url` returns a host-specific compare/MR URL that gets opened in the browser, so the user reviews the PR text before submitting. See [ADR-0011](adr/0011-host-adapter-owns-host-verbs.md).

Adding a new host (GitLab, Codeberg) means writing a new adapter that conforms to the interface — including its own `clone_url` / `repo_url` / `pull_request_url` templates and its own readiness model for `fork`. Operations and CLI don't change.

### `Operations::Fork` and `Operations::Clone`

Two thin primitives sitting between the adapter and the CLI verbs. They're the bootstrap step `fix` and `fork` share:

- `Operations::Fork` calls `adapter.fork(project)` and packages the result with the upstream URL for summary output.
- `Operations::Clone` clones the fork into `<root>/<owner>/<repo>` (reusing an existing clone if one is there) and adds an `upstream` remote pointing at `adapter.clone_url(upstream)`.

The "reuse if `.git` exists" rule and the upstream-remote convention are gem-contribute policy on top of git, not git primitives — that's why they live here rather than in the `Git` wrapper. See [ADR-0011](adr/0011-host-adapter-owns-host-verbs.md).

### `Auth`

Implements the OAuth 2.0 Device Authorization Grant against `github.com`. Stores tokens at `~/.config/gem-contribute/auth.json` (mode 0600). Token cache is keyed by host so multi-host support drops in cleanly.

The OAuth App is registered under the maintainer's account. Client ID is a public constant in source — there is no client secret in device flow, by design. See [ADR-0004](adr/0004-device-flow-auth.md).

## TUI layer

The TUI is a [Rooibos](https://www.rooibos.run/) application. Rooibos provides Model-View-Update (Elm-style) on top of `ratatui_ruby`, plus async Commands and snapshot testing. See [ADR-0008](adr/0008-rooibos-tui-framework.md) for why.

If you've never used Rooibos: read its [Why Rooibos](https://www.rooibos.run/docs/v0.7/doc/getting_started/why_rooibos_md.html) and the Rails-developer guide before changing TUI code. Twenty minutes of orientation saves hours of writing-against-the-grain.

### Mental model

```
   ┌────────┐     message      ┌─────────────────┐
   │  User  │  ───────────────▶│      Update     │
   └────────┘                  │ (model, msg) →  │
       ▲                       │  model | [model,│
       │                       │      command]   │
       │ keys, mouse           └────────┬────────┘
       │                                │
       │                                ├── new model
       │                                │      │
       │                                │      ▼
       │                                │  ┌───────┐
       │                                │  │ View  │ ───── render ──┐
       │                                │  └───────┘                │
       │                                │                           │
       │                                └── command (async)         │
       │                                       │                    │
       │                                       │  http, system,     │
       │                                       │  wait, etc.        │
       │                                       │                    │
       │                                       ▼                    │
       │                                  message (back to Update)  │
       │                                                            │
       └─── terminal ◀──────────────────────────────────────────────┘
```

State lives in one place. Updates flow in one direction. Async work happens via Commands and reports back as messages.

### Fragments

The app is composed as a tree of Rooibos fragments. Each fragment has its own `Init`, `Model`, `View`, and `Update`. Parents compose children using Rooibos's `Router` DSL.

```
GemContribute (parent / router)
├── ProjectList         [project list view]
├── IssueList           [issue list for selected project]
├── IssueDetail         [issue body, labels, action keys]
├── ContributingViewer  [rendered CONTRIBUTING.md]
└── AuthOverlay         [device flow prompt — can fire over any view]
```

The `AuthOverlay` is a fragment that renders on top of whatever view is active when an `:auth_required` message fires. When auth succeeds, the overlay closes and the original action retries.

### Commands

All async work is a Rooibos Command. We never spawn a thread directly.

| What                                    | Command                                         |
|-----------------------------------------|--------------------------------------------------|
| Fetch issues for a project              | `Command.http(:get, url, :got_issues)`           |
| Run device-flow auth poll               | `Command.http(:post, url, :got_token_or_pending)`|
| Wait between auth polls                 | `Command.wait(interval, :poll_again)`            |
| Fork a repo via API                     | `Command.http(:post, url, :forked)`              |
| Clone a forked repo                     | `Command.system("git clone …", :cloned)`         |
| Create a working branch                 | `Command.system("git checkout -b …", :branched)` |
| Open the project in `$EDITOR`           | `Command.open(path)`                             |

Each command produces a message. `Update` handles the message the same way it handles a key press. There is no other concurrency model in this app.

### Messages and pattern matching

`Update` is a single function that pattern-matches on incoming messages. Example shape:

```ruby
Update = -> (message, model) {
  case message
  in :fork_pressed
    [model.with(forking: true), Adapters::GitHub.fork_command(model.current_project)]
  in { type: :http, envelope: :forked, status: 201, body: }
    fork_data = JSON.parse(body, symbolize_names: true)
    clone_cmd = GitWorker.clone_command(fork_data[:clone_url], envelope: :cloned)
    [model.with(fork_data:), clone_cmd]
  in { type: :http, envelope: :forked, status: 401 }
    [model.with(pending_action: :fork_pressed), AuthFlow.start_command]
  in { type: :system, envelope: :cloned, status: 0, stdout: }
    [model.with(local_path: extract_path(stdout)), GitWorker.branch_command(...)]
  # … and so on
  end
}
```

This is the entirety of the control flow. Async work is just messages with envelopes. Errors are messages too. The shape never changes.

## What's deliberately not here

- **Label normalization.** Maintainers chose those labels. Render them. ([ADR-0005](adr/0005-render-labels-verbatim.md))
- **CONTRIBUTING parsing.** Show it. Let the user read it. ([ADR-0007](adr/0007-display-contributing-verbatim.md))
- **PR creation from inside the TUI.** Out of scope; the user writes code in their editor and pushes from their terminal.
- **Private gems / private repos.** Possible later. Out of scope at v0.1; the auth scope is `public_repo` only.
- **Bundler plugin packaging.** Standalone gem at v0.1. ([ADR-0006](adr/0006-standalone-gem-not-plugin.md))
- **A `Worker` module.** Earlier drafts had one. Fork-clone-branch is a sequence of Commands emitted from `Update`; there's no separate orchestrator class. The state machine *is* the orchestrator.
- **Direct threading.** All async work goes through Rooibos Commands. ([ADR-0008](adr/0008-rooibos-tui-framework.md))

## Configuration

`~/.config/gem-contribute/config.yml`:

```yaml
clone_root: ~/code/oss
preferred_labels:
  - good first issue
  - good-first-issue
  - help wanted
  - documentation
hosts:
  github.com:
    enabled: true
```

Everything has a default. The config file is created on first run.

## Caching

| What                           | Where                              | TTL       |
|--------------------------------|------------------------------------|-----------|
| RubyGems source URLs           | `~/.cache/gem-contribute/gems/`    | 7 days    |
| Issue lists                    | `~/.cache/gem-contribute/issues/`  | 5 minutes |
| Community profiles             | `~/.cache/gem-contribute/repos/`   | 1 day     |
| File contents (CONTRIBUTING)   | `~/.cache/gem-contribute/files/`   | 1 day     |

`gem-contribute --refresh` invalidates all caches. Cache misses degrade gracefully — if the network is down and the cache is empty, the TUI shows what it has and reports the gap honestly.

## Testing strategy

ADR-0008 changes this materially from earlier drafts. Because `Update` is a pure function and Rooibos provides snapshot helpers, "test the TUI" goes from impractical to easy.

- **Unit tests** for parsers, resolvers, and adapters. Adapters use VCR cassettes; cassettes are committed.
- **`Update` tests** for every fragment. Pure function in, pure function out. Cover at minimum: every key handler, every command-result message, every error path.
- **View tests** for color and modifier assertions on rendered output. Verify that preferred labels are highlighted, that error states render in red, etc.
- **System tests** for full-flow scenarios. Inject keys, run the app to a quiescent state, snapshot the result. Snapshots are committed.
- **Integration test** against a single live gem (`mailcatcher` is small and friendly) — runs only when `GEM_CONTRIBUTE_INTEGRATION=1` is set. Catches real-world breakage of the adapter.

The Rooibos snapshot tooling normalizes dynamic content (timestamps, paths in `~/code/oss/...`) so snapshot diffs stay legible. Run `UPDATE_SNAPSHOTS=1 rake test` to regenerate baselines.

## Roadmap (non-promises)

**v0.1 (workshop):** GitHub-only, JIT auth, `fix` working, four primary fragments, Rooibos throughout, snapshot tests for the main flows.

**v0.2:** Better empty states, rate-limit display in the status bar, `r` keybinding to refresh the current view, keyboard help overlay (an additional fragment).

**v0.3:** GitLab adapter. The data-layer/TUI-layer split above is the bet that this is a weekend project, not a rewrite.

**Maybe-never:** Codeberg, sourcehut, private repos, PR creation, label normalization, AI-anything, Bundler plugin, RubyGems plugin (a thin lazy-loading shim is the most we'd consider).
