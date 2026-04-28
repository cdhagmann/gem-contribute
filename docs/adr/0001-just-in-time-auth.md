# ADR 0001: Just-in-time authentication

**Status:** Accepted
**Date:** 2026-04-27

## Context

`gem-contribute` reads a Gemfile.lock, resolves source URLs, and queries hosts (GitHub primarily) for issues. Issue browsing is read-only and works against public repos with no auth. Forking, cloning, and branching require auth.

Two reasonable architectures:

1. **Auth at startup.** Prompt for OAuth on first run; everything is authenticated thereafter.
2. **Auth just-in-time.** Run anonymously until the user takes an action that requires auth, then prompt.

## Decision

Auth lazily, per host, on first action that requires it.

## Reasoning

The lockfile-scanning and issue-browsing parts of the tool are useful without auth. A user who runs `gem-contribute` for the first time sees:

> 47 gems · 44 on github.com · 2 on gitlab.com · 1 unknown source
> Hit Enter on a gem to browse its issues.

That's value before the auth prompt. The prompt becomes "you want to fork this — let's connect your GitHub" instead of "before doing anything, please authorize this app."

Per-host matters because the tool is designed to grow GitLab and Codeberg adapters. Asking for GitHub auth on launch when the user only ever interacts with GitLab gems would be backwards.

## Alternatives considered

- **Auth at startup.** Simpler to implement; worse UX. Rejected.
- **PAT-only (no OAuth).** Lower setup burden for the maintainer; higher for the user. See ADR-0004.

## Consequences

- The host adapter must distinguish public-API methods from auth-required ones at the type level (`AuthRequired` exception).
- The TUI needs an auth-prompt overlay that can fire mid-session.
- The token cache is keyed by host, not global.
- Tests must cover both authenticated and anonymous paths for every adapter method.

## Implementation note (post-ADR-0008)

With Rooibos as the TUI framework, the JIT auth flow is naturally expressed as a state machine in `Update`: an action that requires auth dispatches a `Command.http` against an adapter method that returns `AuthRequired`; the resulting message transitions the model into an auth-pending state; device-flow polling runs as a sequence of `Command.http` + `Command.wait` cycles; on success the model retries the original action. This is cleaner and more testable than the imperative interrupt-and-resume pattern that would have been required with bare `ratatui_ruby`. The decision in this ADR is unchanged; only the implementation gets nicer.
