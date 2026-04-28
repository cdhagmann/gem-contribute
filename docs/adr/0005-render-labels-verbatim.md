# ADR 0005: Render labels verbatim

**Status:** Accepted
**Date:** 2026-04-27

## Context

GitHub label conventions vary across projects. Common variants meaning roughly "this is approachable for new contributors":

- `good first issue`
- `good-first-issue`
- `Good First Issue`
- `beginner`
- `easy`
- `help wanted`
- `up-for-grabs`
- `low-hanging fruit`
- (none — the maintainer doesn't tag at all)

We could normalize these to a canonical set ("Beginner-friendly", "Help wanted", etc.) for cleaner UI. We could also leave them exactly as the maintainer wrote them.

## Decision

Render labels exactly as the maintainer wrote them, with the colors GitHub returns. Allow the user to specify a `preferred_labels` list in config that controls highlighting and sort order, but don't rewrite anything.

## Reasoning

Two reasons, one technical and one social.

**Technical:** Normalization is a heuristic. Heuristics are wrong sometimes. When the heuristic gets it wrong — say, a project uses `easy` to mean "easy to fix once you understand the architecture" rather than "easy for a beginner" — normalization loses information the maintainer encoded deliberately. The user is better served by the raw label and the exercise of reading it in context.

**Social:** The act of reading a project's labels *is* contributor onboarding. It's how you start to understand a project's voice, its triage workflow, its expectations. A tool that smooths that over removes a learning surface. We are not in the business of removing learning surfaces from people who are explicitly here to learn open-source contribution.

The `preferred_labels` config is the escape valve for users who want their own ranking. It's user-controlled, not algorithmic. Different.

## Alternatives considered

- **Normalize to a fixed taxonomy.** Loses information; opinionated in a way the tool shouldn't be. Rejected.
- **Show normalized labels alongside raw ones.** Visual clutter. The thing we're optimizing for (fast scanning of issue lists) gets worse, not better. Rejected.
- **Let the user define normalizations in config.** This is approximately what `preferred_labels` does without claiming to normalize. Accepted in that form.

## Consequences

- Issue list rendering must preserve label colors from the GitHub API.
- `preferred_labels` matches case-insensitively against the raw label text. Hyphens and spaces are treated as equivalent. That's the only normalization we do, and it's only for the user's own preference matching.
- Users who want a different taxonomy can edit their config. We don't ship one.
