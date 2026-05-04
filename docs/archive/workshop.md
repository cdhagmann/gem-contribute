# Workshop — Blue Ridge Ruby 2026

90-minute workshop, then open hacking.

## Premise

You depend on dozens of gems. Some of those projects need help. This tool finds the overlap. We built v0.1; you're going to make it better.

## Before the workshop

- Ruby 3.2+
- A GitHub account
- 5 minutes to clone and `bundle install`

```
git clone https://github.com/cdhagmann/gem-contribute
cd gem-contribute
bundle install
bin/gem-contribute
```

If `bundle install` complains about `ratatui_ruby` building a native extension, you need a Rust toolchain. On macOS: `xcode-select --install` is usually enough. On Linux: `sudo apt install build-essential` plus `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.

If you can't get the build working, pair with someone who can. The workshop scales fine with two-person teams.

## Arc

**0:00 — 0:15 · Demo and tour**

I run the tool against a real Gemfile.lock. We walk through what each pane does, then through the architecture (`docs/design.md`).

**0:15 — 0:30 · Architecture overview**

The four-stage pipeline: parse → resolve → adapt → render. Where things are, why they're separate, what an adapter looks like. The point is to give you enough mental model to know where your changes go.

**0:30 — 1:00 · Exercise: build a feature**

Pick one issue from `https://github.com/cdhagmann/gem-contribute/issues?q=label:workshop`. They're scoped to be doable in 30 minutes by someone who's never touched the codebase. Examples:

- Add a "rate limit remaining" indicator to the status bar
- Support `bug_tracker_uri` fallback to `homepage_uri` for older gems
- Add a `r` keybinding that refreshes the current view
- Show CONTRIBUTING.md preview in the issue detail pane

If you finish, pick another. If you don't finish, that's fine — open a PR with what you have and we'll land it together.

**1:00 — 1:30 · Show and tell, plus the contribute-the-tool flow**

Anyone who wants to demo their change does. Then I run `gem-contribute` against this repo's own Gemfile.lock and we use the tool to find issues to contribute to *in our actual dependencies*.

**1:30 — end of day · Open hacking**

Stay if you want. Work on this tool, or — better — use it on a project you depend on. The goal of the rest of the day is at least one merged PR per attendee, somewhere. Doesn't have to be here.

## Ground rules

- Ask anyone, including me, anything.
- "I don't know" is a fine answer to anything; we figure it out together.
- If you're stuck on setup for more than 15 minutes, raise a hand.
- This is a hack day. Imperfect contributions are the point.
