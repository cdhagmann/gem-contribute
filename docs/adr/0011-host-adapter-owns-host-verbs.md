# ADR 0011: HostAdapter owns host verbs; Operations compose them; CLI verbs compose Operations

**Status:** Accepted
**Date:** 2026-05-02

## Context

`CLI::Fork` (and, by delegation, `CLI::Fix`) currently fuses four concerns into one class:

1. CLI shell — argv parsing, usage errors, summary, post-clone hooks.
2. Host-API ceremony — call `adapter.fork`, poll `adapter.fork_ready?` in a 12×5s loop, branch on `adapter.already_forked?`.
3. VCS work on the local filesystem — `git clone` into `<root>/<owner>/<repo>`, reuse if `.git` exists, add an `upstream` remote.
4. Host-specific URL templating — `https://github.com/<owner>/<repo>.git` is hardcoded at [fork.rb:51](../../lib/gem_contribute/cli/fork.rb).

ADR-0001 (and the design doc) already commit to GitLab and Codeberg adapters as a near-term goal. The hardcoded `github.com` literal and the GitHub-shaped readiness loop both block that. A previous refactor (commit 3d53ffc, "dissolve ForkClone into Fork") pulled in the opposite direction: it merged the bootstrap primitive into the CLI verb. That made the multi-host port harder, not easier.

Two reasonable shapes for splitting:

1. **Wider adapter, thicker CLI verbs.** Push everything host-specific into `HostAdapter` (`fork`, `comment`, `pull_request_url`, `clone_url`); CLI verbs compose adapter calls and `Git` calls directly.
2. **Adapter + Operations layer.** Same wider adapter, plus a thin layer of host-agnostic primitives (`Operations::Fork`, `Operations::Clone`) that compose `HostAdapter` and `Git`. CLI verbs compose Operations.

## Decision

Adopt shape 2: a three-layer split.

- **`HostAdapter`** owns *every* host-API verb. Concrete methods: `fork`, `comment`, `pull_request_url`, `clone_url`, plus the existing reads (`issues`, `issue`, `issue_comments`, `community_profile`, `file_contents`, `search_issues`) and identity (`viewer_login`).
- **`Operations::Fork`** and **`Operations::Clone`** are the bootstrap primitives. They depend on a `HostAdapter` and (for Clone) a `Git`. They produce the local clone path the CLI verbs need.
- **`CLI::Fork`** and **`CLI::Fix`** parse argv, resolve a `Project`, compose the Operations primitives, print summaries, and run post-clone hooks. Nothing else.

Three sub-decisions that shape the adapter's surface:

- **`fork(project)` is idempotent and blocks until ready.** The 12×5s polling loop moves *into* the GitHub adapter. Callers ask for "fork this and give me a working clone URL"; the adapter decides whether that needs a poll, a single request, or something else. `fork_ready?` and `already_forked?` become private details.
- **PR creation stays browser-based; the adapter exposes `pull_request_url(...)`.** Today `submit` deliberately opens a pre-filled compare page so the user reviews PR text before submitting. We keep that UX. The adapter's job is to construct the host-correct compare URL; GitLab returns a `merge_requests/new` URL, GitHub returns a `compare` URL, etc.
- **`clone_url(project)` replaces the hardcoded `https://github.com/...` literal.** The Operations layer asks the adapter; the adapter knows its own host.

## Reasoning

The data layer / TUI layer split in [`docs/design.md`](../design.md) is built around adapters being swappable. That bet pays off only if "swap in a GitLab adapter" really is a weekend project. Today it isn't — a GitLab port would have to fork (no pun intended) the GitHub-shaped readiness loop, the hardcoded clone URL, and the same-shape compare URL out of `CLI::Fork` and `CLI::Submit`. With this split, a GitLab port is: implement `HostAdapter#fork` (likely no poll), `#clone_url` (return `https://gitlab.com/...`), `#pull_request_url` (return the GitLab MR URL form), `#comment`. Operations and CLI don't change.

The Operations layer (rather than a fatter CLI) earns its keep because two things in the bootstrap aren't host-API and aren't raw git either: the *clone-or-reuse* policy (skip clone if `.git` exists) and the *upstream remote* policy (always add `upstream` pointing at the canonical repo's `clone_url`). Those are gem-contribute conventions, not git primitives, and they're shared between `fix` and `fork`. Putting them in their own class makes them testable in isolation and keeps the CLI verbs honestly thin.

This direction supersedes the merge in 3d53ffc. That commit was right that `ForkClone` and `Fork` had drifted into near-duplicates; it was wrong that the resolution was to dissolve the primitive into the verb. The correct resolution was to *re-extract* the primitive at a sharper boundary — which is what this ADR does.

## Alternatives considered

- **Wider adapter, no Operations layer (shape 1 above).** Simpler — one fewer namespace. Rejected because the clone-or-reuse and upstream-remote policies don't belong on `HostAdapter` (they're not host-API) or on `Git` (they're gem-contribute policy on top of git). Without an Operations layer they leak into CLI verbs, where they get duplicated between `fork` and `fix`.
- **Move PR creation to API-based (`adapter.create_pull_request`).** Rejected — the deliberate UX in [`submit.rb`](../../lib/gem_contribute/cli/submit.rb) is that the user reviews PR text in the browser before submitting. That's a v1 product decision, not an artifact of laziness.
- **Keep `fork_ready?` / `already_forked?` on the public adapter interface.** Rejected as the default. They're GitHub-shaped (the 202-then-poll dance is a GitHub artifact). Hiding them behind an idempotent, blocking `fork` lets each host implement readiness however it actually works. We can re-expose them later if a real caller needs them.

## Consequences

- `HostAdapter` grows: `fork` semantics tighten (idempotent, blocking), `comment` replaces `comment_on_issue`, new methods `pull_request_url` and `clone_url`. `fork_ready?` and `already_forked?` come off the public interface.
- New namespace `GemContribute::Operations::` housing `Fork` and `Clone`.
- `CLI::Fork` and `CLI::Fix` shrink. The `ensure_fork` / `wait_until_ready` / `clone_into_root` privates move out.
- The hardcoded `github.com` URL literal at [fork.rb:51](../../lib/gem_contribute/cli/fork.rb) goes away.
- [`docs/design.md`](../design.md) needs the `HostAdapter` signature snippet (currently shows the old shape) and a paragraph on the Operations layer.
- Tests: `Operations::Fork` and `Operations::Clone` get unit specs; the existing `CLI::Fork` and `CLI::Fix` specs shrink (less to assert in the verb itself, more in the primitives).
- The "no orchestrator class" rule in CLAUDE.md is unchanged: Operations primitives are not orchestrators. They're single-step compositions of an adapter call and (sometimes) a git call. The TUI's `fix` flow remains a state machine in `Update`.
