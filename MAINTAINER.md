# Maintainer notes

This document is for the person who maintains the published `gem-contribute`
gem. Most contributors will never need to read it. It captures the few
out-of-band steps that can't be automated or committed.

## OAuth App registration (one-time, required for Stage 2)

`gem-contribute` authenticates users with GitHub via the OAuth 2.0 Device
Authorization Grant. See [ADR-0004](docs/adr/0004-device-flow-auth.md) for
why we picked device flow over Personal Access Tokens.

Device flow needs only a **client ID**, no client secret. The client ID is a
public value that ships in the source tree — there is nothing to protect.
GitHub explicitly supports this pattern for CLI tools (see the [GitHub
docs][gh-device-flow]).

### Steps

1. Sign in to the GitHub account that will own the OAuth App. For now this
   is Chris's personal account. If the gem is later donated to a more
   permanent home, the OAuth App migrates with it (you'd register a new App
   under the new owner and update `CLIENT_ID` in `lib/gem_contribute/auth.rb`).

2. Go to <https://github.com/settings/developers>.

3. Click **"OAuth Apps"** in the left sidebar, then **"New OAuth App"**.

4. Fill in the form:

   | Field                          | Value                                                    |
   |--------------------------------|----------------------------------------------------------|
   | Application name               | `gem-contribute`                                         |
   | Homepage URL                   | `https://github.com/cdhagmann/gem-contribute`            |
   | Application description        | `Find and contribute to the gems in your Gemfile.lock.`  |
   | Authorization callback URL     | `https://github.com/cdhagmann/gem-contribute`            |

   The "Authorization callback URL" is a required field on the form but
   isn't used by device flow. Pointing it at the repo URL is the
   conventional dummy value.

5. Click **"Register application"**.

6. **Critical — enable Device Flow.** On the App's settings page after
   registration, scroll down to the **"Device Flow"** section and check
   **"Enable Device Flow"**, then click **"Update application"**. Without
   this checkbox, the device-flow endpoints return
   `device_flow_disabled` and the tool will not work. This step is easy to
   miss because it's a separate save below the basic settings.

7. Copy the **Client ID** from the App's settings page. It looks like
   `Iv1.abcdef0123456789` for newer GitHub OAuth Apps or a 20-character
   hex string for older ones. **Do not generate or copy a client secret.**
   Device flow doesn't use one.

8. Paste the Client ID back into the conversation with Claude Code, or
   commit it directly to `lib/gem_contribute/auth.rb` as the value of the
   `CLIENT_ID` constant. The current placeholder is a deliberate
   sentinel that will raise at runtime.

### Rate limits to know about

- **50 device-code requests per hour, per OAuth App.** This is the cap on
  *starting* a device flow, not on completing one. Workshop scale (~12
  attendees) is comfortably under. If the tool ever sees enough adoption
  to brush this limit, register additional OAuth Apps (and round-robin
  client IDs) or migrate to a GitHub App with refresh-token logic.

- **The user's own API rate limit** is the standard 5,000/hr authenticated.
  No App-level cap.

### Migrating the App later

If `gem-contribute` moves to an org or a different maintainer:

1. The new owner registers a fresh OAuth App following the steps above.
2. Update `CLIENT_ID` in `lib/gem_contribute/auth.rb` and ship a new gem
   release.
3. Existing users will see one auth re-prompt the next time they invoke an
   auth-required command, because the new client ID won't match the cached
   token's issuer. That's acceptable — it's effectively a one-time
   re-login event.

The old OAuth App can stay registered for a transition period so users on
older gem versions continue to work.

## Cutting a release

Releases publish to rubygems.org via [Trusted Publishing][gh-trusted-pub]
(OIDC) — there is no `RUBYGEMS_API_KEY` secret and no manual `gem push`.
A `v*` tag push triggers `.github/workflows/release.yml`, which verifies
the tag matches `GemContribute::VERSION`, checks that `CHANGELOG.md` has a
dated section for the version, runs rubocop and rspec, and then publishes.

### One-time setup (before the first automated release)

The rubygems.org Trusted Publisher entry must exist before any tag push
can succeed. For an unclaimed gem name, use the **pending publisher**
flow:

1. Sign in at <https://rubygems.org>.

2. Go to <https://rubygems.org/profile/me/oidc/pending_trusted_publishers/new>.

3. Fill in the form:

   | Field             | Value                |
   |-------------------|----------------------|
   | Gem name          | `gem-contribute`     |
   | Repository owner  | `cdhagmann`          |
   | Repository name   | `gem-contribute`     |
   | Workflow filename | `release.yml`        |
   | Environment       | `release`            |

   The "Environment" value matches `environment: release` in the
   workflow. Leave blank if you removed that line; otherwise both must
   match exactly.

4. Submit. The publisher entry is now "pending" — it has no gem attached
   yet. The first successful publish from this workflow claims the name
   and promotes the entry to a regular trusted publisher.

After the gem is published, you can add additional trusted publishers
(e.g. for a fork or replacement workflow) from the gem's settings page on
rubygems.org instead of the pending-publisher flow.

### Configure the GitHub environment (one-time)

The workflow runs in an `environment: release` job. Create the environment
in the repo so the OIDC claim carries the correct value:

1. GitHub repo → Settings → Environments → **New environment**.
2. Name it `release`.
3. (Optional) Add yourself as a **Required reviewer** for a manual
   approval gate before each publish. Recommended for the first few
   releases until you trust the workflow.
4. No secrets to configure. Trusted publishing replaces secrets entirely.

### Per-release checklist

When cutting a new version:

1. **Bump the version.** Edit `lib/gem_contribute/version.rb` to the new
   `MAJOR.MINOR.PATCH`. Follow [SemVer](https://semver.org/).

2. **Regenerate `Gemfile.lock`.** Run `bundle install`. The lockfile's
   `gem-contribute (X.Y.Z)` line must match the new version in both the
   PATH spec at the top and the CHECKSUMS section near the bottom. CI
   runs bundler in deployment/`--frozen` mode and refuses to install if
   the lockfile is out of sync with the gemspec.

3. **Update CHANGELOG.md.** Move the contents of `[Unreleased]` into a
   new dated section: `## [X.Y.Z] - YYYY-MM-DD`. Leave `[Unreleased]`
   empty for the next cycle. The release workflow refuses to publish if
   it can't find a `## [X.Y.Z]` section matching the tag.

4. **Commit on `main`.** Bump version.rb, the regenerated Gemfile.lock,
   and CHANGELOG.md all in the same commit. Conventional message:
   `Bump gem-contribute to X.Y.Z`.

5. **Tag and push.**

   ```sh
   git tag -a vX.Y.Z -m "X.Y.Z"
   git push origin main vX.Y.Z
   ```

6. **Watch the Actions tab.** The workflow will:
   - verify the tag/version/CHANGELOG match
   - run rubocop and rspec
   - request an OIDC token, exchange it for a short-lived rubygems API
     key, and publish the gem
   - create a draft GitHub release with auto-generated notes

   If the environment has a required-reviewer protection rule, the
   workflow will pause for your manual approval before the publish step.

7. **Sanity check.** After publish, `gem info gem-contribute` should show
   the new version. The draft GitHub release is yours to edit and publish
   when ready.

### Troubleshooting

- **"Tag … does not match GemContribute::VERSION"** — version.rb is out of
  sync with the tag. Either delete the tag and bump version.rb, or
  re-tag at the right SHA after fixing version.rb.
- **"CHANGELOG.md is missing a section for …"** — add the dated section,
  amend the bump commit, force-push, delete the old tag, retag, push.
  (Force-push is fine on the bump commit before the publish has
  succeeded.)
- **OIDC failure / "no trusted publisher matches"** — check the
  rubygems.org publisher entry: gem name, repo owner, repo name,
  workflow filename (`release.yml`, not the full path), and environment
  must all match. The workflow filename is the basename only, no
  `.github/workflows/` prefix.
- **`gem push` fails with `multifactor authentication required`** —
  trusted publishing satisfies MFA. If you see this error, the workflow
  fell back to a non-OIDC path; verify `permissions.id-token: write` is
  set on the job.

### Yanking a release

Yanks happen via the rubygems.org web UI or `gem yank gem-contribute -v
X.Y.Z`. There is no automated yank flow — by design. If you need to yank,
also delete the corresponding `vX.Y.Z` tag and GitHub release so the
record on GitHub matches what's available on rubygems.org.

[gh-device-flow]: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
[gh-trusted-pub]: https://guides.rubygems.org/trusted-publishing/
