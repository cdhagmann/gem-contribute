---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    padding: 60px;
  }
  h1 { font-size: 2.4em; }
  h2 { font-size: 1.8em; }
  code, pre { font-family: "JetBrains Mono", Menlo, monospace; }
  pre { font-size: 0.85em; }
  .small { font-size: 0.7em; color: #666; }
  .big { font-size: 1.6em; }
  blockquote {
    font-size: 1.5em;
    border-left: 4px solid #cc0000;
    padding-left: 24px;
    margin-left: 0;
  }
  section.title h1 { font-size: 3em; }
  section.title { text-align: center; padding-top: 20%; }
---

<!-- _class: title -->

# gem-contribute

## Building what you cannot find

Chris Hagmann · Blue Ridge Ruby 2026

---

<!-- Speaker note: Hold for 2 beats. Let the room read it.
     This is the entire problem in one sentence. -->

> I have opinions about Sidekiq.
> I don't contribute to Sidekiq.

---

## Where do I even start?

- `gh search issues "good first issue"` → no project context
- "Help wanted on Ruby gems" → not a search that exists
- Trawling GitHub trending → overwhelming and irrelevant

<br>

The thing I couldn't find:

> A tool that maps **"gems I depend on"** → **"issues I could fix today."**

---

## The insight was already on disk

```
$ wc -l Gemfile.lock
     232 Gemfile.lock
```

<br>

Your `Gemfile.lock` is already curated.

- ~200 maintainers you've **already bet on**
- The OSS code you have **the most context on**
- A vote of confidence with versions attached

<br>

Start *there*, not on GitHub.

---

## So I built it

```sh
$ gem-contribute scan
Scanning Gemfile.lock (232 gems)...
232 gems · 228 on github.com · 1 on gitlab.com · 3 unknown source

Top contributable projects (by open `good first issue` count):
  sorbet-runtime    50  github.com/sorbet/sorbet
  rspec-openapi      5  github.com/exoego/rspec-openapi
  packwerk           4  github.com/Shopify/packwerk
  rubocop            4  github.com/rubocop/rubocop
  ...
  gem-contribute     1  github.com/cdhagmann/gem-contribute
```

<!-- Speaker note: Point at the last line. The tool injects itself. -->

---

## Drill in

```sh
$ gem-contribute issues rubocop
rubocop — 4 open "good first issue" issues

  #14102  Allow Lint/Void to be configured per-method
          https://github.com/rubocop/rubocop/issues/14102

  #13871  Improve cop documentation for ...
          https://github.com/rubocop/rubocop/issues/13871

  ...

To contribute: gem-contribute fix rubocop/<issue#>
```

---

## Fix it

```sh
$ gem-contribute fix rubocop/14102
Forking rubocop/rubocop → cdhagmann/rubocop...
Cloning into ~/code/oss/rubocop/rubocop...
Forked, cloned, and branched.
  path:     ~/code/oss/rubocop/rubocop
  branch:   gem-contribute/issue-14102
  upstream: github.com/rubocop/rubocop
  fork:     github.com/cdhagmann/rubocop

Next: cd ~/code/oss/rubocop/rubocop && make your changes,
      then `gem-contribute submit`.
```

---

## Submit it

```sh
$ gem-contribute submit
Pushing gem-contribute/issue-14102 to origin...
Opened browser to:
  https://github.com/rubocop/rubocop/compare/cdhagmann:gem-contribute/issue-14102
  ?expand=1&title=Fix+%2314102%3A+Allow+Lint%2FVoid+...&body=Closes+%2314102.
```

<br>

Browser opens. PR is pre-filled. Review. Click **Create**.

---

## Audience demo

If you have a laptop:

```sh
gem install gem-contribute
gem-contribute auth login
gem-contribute fix gem-contribute/5
```

<br>

Edit `KICKED_THE_TIRES.yml`. Add yourself.

```sh
gem-contribute submit
```

<br>

I'll watch the auto-merge fire on screen behind me.

<!-- Speaker note: Pull up the Actions tab on the second monitor.
     If wifi is bad, fall back to recorded video. -->

---

## What I deliberately did NOT do

- **Don't normalize labels.** "easy" might mean "easy for a beginner" or "easy once you understand the architecture." The maintainer chose the word.
- **Don't summarize CONTRIBUTING.md.** Reading the contributing guide *is* contributor onboarding.
- **Don't ship a Bundler plugin.** Standalone gem; works on every project without changing their Gemfile.

<br>

<span class="small">Decisions are documented as ADRs in `docs/adr/`. The reasoning outlives the code.</span>

---

## What's next

| Now | Soon |
|---|---|
| CLI works end-to-end | Rooibos TUI (`gem-contribute` no args) |
| GitHub only | GitLab + others (host adapter pluggable) |
| Single canonical label | `preferred_labels` config |
| 1 contributor on the world map | Many |

<br>

```sh
gem install gem-contribute
```

<span class="small">Three good first issues open. Sandbox issue #5 always available.</span>

---

<!-- _class: title -->

## Thanks

`gem install gem-contribute`
**cdhagmann.com/gem-contribute**

<br>

<span class="small">
Built with substantial assistance from Claude (Anthropic).<br>
Architecture and decisions are mine; a fair amount of the typing isn't.<br>
Disclosed in the README; the ADRs are auditable independent of who or what produced the diff.
</span>
