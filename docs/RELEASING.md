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

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, merge to `main`, tag.
2. ```sh
   ./Scripts/release.sh
   ```
   This builds, signs (Developer ID + hardened runtime, Sparkle framework
   included), notarizes, staples, zips, and generates `build/appcast.xml`
   (signed with your Sparkle key).
3. Publish — **the appcast must be attached to the release** so the stable
   `releases/latest/download/appcast.xml` URL serves it:
   ```sh
   gh release create vX.Y.Z 'build/Granipa-vX.Y.Z.zip' build/appcast.xml --title 'Grañipa vX.Y.Z' --generate-notes
   ```

Installed apps check the appcast automatically and offer "Install and Relaunch".
People who build from source update with `git pull`.
