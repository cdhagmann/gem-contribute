# Talk source

Lightning talk for Blue Ridge Ruby 2026: *Building what you cannot find*.

`lightning.md` is a [Marp](https://marp.app/) presentation. The same file
is the source of truth for HTML, PDF, and the slides shown live.

## Render the slides

The easiest path is the Marp VS Code extension — open `lightning.md` and
preview it in the side panel. For a finished export:

```sh
# one-time
npm install -g @marp-team/marp-cli

# preview live in browser
marp --server talk/

# export to PDF (recommended for the talk itself — survives wifi)
marp talk/lightning.md --pdf -o talk/lightning.pdf

# export to standalone HTML
marp talk/lightning.md --html -o talk/lightning.html
```

## Speaker notes

Embedded as `<!-- ... -->` HTML comments inside `lightning.md`. They
don't render in the slide output but show up in Marp's presenter view.

## Demo recording

Always record the live demo before the talk and have the video queued
on the second monitor. Wifi at conferences is unreliable. If `submit`
hangs, you swap to the recording without losing the audience.

## Timing

Target 5 minutes. Practice with a phone timer at least four times
standing up. Cut on every pass.
