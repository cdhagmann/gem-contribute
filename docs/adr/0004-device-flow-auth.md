# ADR 0004: OAuth Device Flow, not Personal Access Tokens

**Status:** Accepted
**Date:** 2026-04-27

## Context

To fork repos and clone forks on a user's behalf, `gem-contribute` needs an authenticated GitHub session. Two practical options:

1. **Personal Access Token (PAT).** User generates a token in GitHub settings, pastes it into the tool.
2. **OAuth Device Authorization Grant ("device flow").** Tool displays a code; user opens browser, signs in, enters code; tool polls for the token. Same UX as `gh auth login`.

## Decision

Device flow.

## Reasoning

UX. The PAT flow is genuinely awful: navigate to settings, click through several screens, choose scopes you don't fully understand, name the token, copy it within the one-time-display window, paste it into the tool, hope you didn't fat-finger it. Half the people in the workshop room will lose three minutes to this and one will lose ten.

Device flow is approximately: type `gem-contribute`, click a button in your already-open browser, done. About 30 seconds, no copy-paste, no leaked tokens in shell history.

Critically for an open-source CLI: device flow needs only a `client_id`, no client secret. We can ship the client ID as a public constant in the source code. There is no secret to protect. This is by design — GitHub's docs explicitly support this pattern.

## Alternatives considered

- **PAT only.** Rejected for UX reasons above.
- **Both, with PAT as fallback.** Reasonable; deferred to v0.2 if anyone asks. The ground-truth use case (corporate networks where the device-flow polling fails for some reason) is real but rare.
- **GitHub App instead of OAuth App.** GitHub Apps are more powerful and more correct in the long run, but they require token refresh logic and a higher prep burden. Defer until there's a reason to switch.

## Consequences

- The maintainer (initially: Chris) registers an OAuth App on a personal GitHub account and copies the client ID into the source. When the tool is donated to a more permanent home, the OAuth App migrates with it.
- Rate limits: 50 `user_code` submissions per hour across all users of this client ID. With workshop-scale usage (~12 attendees authing once each), this is fine. If the tool ever gets popular enough to brush this limit, we register additional OAuth Apps or switch to a GitHub App.
- We must implement: device code request, polling with `slow_down` backoff, token storage at `~/.config/gem-contribute/auth.json` (mode 0600), and graceful handling of the 15-minute device-code expiry.
- Scope is `public_repo` only at v1. Adding `repo` (for private repos) would be a future ADR.
