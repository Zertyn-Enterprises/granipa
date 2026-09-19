# Stable bundle signing

User authorized the narrowly scoped fix after TCC logs confirmed a stored Apple
Development requirement mismatched installed Developer ID code. No helper, TCC,
entitlement, bundle identifier, application source or installed app was changed.

`Scripts/bundle.sh` now selects only a valid Developer ID Application identity
for team R4V252C833, for debug and release. Exact certificate name or hash overrides
must resolve to that policy. Missing/invalid identities fail before building or
deleting the previous bundle. Signing failures abort, without an ad-hoc fallback.

## Verification

- Final 16 isolated tests against the old script: exit 1, 13 failures.
- Same 16 tests against the new script: exit 0.
- Tests cover default/explicit identity selection, rejected identities, old-bundle
  preservation on identity failure, and failures in XPC, Autoupdate, Updater.app,
  framework, helper and app signing. They run the real script with stub tools.
- `bash -n Scripts/bundle.sh`: exit 0.
- `ruff check Tests/Shell/test_bundle_signing.py`: exit 0.
- `swift test --no-parallel`: 446 tests / 74 suites passed.
- `swift build -c release`: exit 0.
- Real `./Scripts/bundle.sh release`: exit 0; Developer ID Application: Zertyn LLC.
- Deep strict codesign verification: exit 0.
- New bundle's designated requirement equals the installed public V2 requirement.
- `git diff --check`: exit 0.

## Review adjudication

Fresh GLM xreview returned ISSUES. Its principal claim was that `${@: -1}` is
unsupported by macOS Bash 3.2. Direct execution of `/bin/bash --version` returned
3.2.57; `/bin/bash -c 'set -- first second; printf "last=%s\n" "${@: -1}"'`
returned `last=second`, exit 0. All six signing failure tests also passed through
their `/bin/bash` stubs. The compatibility finding is therefore contradicted by
runtime evidence, not worked around or hidden by weakening assertions.

Two nonblocking observations remain: awk interprets backslashes in an unusual
certificate-name override (the hash override avoids that), and a failed security
tool lookup currently reports a missing identity rather than a distinct tool
error. Both fail closed. The real certificate name/hash paths were validated.

This fixes the packaging cause of identity drift, not previously mismatched OS
consents. No release was published, no installed app replaced, and no claim is
made that the separately blocked battery-helper repair is complete.
