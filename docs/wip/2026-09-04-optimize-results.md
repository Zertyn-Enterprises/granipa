# Grañipa optimization results — 2026-09-04

Baseline: `c10dbb8`

Measured Swift result: `02bb1d8`

Validated local bundle: `c61cd2a`

This report is incomplete only where a signed app, UI interaction, external
review, or remote write is required. Those gates are listed explicitly below.

## Baseline to result

| Metric | Baseline | Result | Delta |
|---|---:|---:|---:|
| Clean debug build, wall | 27.09 s | 26.22 s | -0.87 s (-3.21%) |
| SwiftPM-reported build | 26.78 s | 25.93 s | -0.85 s (-3.17%) |
| Full test command, wall | 10.02 s | 9.26 s | -0.76 s (-7.58%) |
| Test runtime | 0.657 s | 0.661 s | +0.004 s |
| Tests / suites / skipped | 177 / 37 / 0 | 180 / 36 / 0 | +3 / -1 / 0 |
| Unique Swift warning locations | 28 | 0 | -28 |
| Production Swift | 14,143 LOC / 99 files | 14,289 LOC / 99 files | +146 LOC |
| Test Swift | 2,182 LOC / 32 files | 2,218 LOC / 32 files | +36 LOC |
| Direct dependencies | 3 | 3 | 0 |
| `Sources/` | 728 KiB | 732 KiB | +4 KiB |
| `Tests/` | 156 KiB | 156 KiB | 0 KiB |
| `Resources/` | 1,884 KiB | 1,884 KiB | 0 KiB |
| Checkout excluding external scratch | 3,300 KiB | 3,352 KiB | +52 KiB |
| SwiftPM scratch after build/tests | 1,496,832 KiB | 1,497,372 KiB | +540 KiB |
| Debug `Granipa` executable | 29,091,184 B | 29,115,360 B | +24,176 B (+0.083%) |
| Debug battery helper | 207,040 B | 207,040 B | 0 B |
| `node_modules` / virtualenv | absent | absent | unchanged |

The timing figures are one clean run with the baseline command, not a benchmark;
machine load and filesystem cache can affect them. The LOC and executable growth
comes from the requested XPC, hotkey, and language fixes plus regression tests.
It must not be presented as a measured resource improvement. Controlled
idle/Record profiles are still required to quantify runtime savings.

Git churn in `Sources/` and `Tests/` was 358 additions and 178 deletions: 132
production lines and 46 test lines were removed. The bundle-script repair added
10 and removed 5 more lines, for 183 deleted code/script lines in total. Net LOC
grew because the three requested bug fixes needed implementation and regression
coverage; this optimization did not trade safety for a smaller line count.

The checkout size was measured before adding this result file. Baseline and
result both include their then-current `docs/wip` content, so this metric is a
coarse repository-size indicator rather than application payload size.

## Verified changes

### Correctness

- Battery helper replies now leave the private XPC queue before touching
  `MainActor`; a lock-backed latch handles termination-time synchronous replies.
  Four regression tests cover background replies, errors, timeout, and duplicate
  reply resolution. This directly addresses the supplied SIGTRAP stack.
- Modifier-only hotkeys now derive left/right physical state from the received
  `NSEvent` before the actor hop. The new edge test failed before the change and
  passes after it. A signed Right Command smoke remains pending.
- Automatic file transcription probes a bounded 15-second microphone prefix
  across distinct configured languages before one full decode per channel.
  A copied 12.1-second user recording with stale `lastSpeechLocale=en-US`
  selected `es-ES` and produced Spanish raw text in 1.161 s.
- Grañipa no longer adds its own battery icon or percentage to the macOS menu
  bar label. The battery controls remain in Grañipa's menu/settings.
- Local ad-hoc bundles no longer enable Hardened Runtime. On macOS 26, enabling
  it without a Team ID caused Library Validation to reject embedded Sparkle at
  launch. Real-identity builds retain Hardened Runtime and the release path is
  unchanged.

### Runtime and load-path reductions

- Meeting detection rejects unknown bundle IDs before querying their CoreAudio
  input state, returns at the first active known app, and drops cancelled results.
- Battery startup no longer performs the same initial IOPS snapshot twice.
  Unchanged snapshots and temperatures are not republished; machines without an
  internal battery skip temperature reads; the first working SMC key is reused.
- Onboarding resolves each of four LLM executables once per body evaluation.
  Each Settings provider row also resolves its executable once. Runtime LLM
  execution still re-resolves the path so newly installed CLIs remain visible.
- Main-thread AppKit panel operations are explicitly `MainActor` isolated, and
  four redundant actor `await` expressions were removed.
- Removed verified dead inputs/surfaces: LevelGate's unread level argument,
  MeetingGlyph's discarded seed, four Theme tokens, two hotkey/window accessors,
  one image wrapper, unreachable model-prewarming code, one unread battery field,
  and one unread successful-result field.
- Removed two tests with no unique behavioral assertion and one redundant
  prewarm suite; every duplicated assertion retained an equivalent or stronger
  test elsewhere.

## Verification completed

- `swift package --scratch-path ../../../.build clean`: exit 0.
- Clean `swift build --scratch-path ../../../.build --skip-update -c debug`:
  exit 0; zero source/test compiler warning locations.
- Full `swift test --scratch-path ../../../.build --skip-update`: exit 0;
  180 tests in 36 suites; zero failures and zero skipped.
- `.github/workflows/ci.yml` runs the same build/test gates. No project lint
  configuration or installed project linter exists.
- `bash -n Scripts/bundle.sh` and `bash -n Scripts/release.sh`: exit 0.
  Neither script has a non-mutating help/dry-run mode; release was not executed.
- The local 33,336 KiB ad-hoc bundle passes
  `codesign --verify --deep --strict`; its app and Sparkle signatures both have
  `flags=0x2(adhoc)`, and the process remained alive after launch on macOS 26.2.
  The bundle retains only the audio-input and calendar entitlements.
- Three directed audit loops covered functions, properties, types, dynamic
  string/selector references, dependencies, debug artifacts, tests, and hot
  loops. The final lexical pass found no additional 🟢 zero-caller removal.
- Removed an ignored 285,632 KiB `.build/repositories` cache left by the failed
  dependency download. It was generated and rebuildable, not tracked source.

Logs: `/tmp/granipa-opt-final-build.log`,
`/tmp/granipa-opt-final-build.time`, `/tmp/granipa-opt-final-test.log`, and
`/tmp/granipa-opt-final-test.time`.

## Blocked or deliberately not changed

- Clipboard History paste remains unresolved. The completion-based fix was
  exercised with two AppKit test-harness variants; one hung and one failed
  under the test runner, so all related source/test edits were reverted. A
  third unproved timing patch is forbidden by the task budget.
- The installed `/Applications/Grañipa.app` is not this branch: its executable
  was dated `2026-09-04 09:21:14` with SHA-256
  `6c75c457e88806bed2a5af03b4ad2a9880a9e5cf07c307d6063db4c4b6c7abfb`;
  the measured branch executable was dated `2026-09-04 11:07:04` with SHA-256
  `559f99b8a65acb876a55002605775b5ffc61c6dcd7147a4019bc47d2e72c4a3c`.
  The Right Command commit was created at `10:12:42`.
- `security find-identity -v -p codesigning` returned `0 valid identities` in
  this session. The tested build is therefore ad-hoc and may re-prompt for audio
  and Accessibility permissions; a Developer ID release cannot be tested here.
- Exact cold launch-to-ready is unmeasurable without adding instrumentation;
  the app has no ready signal/signpost, and the baseline had no signed-bundle
  measurement.
- One unmatched idle snapshot showed 43.1 MiB physical footprint for the new
  process versus 72.2 MiB for the old process. RSS was 91,040 KiB versus 83,712
  KiB, and thread count was 12 versus 9. The old process had run for two hours
  while the new one had run for two minutes, so these mixed figures do not prove
  a resource reduction. A controlled navigation/dictation/Record profile is
  still required.
- Manual Right Command, Clipboard paste, Record/Stop, language, navigation, and
  battery smoke remain pending user interaction and relevant TCC permissions.
- Attempts to invoke Grok, Kimi, and GLM review were blocked before transmitting
  data because the external-review approval must explicitly authorize sending
  the complete local diff to those providers.
- Push and the single PR are pending manual smoke and cross-review. No merge is
  authorized.

The following audited items were proposals only because they touch persisted
media/delivery, visible motion, external contracts, or lack a sufficient test or
profile: audio buffer/padding changes, orphan audio deletion, webhook
serialization/retention, hidden live-ASR removal, FluidAudio separation, icon
recompression, waveform frame-rate changes, EventKit refresh redesign, LLM
process cancellation/serialization, SMC target consolidation, broad Settings
splitting, clipboard prune timing, HTTP request-body shape, meeting-detector
stop state, and language-probe analyzer reuse.

## Commit groups

- Bugs: `eb6ce5f`, `8404721`, `fbe9b94`, `4037e7c`.
- Build tooling: `c61cd2a`.
- Runtime: `ee44877`, `6ccf1e8`, `4eb817f`, `7bcf07e`.
- Warning cleanup: `9f082ff`, `c5c4e84`, `5f0f7fd`.
- Dead code/tests: `a8b2d48`, `fcfc313`, `ab78eac`, `66ed3c7`,
  `4f6ac12`, `1cc9e60`, `248cffa`, `d987597`, `e9b1e61`, `02bb1d8`.
- Audit/plan: `e168bfc`, `cda719a`, `c552905`.
