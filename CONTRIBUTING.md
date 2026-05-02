# Contributing

Thanks for considering a contribution. This project is *about* lowering the friction to open-source contribution, so we try to walk our talk.

## Quick start

```
gem install gem-contribute
gem-contribute auth login
gem-contribute fix gem-contribute/issue-5
bundle install
bin/rspec               # tests should pass on a clean checkout
bin/gem-contribute      # tool should run against this repo's own Gemfile.lock
```

## What we welcome

- Bug fixes, with a regression test where reasonable
- New host adapters (GitLab, Codeberg, sourcehut)
- Better error messages — there's no such thing as too clear here
- Documentation improvements, including in `docs/adr/` if you spot reasoning that's stale
- Performance improvements with before/after numbers
- Accessibility improvements to the TUI (color contrast, keyboard-only flows, screen-reader compatibility)


## PR expectations

- Run `bin/rubocop` and `bin/rspec` before pushing
- Write a clear commit message; the PR description should explain *why*, not just *what*
- New behavior gets a test
- New decisions of any consequence get an ADR. They're short — see existing ones for the format

## Code of Conduct

Be kind. Assume good faith. The Ruby community deserves both. The full text — adapted from [Contributor Covenant 3.0](https://www.contributor-covenant.org/version/3/0/) — lives in [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Specific incidents go to gem.contribute@cdhagmann.com.

## AI assistance

This project was built with significant AI assistance and we're not hiding that. If you use AI to help write a contribution, that's fine; what's not fine is shipping code you don't understand. The bar for review is the same regardless of how the code was authored: you can explain why every line is there, and you can defend the design choices.
