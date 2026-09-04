# TokenWatch Mac release & updates

TokenWatch uses Sparkle 2 for in-app updates. Release archives are signed with a dedicated Ed25519 key stored in the release Mac's login Keychain under account `com.nathanwu.TokenWatch`; only the public key is committed to this repository.

## User behavior

- **Automatically check for updates** defaults to on.
- **Automatically update** defaults to off and can be enabled independently in Settings.
- Opening the main dashboard performs an informational update probe when the previous check is older than 15 minutes. It does not force an install dialog.
- Sparkle also schedules background checks once per hour.
- When a version is available, the dashboard shows a lightweight update banner. “Update” hands control to Sparkle's standard update UI.

## Release flow

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `Configs/Production.xcconfig`, then commit and merge to `main`.
2. On the release Mac, sync `main` so `HEAD == origin/main` and the worktree is clean.
3. Publish with, for example:

   ```sh
   ./Scripts/publish-github-release --tag v0.1.0-preview.2 --prerelease
   ```

   Add `--notes path/to/release-notes.md` when release notes are prepared.

The script builds the Universal app, ZIP and DMG, validates the embedded Sparkle feed/public key, signs `appcast.xml`, creates the version release as a **draft**, uploads and verifies every asset, publishes the version release, and only then replaces `appcast.xml` in the fixed `update-feed` release. This ordering guarantees clients never receive metadata pointing to a draft or incomplete release.

GitHub's `/releases/latest` endpoint excludes prereleases, so TokenWatch intentionally uses the stable direct feed URL:

`https://github.com/NathanWu12/TokenWatch-Mac/releases/download/update-feed/appcast.xml`

The `update-feed` release is machine-readable infrastructure; user-facing builds remain on their versioned releases.

## One-time Keychain authorization

The first time `generate_appcast` uses the TokenWatch signing key, macOS may ask for Keychain access. Choose **Always Allow** for the Sparkle `generate_appcast` tool on the trusted release Mac. Do not export or commit the private key just to bypass this prompt.

## Current preview limitation

The repository's local release pipeline still uses ad-hoc signing and is not Apple-notarized. Sparkle update signing protects update integrity, but it does not replace Developer ID signing/notarization. A public stable release should move the existing build pipeline to Developer ID + notarization separately.
