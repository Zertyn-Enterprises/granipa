# Grañipa 2.0.0 release candidate

Source: `feat/granipa-v2@337d0f4`. Display version `2.0.0`, build `6`.
Public release publication and merge remain human actions; neither was performed.

## Verified packaging

- `CODESIGN_ID='Developer ID Application: Zertyn LLC (R4V252C833)' NOTARY_PROFILE=granipa ./Scripts/release.sh`: exit 0.
- Apple notarization `e1411b7b-0757-4e28-9ca8-6eea1e1f8dcd`: Accepted.
- Stapling and `xcrun stapler validate`: passed.
- Archive Utility extraction, deep strict signature verification and Gatekeeper assessment: passed.
- `spctl --assess --type execute --verbose=2`: accepted, Notarized Developer ID.
- Sparkle `sign_update --verify` against the generated enclosure signature: exit 0.
- Existing bundle identifier, feed URL and public signing key unchanged.
- Appcast contains build 6, display version 2.0.0, macOS 26.0 minimum and arm64 requirement.

Artifacts are ignored build outputs, not committed:

- `build/Granipa-v2.0.0.zip`: 9046182 bytes.
- SHA-256: `227e7cdf84d80bc678ae996abcf550dcc9bad5bfa9fcca3a1150ccb3c7de7b24`.
- `build/appcast.xml`: enclosure points to the same ZIP under the existing latest-release download URL.

## QA and limitations

The preceding metadata preparation passed 446 tests in 74 suites with
`swift test --no-parallel`, production compilation, plist lint, diff checking,
and GLM review (OK). No configured Swift linter was found. No source changed
between that verification and packaging.

The previously observed default parallel-test cancellation timing failure remains
unresolved. The final additional meeting-open AX probe was inconclusive. This
packaging check is not proof of all live audio, paste or update-install flows.
Deferred tags, tasks and integrations are not included merely by naming this V2.

## Human publication handoff

Review and merge the V2 branch through a PR, then tag the reviewed source as
`v2.0.0`. Do not create a tag from the old main revision. Publish the ZIP and
appcast together in the same non-prerelease release, marked latest. Verify that
the public latest appcast and ZIP match these files, then test Check for Updates
from an installed older version. No public update notification exists until
publication; clients may check at different times or disable automatic checks.
