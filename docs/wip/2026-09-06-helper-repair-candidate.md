# Explicit helper repair candidate

User renewed the repair task after stable signing landed. Candidate implementation
is complete; installed-service recovery is NOT yet verified. The Mac was locked
at the runtime handoff, so the installed app was not replaced or terminated.

## Change

- Explicit repair validates the bundled executable and Applications location,
  resets the client connection, unregisters the existing registration and registers
  the current bundle. Normal automatic install remains registration-only.
- Registration and approval errors are surfaced; no claim of daemon health.
- Settings says Registered/Not registered using the existing 60-second cache.
- One observable busy flag disables repair buttons; progress, registration-success
  and real error messages are shown. No new SMC actions or automatic repair loop.
- XPC protocol, signing requirements, bundle identity, entitlements and persisted
  settings remain unchanged.

Callers: SettingsView and MenuBarView now invoke BatteryService.repairHelper;
the existing install prompt still invokes installHelper. Tests adjust the menu
source contract to the intended repair action, not to hide a regression.

## Gates

- First candidate: 456 tests/75 suites passed. GLM xreview: OK with three nits.
- Nits addressed: real registration error preserved, visible progress/success,
  bounded test gate and cancellation cleanup; additional approval-error test.
- Regression experiment temporarily omitted unregister: tests detected missing
  unregister ordering and missing unregister-error handling. Code restored.
- A test fixture initially threw the raw platform error into BatteryService,
  bypassing the client mapping while expecting the mapped message. Corrected the
  injected error to the actual client message; expectation was not weakened.
- Final `swift test --no-parallel`: 457 tests/75 suites passed, 11.718 seconds.
- `swift build -c release`: exit 0, 105.62 seconds.
- `git diff --check`: exit 0. No configured Swift linter exists in this repo.
- `gitleaks dir Sources/Granipa/System --no-banner --redact`: exit 0.

## Still required

Local candidate 2.0.1 (build 7) was bundled successfully after commit 94a5e76.
Host `codesign --verify --deep --strict --verbose=2` passed, including the helper
and Sparkle. The designated requirement retains Developer ID team R4V252C833.
An initial sandbox verification reported an invalid signature; verification in
the host security context succeeded. The helper executable is present.

Auto-review rejected running release.sh because Apple notarization transfers the
artifact externally and requires explicit authorization. Only bundle.sh was run
after that rejection: no notarization, publication or installed-app replacement.
The prior local bundle is backed up at
`/private/tmp/granipa-helper-candidate-backup.ljRpdY/Grañipa.app`.

Install the signed candidate only after normal app closure can be verified. Run
Repair battery helper, approve Login Items if macOS requests it, and verify the
registered parent bundle matches the candidate and no longer fails to spawn.
Do not claim mocked lifecycle tests prove actual launchd/XPC recovery.

Then test the agreed dictation/paste/meeting flows and permission continuity.
Do not publish a maintenance release until those runtime gates are addressed.
