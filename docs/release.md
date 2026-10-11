# Release: signed, notarized DMG

The `release` job in `.github/workflows/ci.yml` runs on a `v*` tag push (or by hand via *Run workflow*). It signs `Hours.app` with a Developer ID Application certificate (hardened runtime), packs `build/Hours.dmg`, notarizes it with `notarytool`, staples the ticket, and uploads the DMG as a workflow artifact. Publishing to GitHub Releases and Sparkle come with ticket 13.

## Repository secrets

| Secret | What |
| --- | --- |
| `MACOS_CERTIFICATE` | The *Developer ID Application* certificate + private key exported from Keychain Access as `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | The password chosen when exporting the `.p12` |
| `APPLE_ID` | The Apple ID email of the developer account |
| `APPLE_TEAM_ID` | The 10-character Team ID (developer.apple.com → Membership) |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID (appleid.apple.com → Sign-In and Security) |

## Cutting a release

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The tag (without `v`) becomes `CFBundleShortVersionString`; the workflow run number becomes `CFBundleVersion`.

## Locally

```sh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh dmg
xcrun notarytool submit build/Hours.dmg --wait --apple-id … --team-id … --password …
xcrun stapler staple build/Hours.dmg
```
