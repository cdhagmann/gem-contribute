# Workshop issue ideas — staging area

Scratch list of issue candidates discovered during Stage 1–3 work. Triaged
into proper template-shaped markdown files when Stage 4 starts; this file is
deleted at that point.

The whole directory is `.gitignore`d until Stage 4. To promote: remove the
line from `.gitignore`, expand the strongest 12 ideas into individual files
following `.github/ISSUE_TEMPLATE/workshop-issue.md`, delete this file.

---

## Discovered during Stage 1 demo

### Follow GitHub repo-rename redirects (one hop)

**Where:** `lib/gem_contribute/host_adapters/github_adapter.rb#http_get`

**What:** When `api.github.com` returns `301 Moved Permanently` for a
repo URL, follow the `Location:` header once and use the new
owner/repo. Surface the rename as a `:repo_renamed` flag on the
returned data so callers can hint upstream that the gemspec is stale.

**Why this matters:** Gem authors who rename their GitHub username
(e.g. `sickill` → `ku1ik` for `rainbow`) leave their published gem
metadata pointing at the old name forever — RubyGems metadata is
frozen at publish time. The old URL still works because GitHub
redirects, but every downstream tool that doesn't follow redirects
(including this one in Stage 1) papers over a rename with a
warning. Following one hop fixes the immediate symptom; the
`:repo_renamed` flag enables the meta-feature below.

**Difficulty:** Trivial-to-moderate. ~15 lines + a spec with a
hand-crafted cassette that returns 301 with a Location header.

**Constraints / ADRs:** None directly. Single-hop only, so we don't
chase chains of redirects accidentally.

**Acceptance:**
- [ ] `GitHubAdapter#issues` against a renamed repo succeeds without
      a warning, using the redirected target.
- [ ] The first hop is followed; a second 301 raises the existing
      `AdapterError` so we don't loop.
- [ ] The returned response carries `repo_renamed: true` along with
      the new `owner`/`repo` so callers can tell.
- [ ] Spec covers: 301 with Location, 301 without Location (still
      raises), and 301 chain (raises after one hop).

---

### Surface "stale gemspec metadata" as its own scan section

**Where:** `lib/gem_contribute/cli/scan.rb` — relies on the
`:repo_renamed` flag from the issue above.

**What:** When the GitHub adapter follows a rename, mark the project
in the scan output as having stale gemspec metadata. Print a
secondary list:

```
Stale gemspec metadata (gemspec → live):
  rainbow   sickill/rainbow   →   ku1ik/rainbow
```

**Why this matters:** Each entry is a guaranteed-fixable
contribution: open the gemspec, replace the URLs, PR. It's a meta
feature — the tool finds its own raison d'être ("a tool for finding
contributable issues that itself surfaces a class of trivial
contributions to make"). Pairs well with the redirect-following
issue as a one-two punch a workshop attendee can do back-to-back:
fix the adapter, then use the now-better tool to find a stale gem
to PR.

**Difficulty:** Stretch. Requires the redirect-following work
landed first, plus output-shape discussion.

**Constraints / ADRs:** None new. ADR-0005 still holds — we display
the maintainer-authored data, we just also note when it's gone
stale.

**Acceptance:**
- [ ] Scan output includes a "Stale gemspec metadata" section when
      any project resolved via a 301.
- [ ] Suppressed when no renames detected (no empty section).
- [ ] Tested against a fixture with at least one renamed project.

---

## Slot for future ideas

Drop new candidates as we hit them in Stage 2/3. Each entry: where,
what, why, difficulty, ADR touch, acceptance. Doesn't need to be
template-perfect — just enough that we can promote it later without
re-doing the thinking.
