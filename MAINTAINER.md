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

(Stub — fill in when we cut v0.1.0 to RubyGems. Notes will live here:
gemspec metadata checks, `bundle exec rake release` flow, signing, etc.)

[gh-device-flow]: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
