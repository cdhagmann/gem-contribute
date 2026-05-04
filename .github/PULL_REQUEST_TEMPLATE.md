## Summary

<!-- One or two sentences. What changes, and why. The "why" is the part that's hard to recover later. -->

## Linked issue / ADR

<!--
Issue # this closes (or "none — drive-by fix").
For non-trivial changes: which ADR(s) does this touch? If you skipped that step, write "no ADR" plus a one-line reason.
-->

## Working agreement

- [ ] Single concern (multi-concern PRs get bounced — see [CLAUDE.md](../CLAUDE.md))
- [ ] `bin/rubocop` and `bin/rspec` pass locally
- [ ] New behavior has a test; bug fix has a regression test
- [ ] Async work goes through Rooibos Commands (no direct threads / `Async` / synchronous shellouts)

## Test plan

<!--
How was this verified? Spec output, manual smoke, screenshots — whatever applies.
"`bin/rspec` passes" is the floor, not a test plan.
-->

## Notes for reviewer

<!-- Tradeoffs, open questions, follow-ups — anything not obvious from the diff. Delete the section if there's nothing to add. -->
