# Grañipa optimization results — 2026-09-04

Baseline: `c10dbb8`

Measured Swift result: `b563be2`

Validated current bundle: `b563be2`

The user validated Right Command and Clipboard paste on installed bundle
`77ca895`. Later transcription/audio commits are covered by automated gates and
a signed local bundle, but that exact bundle has not received another manual UI
smoke. External review findings and deliberately unintegrated candidates are
listed explicitly below.

## Baseline to result

| Metric | Baseline | Result | Delta |
|---|---:|---:|---:|
| Clean debug build, wall | 27.09 s | 21.78 s | -5.31 s (-19.60%) |
| SwiftPM-reported build | 26.78 s | 21.51 s | -5.27 s (-19.68%) |
| Full test command, wall | 10.02 s | 8.59 s | -1.43 s (-14.27%) |
| Test runtime | 0.657 s | 0.586 s | -0.071 s |
| Tests / suites / skipped | 177 / 37 / 0 | 197 / 37 / 0 | +20 / 0 / 0 |
| Unique Swift warning locations | 28 | 0 | -28 |
| Production Swift | 14,143 LOC / 99 files | 14,535 LOC / 99 files | +392 LOC |
| Test Swift | 2,182 LOC / 32 files | 2,800 LOC / 33 files | +618 LOC / +1 file |
| Direct dependencies | 3 | 3 | 0 |
| `Sources/` | 728 KiB | 744 KiB | +16 KiB |
| `Tests/` | 156 KiB | 180 KiB | +24 KiB |
| `Resources/` | 1,884 KiB | 1,884 KiB | 0 KiB |
| Checkout excluding generated build output | 3,300 KiB | 3,396 KiB | +96 KiB |
| SwiftPM scratch after build/tests | 1,496,832 KiB | 1,498,680 KiB | +1,848 KiB |
| Debug `Granipa` executable | 29,091,184 B | 29,241,328 B | +150,144 B (+0.516%) |
| Debug battery helper | 207,040 B | 207,040 B | 0 B |
| `node_modules` / virtualenv | absent | absent | unchanged |

The timing figures are one clean run with the baseline command, not a benchmark;
machine load and filesystem cache can affect them. The LOC and executable growth
comes from the requested XPC, hotkey, and language fixes plus regression tests.
It must not be presented as a measured resource improvement. Controlled
idle/Record profiles are still required to quantify runtime savings.

Final Git churn in `Sources/`, `Tests/`, and `Scripts/` was 1,297 additions and
284 deletions: 230 production lines, 49 test lines, and 5 script lines were
removed. Net LOC grew because the requested battery, dictation, audio continuity,
and transcription fixes needed implementation and regression coverage; this
optimization did not trade safety for a smaller line count.

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
  passes after it. The user confirmed that Right Command opens dictation in the
  installed, signed build.
- Clipboard History now posts Command-V only after the animated panel has
  completed `orderOut`; it no longer uses a 140 ms delay while the key panel can
  retain focus for 200 ms.
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
- Live meeting ASR remains opt-in after its previous high-CPU failure, but its
  Settings control is now reachable and captions cannot advertise an empty live
  stream.
- Microphone route changes append converted buffers and any real gap to the same
  `mic.m4a` instead of truncating earlier speech.
- Post-meeting ASR returns typed model/channel failures, preserves saved audio,
  closes analyzer result tasks, and shows a generic failure toast.
- Dictation rejects a second microphone capture while a meeting is recording.
- A detected locale remains the next-meeting hint after real audio analysis even
  if one channel fails; model-install failure leaves the old hint untouched.

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
  197 tests in 37 suites; zero failures and zero skipped.
- After the Clipboard fix, the same clean verification passed again: build
  39.59 s and tests 15.31 s. This slower second timing under different machine
  load confirms that the single-run timing deltas above are not a benchmark.
- `.github/workflows/ci.yml` runs the same build/test gates. No project lint
  configuration or installed project linter exists.
- `bash -n Scripts/bundle.sh` and `bash -n Scripts/release.sh`: exit 0.
  Neither script has a non-mutating help/dry-run mode; release was not executed.
- The current local 33,468 KiB bundle passes
  `codesign --verify --deep --strict`. It is signed with
  `Apple Development: Pablo Muñoz (J4S275P398)`, retains Team ID `R4V252C833`
  and Hardened Runtime, and contains only the audio-input and calendar
  entitlements. The same command must run outside the filesystem sandbox so
  `codesign` can read the system trust store.
- On the final launch, TCC reported `ListenEvent=2` and `Accessibility=2` before
  the user confirmed the Right Command smoke.
- Three directed audit loops covered functions, properties, types, dynamic
  string/selector references, dependencies, debug artifacts, tests, and hot
  loops. The final lexical pass found no additional 🟢 zero-caller removal.
- Removed an ignored 285,632 KiB `.build/repositories` cache left by the failed
  dependency download. It was generated and rebuildable, not tracked source.

Latest logs: `/tmp/granipa-opt-v2close-build.{log,time}`,
`/tmp/granipa-opt-v2close-test.{log,time}`, and
`/tmp/granipa-opt-v2close-bundle-final.log`.

## Blocked or deliberately not changed

- Clipboard's focus-transfer path has no automated AppKit test. Two test-runner
  harnesses failed earlier, and the automation smoke was blocked by macOS
  error `-1743` before it could control System Events. The deterministic timing
  defect was removed, the full suite passed, and the signed build was installed
  for the user's smoke.
- The previous 09:21 installed app is preserved at
  `build/Grañipa-pre-refactor-2026-09-04-0921.app`; the replacement is
  recoverable without rebuilding.
- Exact cold launch-to-ready is unmeasurable without adding instrumentation;
  the app has no ready signal/signpost, and the baseline had no signed-bundle
  measurement.
- One unmatched idle snapshot showed 43.1 MiB physical footprint for the new
  process versus 72.2 MiB for the old process. RSS was 91,040 KiB versus 83,712
  KiB, and thread count was 12 versus 9. The old process had run for two hours
  while the new one had run for two minutes, so these mixed figures do not prove
  a resource reduction. A controlled navigation/dictation/Record profile is
  still required.
- Controlled navigation/dictation/Record and physical battery-policy profiling
  remain pending; the available idle samples are not directly comparable.
- `gitleaks git . --log-opts='main..HEAD'` scanned 39 commits and approximately
  663.47 KB: zero leaks. The user explicitly authorized sharing with Grok, Kimi,
  and GLM.
- Grok `xreview --base main --family grok` completed with `VERDICT: ISSUES`.
  It found file-ASR fallback gaps after live failure/retry, system-audio format
  drift after a route change, an unbounded Muse handshake, swallowed transcript
  DB writes, missing client-side XPC peer validation, and a misleading no-op echo
  cancellation setting.
- Candidate fixes were deliberately not rushed into this checkpoint without a
  second-family review: `fix/live-transcription-recovery` at `4ab30eb`,
  `fix/system-audio-continuity` at `68a0e60`, and `fix/muse-xpc-hardening` at
  `0646a62`. Their worktrees were removed; the branches preserve the commits.
- The local macOS 26.5 SDK verifies that
  `NSXPCConnection.setCodeSigningRequirement(_:)` exists since macOS 13 and must
  be called before `resume`. No client-side helper requirement was integrated
  because the interrupted GLM attempt did not finish a safe implementation.
- “Echo cancellation (mic)” remains visible but meetings hard-code it off after
  the enabled path reproduced 134% CPU and repeated hangs. Changing that visible
  contract without a safe implementation is a proposal, not an optimization.
- No merge is authorized.

The following audited items were proposals only because they touch persisted
media/delivery, visible motion, external contracts, or lack a sufficient test or
profile: audio buffer/padding changes, orphan audio deletion, webhook
serialization/retention, hidden live-ASR removal, FluidAudio separation, icon
recompression, waveform frame-rate changes, EventKit refresh redesign, LLM
process cancellation/serialization, SMC target consolidation, broad Settings
splitting, clipboard prune timing, HTTP request-body shape, meeting-detector
stop state, and language-probe analyzer reuse.

## Commit groups

- Bugs: `eb6ce5f`, `8404721`, `fbe9b94`, `4037e7c`, `77ca895`.
- Post-review bugs: `30d18a1`, `b9a217b`, `58befb7`, `b79abfe`, `12e0c7c`,
  `b563be2`.
- Build tooling: `c61cd2a`.
- Runtime: `ee44877`, `6ccf1e8`, `4eb817f`, `7bcf07e`.
- Warning cleanup: `9f082ff`, `c5c4e84`, `5f0f7fd`.
- Dead code/tests: `a8b2d48`, `fcfc313`, `ab78eac`, `66ed3c7`,
  `4f6ac12`, `1cc9e60`, `248cffa`, `d987597`, `e9b1e61`, `02bb1d8`.
- Audit/plan: `e168bfc`, `cda719a`, `c552905`.
- Contract tests: `c423ab0`, `0fb4d09`.
