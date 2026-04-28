---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  /* Blue Ridge Ruby 2026 palette, pulled from the conference mark. */
  :root {
    --brr-light:  #a8cce4;  /* pale ridge blue */
    --brr-ruby:   #c2272e;  /* ruby red */
    --brr-blue:   #2872b4;  /* mid blue */
    --brr-navy:   #0e2854;  /* deep navy */
    --brr-cream:  #fbf9f5;  /* slide background */
    --brr-ink:    #16213a;  /* body text */
  }

  section {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", sans-serif;
    background: var(--brr-cream);
    color: var(--brr-ink);
    padding: 60px 80px;
    position: relative;
  }

  /* Subtle bottom accent bar — conference colors in order. */
  section::before {
    content: "";
    position: absolute;
    left: 0; right: 0; bottom: 0;
    height: 6px;
    background: linear-gradient(
      to right,
      var(--brr-light) 0% 25%,
      var(--brr-ruby)  25% 50%,
      var(--brr-blue)  50% 75%,
      var(--brr-navy)  75% 100%
    );
  }

  /* Header strap with the conference identifier on every content slide. */
  section::after {
    content: "Blue Ridge Ruby 2026 · gem-contribute";
    position: absolute;
    top: 28px; right: 80px;
    font-size: 0.65em;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--brr-blue);
  }

  h1, h2, h3 {
    color: var(--brr-navy);
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  h1 { font-size: 2.4em; }
  h2 { font-size: 1.8em; }

  a { color: var(--brr-blue); text-decoration: underline; }
  strong { color: var(--brr-ruby); }

  code, pre { font-family: "JetBrains Mono", "Fira Code", Menlo, monospace; }
  code {
    background: rgba(40, 114, 180, 0.10);
    color: var(--brr-navy);
    padding: 2px 6px;
    border-radius: 3px;
  }
  pre {
    font-size: 0.78em;
    background: var(--brr-navy);
    color: #f0f4fa;
    padding: 18px 22px;
    border-radius: 6px;
    border-left: 4px solid var(--brr-ruby);
  }
  pre code {
    background: transparent;
    color: inherit;
    padding: 0;
  }

  blockquote {
    font-size: 1.5em;
    border-left: 6px solid var(--brr-ruby);
    padding: 8px 0 8px 28px;
    margin-left: 0;
    color: var(--brr-navy);
    font-style: normal;
    font-weight: 500;
  }

  table { border-collapse: collapse; }
  th { background: var(--brr-navy); color: white; padding: 10px 16px; }
  td { padding: 8px 16px; border-bottom: 1px solid var(--brr-light); }
  tr:last-child td { border-bottom: none; }

  .small { font-size: 0.7em; color: #5a6a82; }
  .big { font-size: 1.6em; }

  /* Page numbers, themed. */
  section::part(pagination) { color: var(--brr-blue); }

  /* Title and closing slides invert: navy background, light type.
     All overrides below were chosen to clear WCAG AA (4.5:1) for normal
     text and 3:1 for large text against the navy background. */
  section.title {
    background: var(--brr-navy);
    color: white;
    text-align: center;
    padding-top: 18%;
  }
  section.title::after { color: var(--brr-light); }
  section.title h1 {
    color: white;
    font-size: 3.2em;
    margin-bottom: 0.1em;
  }
  section.title h2 {
    color: var(--brr-light);
    font-weight: 400;
    font-size: 1.4em;
    margin-top: 0;
  }
  /* Brighter ruby (#ff5b62 ≈ 5.0:1 on navy) so the URL pops without
     dropping below WCAG AA. The original --brr-ruby is fine on cream
     but fails on navy. */
  section.title strong { color: #ff5b62; }
  section.title a { color: var(--brr-light); }
  /* Inline code on title slides: invert to white-on-translucent-white
     (≈ 12:1 on navy) — the cream-on-cream default is invisible here. */
  section.title code {
    background: rgba(255, 255, 255, 0.18);
    color: white;
  }
  section.title pre {
    background: rgba(255, 255, 255, 0.08);
    color: white;
    border-left-color: #ff5b62;
  }
  section.title pre code {
    background: transparent;
    color: inherit;
  }
  /* Disclosure / fine-print on title slides — clears AA at ~6.5:1. */
  section.title .small { color: #b9cde0; }
---

<!-- _class: title -->

# gem-contribute

## Building what you cannot find

Chris Hagmann · Blue Ridge Ruby 2026

---

<!-- Speaker note: Hold for 3 beats. Let the room read it.
     Don't say "Gemfile" or "lockfile" yet — that's the bundle fund
     reveal four slides from now. -->

> Every Ruby developer has wanted to contribute back.
>
> Most have never figured out where to start.

---

<!-- Speaker note: This is the talk title made literal. You're at
     Hack Day right now. So was I, in March. The list I went looking
     for is the one I'm about to show you. -->

## Building what you cannot find

I signed up to help organize **Hack Day** for this conference.

<br>

I needed a list of **good Ruby projects** to point people at.

<br>

That list didn't exist.

<br>

> So I built one.

---

## What's out there

- **goodfirstissue.dev** · opt-in registry · sparse
- **goodfirstissues.com** · opt-in registry · sparse
- **github.com/topics/good-first-issue** · opt-in topic · sparse
- **forgoodfirstissue.github.com** · curated · narrow

<br>

The inventories aren't sparse by accident — they're sparse because they're **opt-in.**

<br>

Drop opt-in and the inventory becomes **everything on GitHub.**

Now you need a **heuristic.**

---

## `bundle fund` already chose

When you give *money* to open source, you don't pick a project at random. You pick from your **lockfile** — the projects you've already bet on, with versions pinned, code you have context on.

<br>

That's the same logic, whether the unit is **dollars** or **hours**.

<br>

> `gem-contribute` is **`bundle fund` for time.**

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

<!-- _class: title -->

<!-- Speaker note: This is the takeaway. gem-contribute is the
     example, not the lesson. Read slowly — one beat per line.
     The audience should leave with this slide in their head, not
     the install command. -->

## Build what you cannot find.

<br>

> Build for yourself first.
> Help where you can.
> The rest is bonus.

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
