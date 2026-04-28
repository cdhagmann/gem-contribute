# Contributing

Thanks for considering a contribution. This project is *about* lowering the friction to open-source contribution, so we try to walk our talk.

## Quick start

```
git clone https://github.com/cdhagmann/gem-contribute
cd gem-contribute
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

## What we'd push back on

- Label normalization (see [ADR-0005](docs/adr/0005-render-labels-verbatim.md))
- Parsing CONTRIBUTING.md for structured data (see [ADR-0007](docs/adr/0007-display-contributing-verbatim.md))
- AI-anything that summarizes, suggests, or rewrites maintainer-authored content
- Bundler plugin packaging (see [ADR-0006](docs/adr/0006-standalone-gem-not-plugin.md)) — we'll consider it later, just not now

If you have a strong case for any of the above, open an issue first and let's talk before you write code.

## PR expectations

- Run `bin/rubocop` and `bin/rspec` before pushing
- Write a clear commit message; the PR description should explain *why*, not just *what*
- New behavior gets a test
- New decisions of any consequence get an ADR. They're short — see existing ones for the format

## Code of Conduct

Be kind. Assume good faith. The Ruby community deserves both. Specific incidents go to chris@example.com (placeholder — TODO: update before merging this).

## AI assistance

This project was built with significant AI assistance and we're not hiding that. If you use AI to help write a contribution, that's fine; what's not fine is shipping code you don't understand. The bar for review is the same regardless of how the code was authored: you can explain why every line is there, and you can defend the design choices.
