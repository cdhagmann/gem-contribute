---
marp: true
theme: default
paginate: true
size: 16:9
header: 'Blue Ridge Ruby 2026 · gem-contribute'
footer: ' '
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

  /* Header strap with the conference identifier on every content slide.
     Uses Marp's `header:` directive so it survives PDF export (unlike
     ::before/::after `content:` properties, which Marp drops). */
  header {
    position: absolute;
    top: 28px; right: 80px;
    left: auto;
    width: auto;
    margin: 0;
    font-size: 0.65em;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--brr-blue);
  }

  /* Footer is empty content but its element provides the gradient bar at
     the bottom of every slide. The four-color stripe is the conference
     palette in order. */
  footer {
    position: absolute;
    left: 0; right: 0; bottom: 0;
    margin: 0;
    padding: 0;
    height: 6px;
    width: 100%;
    color: transparent;
    font-size: 0;
    background: linear-gradient(
      to right,
      var(--brr-light) 0% 25%,
      var(--brr-ruby)  25% 50%,
      var(--brr-blue)  50% 75%,
      var(--brr-navy)  75% 100%
    );
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
  /* On title and closing slides we hide the header strap (no `Blue Ridge
     Ruby 2026 · gem-contribute` repeating over the title) but keep the
     gradient bar — it visually anchors every slide identically. */
  section.title header { display: none; }
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
  /* Blockquotes on title slides: white text, no left border (clashes
     with center alignment), constrained width so lines wrap naturally. */
  section.title blockquote {
    color: white;
    border-left: none;
    text-align: center;
    padding: 8px 0;
    margin: 0 auto;
    max-width: 70%;
    font-size: 1.4em;
  }
---

<!-- _class: title -->

<!-- Speaker note (~10s): Title slide. Smile, take a breath, let
     the room settle. "I'm Chris Hagmann. I want to talk about
     building tools that don't exist yet — using a small one I
     made this week as the example." -->

# gem-contribute

## Building what you cannot find

Chris Hagmann · Blue Ridge Ruby 2026

---

<!-- Speaker note (~15s): Hold the slide. Don't read it aloud —
     let them read it themselves. Then, quietly: "That's been me
     for years. I suspect it's been some of you." Beat. Move on.
     Make it personal, not a claim about the whole room. -->

> I wanted to contribute back.
>
> I never figured out where to start.

---

<!-- Speaker note (~25s): "I volunteered yesterday to help with
     Hack Day tomorrow. When I said yes, I needed a list of good
     Ruby projects with approachable issues to point people at.
     That list didn't exist." Pause on "didn't exist."
     Then: "So I built one. And along the way I noticed something
     that I think generalizes." That's the bridge to the next
     slide. -->

## A small problem

I volunteered to help with **Hack Day** tomorrow.

<br>

I needed a list of **good Ruby projects** to point people at.

<br>

That list didn't exist.

<br>

> So I built one.

---

<!-- Speaker note (~20s): "There ARE resources. Four of them, all
     fine, all sparse." Don't read the URLs. The point is the
     pattern, not the list. "They're sparse for the same reason:
     they need a maintainer to opt their project in. Most
     maintainers never do."
     Then the turn: "The signal I needed was a different kind of
     opt-in. Mine." Land on "mine." -->

## What's out there

- **goodfirstissue.dev** · opt-in registry · sparse
- **goodfirstissues.com** · opt-in registry · sparse
- **github.com/topics/good-first-issue** · opt-in topic · sparse
- **forgoodfirstissue.github.com** · curated · narrow

<br>

These all rely on **maintainer opt-in** — and most maintainers never do.

<br>

The signal I needed was a different kind of opt-in: **mine.**

---

<!-- Speaker note (~25s): "Bundler shipped this insight years
     ago. `bundle fund` reads your Gemfile.lock to answer one
     question: where should my dollars go? It's the right index
     for the question." Beat. "Same index, different question:
     where should my hours go?"
     Land hard on the slogan. This is the meme of the talk. -->

## `bundle fund` for time

`bundle fund` reads your `Gemfile.lock` to answer
*"where should my **dollars** go?"*

<br>

`gem-contribute` reads the same file to answer
*"where should my **hours** go?"*

---

<!-- Speaker note (~20s): "Two hundred and sixteen gems in this
     project. Two hundred and sixteen maintainers I've already
     bet on. Two hundred and sixteen codebases I have at least
     a little context on."
     "That's already a curated list. I just had to use it." -->

## The insight was already on disk

```
$ bundle list | wc -l
     216
```

<br>

Your `Gemfile.lock` is already curated.

- ~216 maintainers you've **already bet on**
- The OSS code you have **the most context on**
- A vote of confidence with versions attached

<br>

Start *there*, not on GitHub.

---

<!-- Speaker note (~45s): Let them read the output for ~10s
     before talking. Then walk down the list:
     "Sorbet has fifty open good-first-issues. Fifty."
     "RSpec OpenAPI, five. Packwerk, four. Rubocop, four."
     Point at gem-contribute on row three. Smile.
     "And the tool itself, four. It found itself. We'll come
     back to that." That's the meta-joke; don't oversell it. -->

## So I built it

```
$ gem-contribute scan
Scanning Gemfile.lock (234 gems)...
234 gems · 230 on github.com · 1 on gitlab.com · 3 unknown source

Top contributable projects (by open `good first issue` count):
  sorbet-runtime    50  github.com/sorbet/sorbet
  rspec-openapi      5  github.com/exoego/rspec-openapi
  gem-contribute     4  github.com/cdhagmann/gem-contribute
  packwerk           4  github.com/Shopify/packwerk
  rubocop            4  github.com/rubocop/rubocop
  gitlab             3  github.com/NARKOZ/gitlab
  pundit             2  github.com/varvet/pundit
  ...
```

<!-- (Drill-in slide cut for time. Mention in patter:
     "You can list the issues for any of these.") -->

---

<!-- Speaker note (~40s): Pre-frame: "You pick an issue. One
     command does the rest."
     Read silence ~8s. Then narrate: "It forks the repo to your
     account. Clones the fork locally. Adds the upstream remote.
     Creates a branch named after the issue."
     Pause. "All the git ceremony, gone." -->

## Fix it

```
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

<!-- Speaker note (~35s): "You write the fix. You commit it.
     You run submit." Beat for the URL to render.
     "It pushes your branch. It opens the compare URL with the
     title, the body, and `Closes #14102` already filled in."
     Bottom-line it: "Browser opens. PR is pre-filled. Review.
     Click Create." -->

## Submit it

```
$ gem-contribute submit
Pushing gem-contribute/issue-14102 to origin...
Opened browser to:
  https://github.com/rubocop/rubocop/compare/cdhagmann:gem-contribute/issue-14102
  ?expand=1&title=Fix+%2314102%3A+Allow+Lint%2FVoid+...&body=Closes+%2314102.
```

<br>

Browser opens. PR is pre-filled. Review. Click **Create**.

---

<!-- Speaker note (~20s): The bridge from demo to lesson. Slow
     down here. The tool is the example, not the lesson.
     "I'm doing this for gems. But the pattern works wherever
     you look. The things you depend on are the things you should
     give back to. Once you see that, you start noticing it
     everywhere." Pause. Move on. -->

## The pattern generalizes

> The things you depend on
> are the things you should give back to.
>
> Once you see that, you start noticing it everywhere.

---

<!-- _class: title -->

<!-- Speaker note (~15s): The takeaway slide. Read it slowly,
     one beat per line. Don't editorialize. The audience should
     leave the room with this in their head — not the install
     command, not the gem name, this. -->

> Build for yourself first.
>
> Help where you can.
>
> The rest is bonus.

---

<!-- _class: title -->

<!-- Speaker note (~10s): "Thanks. The gem installs today. I'll
     be at Hack Day tomorrow if you want to try it on your
     laptop. Find me." Don't run over. Step back from the mic. -->

## Thanks

`gem install gem-contribute`
**cdhagmann.com/gem-contribute**

<br>

Find me at **Hack Day** tomorrow — I'll watch it work on your laptop.

<br>

<span class="small">AI-assisted; ADRs explain why.</span>
