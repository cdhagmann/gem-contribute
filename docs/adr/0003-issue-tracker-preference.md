# ADR 0003: Prefer `bug_tracker_uri` over `source_code_uri`

**Status:** Accepted
**Date:** 2026-04-27

## Context

The RubyGems v1 API returns metadata for a gem including several URIs from the gemspec: `homepage_uri`, `source_code_uri`, `bug_tracker_uri`, `documentation_uri`, `changelog_uri`, etc. Most of the time `source_code_uri` and `bug_tracker_uri` point to the same GitHub repo. Sometimes they don't.

A small but real fraction of gems host code on one platform and issues on another (commonly: code on GitHub Enterprise, issues on a public GitHub repo). For those gems, we want issues, not code.

## Decision

Prefer `bug_tracker_uri`. Fall back to `source_code_uri`. Fall back to `homepage_uri` if it points at a recognized host. Otherwise mark the gem as `:unknown` source.

## Reasoning

The tool is named `gem-contribute` and the primary action is "browse and respond to issues." The bug tracker is the canonical location of issues. If a maintainer set both URIs, they did so deliberately, and we should respect their choice.

For gems that only set `source_code_uri`, the fallback is correct because most of the time the source repo *is* the issue tracker.

The `homepage_uri` fallback is a hail-mary for gems whose maintainer never set the more specific URIs but happened to put a GitHub URL in the homepage field. In practice this catches a few percent of older gems.

## Alternatives considered

- **Always use `source_code_uri`.** Loses the rare-but-real case where issues live elsewhere. Rejected.
- **Only use `bug_tracker_uri`, with no fallback.** Excludes too many gems. Rejected.
- **Try them all and let the user pick.** Workable, but the right answer is almost always the first non-nil one in our preference order. Don't make the user choose.

## Consequences

- A small number of gems will have `bug_tracker_uri` pointing at something that isn't a host we have an adapter for (private Bugzilla, mailing list, etc.). Those gems become `:unknown` and aren't actionable. We surface them anyway because seeing "this gem has no contributable issue tracker" is itself useful information.
- We may want a `--prefer-source` flag eventually for users who specifically want code-level contributions over issue triage. Not in v1.
