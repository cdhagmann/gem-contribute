# ADR 0007: Show CONTRIBUTING; don't parse it

**Status:** Accepted
**Date:** 2026-04-27

## Context

When a user is about to fork-and-branch on an issue, it would be useful to surface the project's contribution guidelines. CONTRIBUTING.md is the canonical location, with `.github/CONTRIBUTING.md` and `docs/CONTRIBUTING.md` as common alternates. GitHub's community profile API (`/repos/:owner/:repo/community/profile`) returns the path of whichever exists.

Two ways to use that file:

1. **Display it.** Show the markdown in a pane. User reads it.
2. **Parse it.** Programmatically extract things like "this project uses these labels," "PRs require DCO sign-off," "tests are required," etc.

## Decision

Display, don't parse.

## Reasoning

Parsing CONTRIBUTING.md across thousands of projects is heuristic work. The files are written in prose by humans for humans, with no schema, no consistent terminology, and no obligation to be parseable. Any extraction layer we ship will be wrong some of the time, in subtle ways, on the projects that matter most (the ones with non-standard but important guidelines).

The cost of being wrong here is high. A user who relies on a misparsed CONTRIBUTING and opens a PR that violates an unwritten convention is in a worse position than a user who reads the file themselves and notices the convention.

There's also a softer reason: reading a project's CONTRIBUTING is part of the contribution itself. It's where you learn the project's voice and norms. Hiding that behind extracted bullet points makes the user a worse contributor over time.

The pragmatic version of "display, don't parse" is good enough: render the markdown nicely (headings, lists, code blocks, links), let the user scroll through it, surface a "you haven't read this yet" indicator on the issue detail screen if they try to fork before opening CONTRIBUTING.

## Alternatives considered

- **Parse for known signals.** Look for backticked label names, URL patterns, common phrases like "sign your commits." Possibly v0.3+; not v1. The risk is that we introduce the parsing infrastructure and then everyone wants to extend it, and we end up with a half-built NLP system in a TUI tool.
- **AI-summarize the CONTRIBUTING.** Out of scope, out of character for this project, and an additional dependency we don't want.
- **Don't surface CONTRIBUTING at all.** Surfacing it is one of the tool's quietly-best features. Rejected.

## Consequences

- We need a markdown renderer that works in a Ratatui pane. There are a few; pick the smallest one that handles headings, lists, code blocks, and links.
- The "have you read CONTRIBUTING" indicator is local UI state. We track whether the user has opened the CONTRIBUTING pane for the current project in this session. We don't persist this — re-prompting on a fresh run is fine.
- If someone wants parsing, they can build it as a separate gem that consumes our output.
