# Releasing Grañipa

## One-time setup (maintainer)

1. **Developer ID certificate** — Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application.
2. **Notarization credentials**:
   ```sh
   xcrun notarytool store-credentials granipa --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```
3. **Sparkle update-signing keys** — download the Sparkle tools from
   https://github.com/sparkle-project/Sparkle/releases (the `Sparkle-2.x.tar.xz`
   archive contains `bin/generate_keys` and `bin/generate_appcast`; put them on
   your PATH). Then:
   ```sh
   generate_keys
   ```
   The private key is stored in your Keychain. Copy the printed **public** key
   into `Resources/Info.plist` → `SUPublicEDKey` (replacing the placeholder)
   and commit.

## Every release

1. Bump both `CFBundleShortVersionString` (display version) and `CFBundleVersion` (build number) in `Resources/Info.plist`. The build number must exceed the current appcast `sparkle:version` so Sparkle offers the update. Then merge to `main` and tag.
2. ```sh
   ./Scripts/release.sh
   ```
   This builds, signs (Developer ID + hardened runtime, Sparkle framework
   included), notarizes, staples, zips, and generates `build/appcast.xml`
   (signed with your Sparkle key).
   Signing requires a Developer ID Application certificate for team
   `R4V252C833`; `Scripts/bundle.sh` validates the identity (override with
   `CODESIGN_ID`, given as exact certificate name or hash) before building
   and fails hard otherwise — there is no ad-hoc fallback.
3. Publish — **the appcast must be attached to the release** so the stable
   `releases/latest/download/appcast.xml` URL serves it:
   ```sh
   gh release create vX.Y.Z 'build/Granipa-vX.Y.Z.zip' build/appcast.xml --title 'Grañipa vX.Y.Z' --generate-notes
   ```

Installed apps check the appcast automatically and offer "Install and Relaunch".
People who build from source update with `git pull`.
