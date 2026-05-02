## Summary

<!-- One or two sentences. What changes, and why. The "why" is the part that's hard to recover later. -->

## Review preference

Lowering friction is the whole point of this project. Pick whichever fits — defaults to the first if you don't tick anything.

- [ ] **Ship it.** Review for correctness, tests, and design fit. Skip style nits unless they're load-bearing.
- [ ] **Full review, please.** Feedback on style, naming, idioms, and alternative designs welcome. I want the deep version, whether to learn the Ruby way or to stress-test a pattern I'm trying.

## Working agreement check

- [ ] Single concern (multi-concern PRs get bounced — see [CLAUDE.md](../CLAUDE.md))
- [ ] ADRs touched: <!-- list ADR numbers, or "none" -->
- [ ] `bin/rubocop` and `bin/rspec` pass locally
- [ ] New behavior has a test; bug fix has a regression test
- [ ] Async work goes through Rooibos Commands (no direct threads / `Async` / synchronous shellouts)

## Notes for reviewer

<!-- Tradeoffs, open questions, follow-ups — anything not obvious from the diff. -->
