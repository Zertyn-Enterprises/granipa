# Helper approval correction and unresolved launch failure

## Verified machine state

- Installed 2.0.1 build 7 was notarized and stapled successfully. Apple submission
  `0be4bd90-e72e-411a-8808-f54ab4a08463` was Accepted. Installed-app Gatekeeper
  assessment returned `accepted`, source `Notarized Developer ID`.
- This did NOT fix helper startup. AMFI logged `c[5]p[1]m[1]e[0]`, helper
  validation category 6, and launchd removed the failed service.
- App and helper retain Developer ID team R4V252C833. Neither the helper binary
  nor its plist contains an added launch/spawn constraint. No identifiers,
  signing requirements, entitlements or XPC methods were changed in this patch.
- A controlled press of the existing installed-app Install button captured the
  job before launch: parent bundle version 7, `has LWCR`, registered through smd.
  It is not using the old build 5 registration now.
- At 16:33 the job had 675 runs and EX_CONFIG (78), with `needs LWCR update`.
  Scoped logs repeatedly report `Unable to get updated LWCR` for the Grañipa BTM
  UUID with `error 0x16 - Invalid argument`. This is NOT a verified SMC or XPC
  client-validation failure: no successful helper response has been observed.
- BTM earlier reported parent pending authorization. That does not prove that
  granting consent alone will resolve the separate launch-constraint failure.

## Verified app defect and correction

Apple DTS demonstrates SMAppServiceErrorDomain code 1 for missing administrator
approval: https://developer.apple.com/forums/thread/802443. The local SDK also
documents kSMErrorLaunchDeniedByUser. These exact domain/code combinations now
open Login Items and return/throw needsApproval before checking a stale enabled
status. Same-number errors in unrelated domains remain failures.

The app previously only recognized an immediate requiresApproval status, leaving
the documented code-1 path as a generic error. Its charge tick also overwrote
installation messages. GLM implemented the correction; Codex orchestrated and
verified it. The automatic install alert and manual repair entry points remain
distinct, with install blocked while repair is busy.

Setup progress/errors now use separate observable text. Normal charge updates
cannot overwrite it. Real helper callbacks can replace it after setup finishes.
Successful registration remains transient controlMessage feedback so it cannot
mask later errors. Settings adds Open Login Items and removes the guaranteed
password-prompt claim. This is registration guidance, not a health probe.

Callers: BatteryService.installHelper (automatic prompt), repairHelper (Settings
and menu), registerSMAppService, performRepair. Both helper-message rendering
sites prefer the setup message. Persisted preferences and charge policy are intact.

## Tests and review

- Baseline: 457 tests / 75 suites, 18.074 seconds.
- Independent GLM test-author used acceptance criteria and API signatures only.
  The six approval tests compiled against pre-fix code: four failed / nine issues;
  unrelated-domain cases passed. No real registration is mocked as E2E success.
- Two setup-message tests detected a temporary omission of setup-message writes:
  two failed / four issues. Omitted production lines were restored immediately.
- Test-author fixture corrections: use the SDK status .enabled, not nonexistent
  .registered; BatteryHelperError is top-level; existing registration copy ends
  with a period. None changes an expected behavior to accommodate production.
- Cross-review changed success persistence deliberately: persistent success hid
  subsequent control errors. The independent author supplied the replacement
  assertions: nil setup message AND preserved registered controlMessage. The
  original exact failure assertion and failure-to-retry path were retained; the
  author's looser contains assertion was not adopted.
- Intermediate final suite: 465 tests / 77 suites passed, 10.710 seconds;
  release build passed in 78.02 seconds. Final build-8 gates are recorded below.
- Full GLM xreview returned ISSUES. The substantive success-shadowing issue was
  corrected. Generic helper failures can still expose Open Login Items as a
  diagnostic destination, without asserting they are permission failures.
  Lifecycle tests do not cover real administrator consent or launchd recovery.
  The proposed SMAppServiceError.Code enum was not found in the SDK; the code-1
  mapping has an explicit Apple DTS reference. No speculative helper extraction
  or timeout was added merely to satisfy review nits.
- No configured Swift linter exists. No dependencies were added or updated.
- A temporary host-approval quota error blocked a test call. The mutation was
  restored. Restricted verification also failed (Swift cache access, then nested
  sandbox denial); no security bypass was used. Authorized execution later resumed.

## Blocked / not done

Actual helper startup and successful charge control remain unverified. Do not
publish this candidate as a complete helper fix. No TCC reset, global resetbtm,
security downgrade, manual SMC write, OS restart, or unrelated-service mutation
was performed. User administrator consent cannot be supplied by the agent.

Apple references for diagnostics:
- https://developer.apple.com/documentation/security/applying-launch-environment-and-library-constraints
- https://developer.apple.com/documentation/security/defining-launch-environment-and-library-constraints
- https://developer.apple.com/forums/thread/799933

The latter documents a similar development-history problem but not a verified
per-app recovery for this Mac. Global reset is not an approved automatic remedy.

## Final candidate gates

- `swift test --no-parallel`: 465 tests / 77 suites pass, 19.856 seconds.
- `Scripts/bundle.sh release` with the existing Developer ID: exit 0; Swift
  release compilation 268.19 seconds. Local bundle version 2.0.1, build 8.
- Host `codesign --verify --deep --strict`: exit 0.
- `plutil -lint Resources/Info.plist`, `git diff --check`, and
  `gitleaks dir Sources/Granipa/System --no-banner --redact`: exit 0.
- No edits from temporary regression experiments remain. Final tests deliberately
  retain exact failure text and the failure-to-success retry path.
- Auto-review rejected notarizing build 8: it requires explicit authorization for
  this new artifact, distinct from the prior build-7 approval. Nothing was sent
  for build 8; no attempt to bypass that decision. Installed build 7 remains intact.
- No main merge or publication. This is a verified app-flow correction and a
  locally signed candidate, NOT a verified resolution of the OS launch failure.

## Build 8 notarization after explicit approval

- The user explicitly approved notarizing and testing build 8. Apple accepted
  submission `89606c75-71ac-4f9a-81bf-85d30b9c31aa`.
- The isolated candidate at
  `/private/tmp/granipa-build8-notary.2XWEKe/Grañipa.app` is version 2.0.1 / 8.
  Staple validation and host deep/strict signature verification passed.
  Gatekeeper returned `accepted`, source `Notarized Developer ID`.
- Before replacement, the installed build-7 helper still had EX_CONFIG (78),
  857 runs and `needs LWCR update`; notarization acceptance is not proof of
  helper recovery. No public release was made.
- Installed Grañipa was still running. The guarded normal-quit probe could not
  confirm idle capture from Settings; after Back to app reached Home, Dictation
  navigation returned no actionable control. The replacement command stopped
  before backup/move/copy. Build 7 was left intact and the user was asked to
  close Grañipa normally. Build-8 runtime testing awaits that safe closure.
