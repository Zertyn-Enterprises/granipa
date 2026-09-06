# Helper recovery and permission investigation

Status: blocked after two implementation attempts; all candidate code and tests
were reverted. Installed app, daemon registration and TCC permissions were not
modified. No new release was published in this task.

## Verified

- Installed V2 contains executable GranipaBatteryHelper.
- launchctl reports parent bundle version 5, spawn failed and EX_CONFIG 78.
- Current reinstall code registers without unregistering and treats an enabled
  registration as success after a registration error. UI says Installed from
  registration status, without checking daemon health.
- Public 1.0.4 and public 2.0.0 have identical designated requirements: Developer
  ID Application, bundle identifier com.zertyn.granipa, team R4V252C833.
- The saved internal development build has a different Apple Development DR.
- PermissionCenter already refreshes on app activation. Specific affected
  permission and a reproducible public-to-public update failure remain unknown.

## Attempts and gates

Grok exhausted its balance before editing. GLM implemented explicit async
unregister/register, error propagation, registration labels and serialized UI.
First pass failed new tests due to real bundle guards and malformed shell stubs.
Second helper pass compiled and passed 456 tests in 75 suites; signing tests
still failed 16 assertions and that entire item was reverted. New GLM review
reported ISSUES: synchronous uncached service status in render, unregister then
failed register recovery risk, missing successful approval-path test, plus seams
and redundant state observations. No third implementation was attempted.
The entire helper candidate was reverted as well; baseline code is unchanged.
Baseline before changes passed 446 tests in 74 suites.

Claude review was rejected by policy because sharing authorization named only
Grok, Kimi and GLM. No attempt was made to bypass that rejection.

## Next bounded proposal

Distinguish explicit repair from installation; cache registration status outside
rendering; retain explicit failure state if registration cannot be restored.
Validate with actual macOS service registration, not only mocked lifecycle tests.
Test a successful approval-required path and failure recovery. Keep XPC security,
SMC behavior, bundle identity and persisted settings unchanged.

For signing, default internal builds to the same Developer ID as distribution
and fail closed on real-signature failure, but first fix the isolated test
fixtures (quoted identity output, exported variables, assertion arity). Do not
claim that fixes a public-to-public permission regression: those DRs already match.
Ask which permission fails before choosing the next runtime reproduction.

Apple references:
- https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/
- https://developer.apple.com/documentation/servicemanagement/smappservice/register()
- https://developer.apple.com/documentation/ServiceManagement/SMAppService/unregister%28%29
