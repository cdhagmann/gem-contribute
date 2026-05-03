# Architecture Decision Records

This directory contains short, dated records of meaningful design decisions. Each ADR captures one decision, the context it was made in, the alternatives considered, and the consequences accepted. The goal is auditable reasoning, not exhaustive documentation.

Format: [Michael Nygard's template](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md), kept short.

## Index

- [0001 — Just-in-time auth](0001-just-in-time-auth.md)
- [0002 — Use Bundler's lockfile parser](0002-bundler-lockfile-parser.md)
- [0003 — Prefer `bug_tracker_uri` over `source_code_uri`](0003-issue-tracker-preference.md)
- [0004 — Use OAuth Device Flow, not PATs](0004-device-flow-auth.md)
- [0005 — Render labels verbatim](0005-render-labels-verbatim.md)
- [0006 — Ship as a standalone gem, not a Bundler plugin](0006-standalone-gem-not-plugin.md) — Bundler-plugin decision reversed by 0014; standalone-gem decision stands
- [0007 — Show CONTRIBUTING; don't parse it](0007-display-contributing-verbatim.md)
- [0008 — Use Rooibos for the TUI layer](0008-rooibos-tui-framework.md) — superseded by 0010, substance restored by 0013
- [0009 — Top-level namespace is `GemContribute`](0009-top-level-namespace.md)
- [0010 — Use Charm-Ruby (bubbletea + lipgloss) for the TUI layer](0010-charm-ruby-tui-framework.md) — superseded by 0013
- [0011 — HostAdapter owns host verbs; Operations compose them; CLI verbs compose Operations](0011-host-adapter-owns-host-verbs.md)
- [0012 — Output-free service objects, dry-monads Result contract, three-interface architecture](0012-output-free-service-objects-three-interface-architecture.md) — packaging amended by 0014; service-layer contract stands
- [0013 — Revert TUI framework to Rooibos](0013-revert-to-rooibos.md) — supersedes 0010, restores 0008's substance
- [0014 — Ship Bundler and RubyGems plugins as v1 interfaces](0014-ship-bundler-and-rubygems-plugins.md) — amends 0006 and 0012

## When to add an ADR

Add one when a decision is non-obvious *and* would be expensive to reverse. Don't add one for "we used Minitest." Do add one when "we picked X over Y for non-obvious reasons and someone six months from now will wonder why."
