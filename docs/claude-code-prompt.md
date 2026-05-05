# Initial prompt for Claude Code

Paste the following as your first message in Claude Code (in the `gem-contribute` directory).

---

We're building `gem-contribute` together for a workshop at Blue Ridge Ruby on April 30 – May 1, 2026.

Before doing anything, read these in order:

1. `CLAUDE.md` — the working agreement
2. `README.md` — what the project is
3. `docs/design.md` — the architecture
4. `docs/adr/` — every ADR; they constrain implementation choices
5. `docs/archive/prep-plan.md` — the staged plan I want you to execute

Then check out the current state of the repo. Right now there's no Ruby code yet — just docs. The very first thing you do is generate the gem skeleton (gemspec, Gemfile, lib/, bin/, spec/) following standard Bundler conventions for a CLI gem with a native-extension dependency. Use the gem name, version, and license from the README. Don't add any runtime dependencies that aren't justified by the design doc; we'll add `rooibos` and `ratatui_ruby` in Stage 3.

Then start Stage 1 from `docs/archive/prep-plan.md`.

Working rules for our collaboration:

- **Stop at every stage boundary** in the prep plan and tell me what you've done. Don't barrel into the next stage. I want to demo and review.
- **Commit at meaningful checkpoints**, not all at once at the end. Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- **Push back on me** if a request contradicts an ADR. Reference the ADR by number. If we change our minds, we update the ADR before writing the conflicting code.
- **When you hit a real architecture question**, surface it instead of picking. The ADR-0008 / Rooibos call is the kind of thing that should have come back to me as a question, not a fait accompli.
- **Don't write workshop issues as actual GitHub issues**, just as markdown files per Stage 4. I'll create them on GitHub myself when the repo is public.
- **Don't register the OAuth App for me.** When Stage 2 needs the client ID, generate a `MAINTAINER.md` with step-by-step instructions for me to do it manually, then pause and wait for me to paste the client ID back.
- **Don't open the demo PR for me.** When Stage 2 says "use the tool to open one real PR," stop there and have me do it. Watching me use my own tool is the test.

Start by reading the docs and confirming the plan. Then go.

---

## Notes on using this prompt

- If Claude Code asks clarifying questions before reading the docs, tell it to read first and then ask.
- If it suggests architecture changes early, fine — but require an ADR update *before* the code change, not after.
- The "stop at every stage boundary" rule is the most important one. Without it, agentic coding sessions tend to overshoot. Reinforce it if needed.
- The 12–20 hour estimate in `archive/prep-plan.md` is honest, not pessimistic. Plan accordingly.
