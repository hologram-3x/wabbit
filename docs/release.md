# Release: signed, notarized DMG

The `release` job in `.github/workflows/ci.yml` runs on a `v*` tag push (or by hand via *Run workflow*). It signs `Wabbit.app` with a Developer ID Application certificate (hardened runtime), packs `build/Wabbit.dmg`, notarizes it with `notarytool`, staples the ticket, and uploads the DMG as a workflow artifact. On a tag it also signs a Sparkle appcast (`appcast.xml`) with the EdDSA private key and creates a GitHub Release with `Wabbit.dmg` and `appcast.xml`.

## Repository secrets

| Secret | What |
| --- | --- |
| `MACOS_CERTIFICATE` | The *Developer ID Application* certificate + private key exported from Keychain Access as `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | The password chosen when exporting the `.p12` |
| `APPLE_ID` | The Apple ID email of the developer account |
| `APPLE_TEAM_ID` | The 10-character Team ID (developer.apple.com → Membership) |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID (appleid.apple.com → Sign-In and Security) |
| `SPARKLE_ED_PRIVATE_KEY` | The Sparkle EdDSA private key (see below). Never commit it. |

And one repository **variable** (Settings → Secrets and variables → Actions → Variables), since it's public:

| Variable | What |
| --- | --- |
| `SPARKLE_PUBLIC_ED_KEY` | The matching public key. `scripts/build-app.sh` writes it into `Info.plist` as `SUPublicEDKey`. Without it the app embeds Sparkle but never checks and "Check for Updates…" is disabled (that's what local and CI test builds do). |

## Sparkle keys (once)

Sparkle's tools come with the SwiftPM package; after any `swift build` they're in `.build/artifacts/sparkle/Sparkle/bin/`.

```sh
B=.build/artifacts/sparkle/Sparkle/bin
$B/generate_keys                         # creates the key in your login Keychain, prints the public key
$B/generate_keys -x sparkle_private.key  # exports the private key to a file
gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle_private.key && rm -P sparkle_private.key
gh variable set SPARKLE_PUBLIC_ED_KEY --body "<public key printed above>"
```

Keep the private key in the Keychain (or a password manager) too: losing it means existing installs can't verify updates anymore. Changing it later needs one release signed with the old key that ships the new public key.

## Where the appcast lives (private repo caveat)

`SUFeedURL` in `App/Info.plist` is `https://github.com/hologram-3x/wabbit/releases/latest/download/appcast.xml`, and the appcast points each DMG at `https://github.com/hologram-3x/wabbit/releases/download/<tag>/Wabbit.dmg`. **While `hologram-3x/wabbit` is private, those URLs return 404 to anyone not logged in**, and Sparkle sends no GitHub credentials, so update checks fail ("Update Error"). Options:

1. **Public releases-only repo** (recommended): e.g. `hologram-3x/wabbit-releases`, empty except for Releases. In `ci.yml` add `--repo hologram-3x/wabbit-releases` to `gh release create`, use a fine-grained PAT with *Contents: write* on that repo as `GH_TOKEN` (secret `RELEASES_TOKEN`), and change the repo name in `--download-url-prefix` and in `SUFeedURL`.
2. **Hosted appcast**: publish `appcast.xml` and the DMG on any static HTTPS host (GitHub Pages of a public repo, S3/R2, the company site) and point `SUFeedURL` and `--download-url-prefix` there.
3. **Make `hologram-3x/wabbit` public**: everything works as configured.

Whatever the choice, `SUFeedURL` is baked into every shipped build, so pick it before v1.0: moving it later means one last release on the old feed that ships the new URL.

## Cutting a release

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The tag (without `v`) becomes `CFBundleShortVersionString`; the workflow run number becomes `CFBundleVersion`.

## v1.0 (needs a human)

1. Do the Sparkle keys step above and pick where the appcast lives (edit `SUFeedURL` and `ci.yml` if not this repo).
2. Push this branch's `.github/workflows/ci.yml` change yourself (agents can't push workflow files).
3. `git tag v1.0.0 && git push origin v1.0.0`, wait for the `release` job: it notarizes, writes `appcast.xml` and creates the `v1.0.0` Release.
4. On a clean Mac (or a new user account): download `Wabbit.dmg` from the Release, drag Wabbit to Applications, open it. Gatekeeper must not complain; the clock appears in the menu bar; Launch at login is on.
5. Updates: tag `v1.0.1` the same way, then in the installed v1.0.0 choose **Check for Updates…**. Sparkle must offer 1.0.1, install it and relaunch.

## Footprint over a full workday (needs a human)

The budget (PLAN.md) is < 30 MB memory and ~0% CPU at rest. Measure the installed release build, not `swift run`:

1. Open Instruments → **Activity Monitor** template (or **Allocations** + **Energy Log**), target the running Wabbit, record for a workday while using the Mac normally: a call or two (Meeting Prompt), some Watched App prompts, open each window once and close it.
2. Pass if *Memory* (physical footprint, the number Activity Monitor shows; not RSS) settles under 30 MB after the windows are closed and *% CPU* is ~0 outside the moments you interact.
3. Quick command-line check at any time: `footprint $(pgrep -x Wabbit) | head -3` and `top -l 3 -s 30 -pid $(pgrep -x Wabbit) -stats pid,cpu,idlew,mem,time`.

## Locally

```sh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh dmg
xcrun notarytool submit build/Wabbit.dmg --wait --apple-id … --team-id … --password …
xcrun stapler staple build/Wabbit.dmg
```
