# Grañipa optimization audit — 2026-09-04

Audited commit: `chore/optimize-2026-09-04@c10dbb8`

This phase changed no production or test code. Findings below distinguish
verified evidence from inference. Line numbers refer to `c10dbb8`.

## Functional regressions reported by the user

- [correctness] `Sources/Granipa/System/HotkeyManager.swift:136-149`
  Qué: modifier-only events jump to `MainActor` before reading physical key
  state; a completed tap can be observed only as "up" and lose both edges.
  Acción: refactorizar; diagnose the signed process, then feed the callback's
  event state into the existing transition state instead of sampling later.
  Impacto: alto (Right Command dictation is currently unusable).
  Riesgo: 🟡 refactor con tests.
  Evidencia: `rg -n 'handleFlagsChanged|dispatchModifier|keyState' Sources Tests`
  shows the only modifier path and no edge-transition test. The delayed read is
  Verificado; whether it is the only live failure is Inferencia, confirmar con
  signed-app event logging because the first attempted early-keyState fix did
  not restore the shortcut.

- [correctness] `Sources/Granipa/System/PasteService.swift:19-35`,
  `Sources/Granipa/Clipboard/ClipboardHistoryView.swift:295-306`, and
  `Sources/Granipa/System/PanelMotion.swift:46-64`
  Qué: Clipboard publishes Command-V after 140 ms while its keyable panel stays
  visible for a 200 ms hide animation; the panel can still receive the paste.
  Acción: refactorizar; paste from the existing disappear completion.
  Impacto: alto (Clipboard History copies but does not paste).
  Riesgo: 🟡 refactor con tests.
  Evidencia: `rg -n 'milliseconds\(140\)|hideDuration|makeKey: true|pasteToFrontmostApp' Sources`
  — Verificado. PasteService returning true means "events posted", not "target
  mutated" — Verificado from its implementation.

- [correctness] `Sources/Granipa/Transcription/FileMeetingTranscriber.swift:15-27`
  and `Sources/Granipa/Transcription/LanguageDetection.swift:44-55`
  Qué: automatic post-record transcription runs one locale only, preferring
  `lastSpeechLocale`; real defaults are probes `en-US,es-ES,es-US` and last
  `en-US`, so a Spanish meeting was processed with `en-US` and cannot recover.
  Acción: refactorizar; probe a bounded mic prefix sequentially, select through
  existing `LanguageDetection.decide`, then transcribe each full channel once.
  Impacto: alto (wrong-language raw transcript and generated notes).
  Riesgo: 🟡 refactor con tests; do not change schema or stored shapes.
  Evidencia: `defaults read com.zertyn.granipa` returned `dictationLocale=es-ES`,
  `lastSpeechLocale=en-US`, and `probeLocales=en-US,es-ES,es-US`; source grep
  shows `[0]` is the sole candidate — Verificado. The user's affected meeting
  being English before LLM enhancement was verified read-only by the audio
  audit.

- [correctness] `Sources/Granipa/System/BatteryHelperClient.swift:107-131`
  Qué: an actor-isolated XPC error callback executes on the private XPC reply
  queue and traps in Swift 6 isolation checking.
  Acción: refactorizar; make XPC callbacks sendable and explicitly deliver UI
  state back to `MainActor`.
  Impacto: alto (verified startup crash).
  Riesgo: 🟡 refactor con tests.
  Evidencia: supplied crash thread 2 is
  `com.apple.NSXPCConnection...batteryhelper` and ends at
  `BatteryHelperClient.proxy(reply:)` via `_swift_task_checkIsolatedSwift` —
  Verificado.

## Runtime and responsiveness

- [runtime] `Sources/Granipa/System/BatteryService.swift:79-122` and
  `Sources/Granipa/System/BatteryService.swift:271-279`
  Qué: the app always wakes every 5 s on `MainActor`, reads IOPS, attempts up to
  four synchronous SMC temperature keys, applies LED policy, and republishes
  values even when unchanged.
  Acción: refactorizar in safe slices: skip SMC without a battery, avoid equal
  publishes, then propose an IOPS notification source plus policy-only timer.
  Impacto: alto (720 IOPS polls/hour and up to 2,880 temperature-key attempts/hour).
  Riesgo: 🟡 refactor con tests for scheduling; the two early exits/equality
  assignments are 🟢.
  Evidencia: `rg -n 'BatteryService.shared.start|seconds\(5\)|readTemperature|tempKeys' Sources`
  and direct source inspection — Verificado. A UI hang caused by a slow SMC call
  is Inferencia, confirmar with an Instruments time profile.

- [runtime] `Sources/Granipa/Detection/MeetingDetector.swift:35-45` and
  `Sources/Granipa/Detection/MeetingDetector.swift:73-104`
  Qué: every 5 s it asks `IsRunningInput` for every CoreAudio process, then
  filters for the eleven known meeting bundle prefixes; a cancelled detached
  read can also publish one final result.
  Acción: refactorizar; filter bundle IDs before the input-state call, return on
  first match, and guard cancellation after the detached read.
  Impacto: medio (fewer CoreAudio property calls and allocations every poll).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `nl -ba Sources/Granipa/Detection/MeetingDetector.swift | sed -n '35,105p'`
  — Verificado.

- [runtime] `Sources/Granipa/AppState.swift:242-250`
  Qué: a webhook task wakes every 30 s even with zero webhooks; current data has
  zero webhooks, so all 120 wakeups/hour are no-ops.
  Acción: refactorizar only with a lifecycle test; wake on enqueue/next due time.
  Impacto: bajo currently, medio when retry payloads exist.
  Riesgo: 🟡 refactor con tests.
  Evidencia: `rg -n 'webhookLoop|deliverDue|seconds\(30\)' Sources/Granipa/AppState.swift`
  and read-only database count from the services audit — Verificado.

- [correctness/runtime] `Sources/Granipa/API/WebhookService.swift:25-39` and
  `Sources/Granipa/AppState.swift:243-246,452-461,520-526`
  Qué: three concurrent callers can read the same due row before either marks
  it delivered, producing duplicate POSTs; delivered/failed payload rows have
  no retention policy.
  Acción: proponer a single serialized worker and an explicit retention policy.
  Impacto: medio (duplicate network work and unbounded persisted payloads).
  Riesgo: 🔴 toca entrega externa y persistencia.
  Evidencia: `rg -n 'deliverDue|dueDeliveries|updateDelivery' Sources Tests`
  — concurrency window and missing delete/prune caller Verificado. A duplicate
  POST in production is Inferencia, confirmar with a delayed local HTTP test.

- [runtime] `Sources/Granipa/Calendar/CalendarService.swift:44-96`
  Qué: EventKit access is requested eagerly and event fetching/sort run on
  `MainActor` every 300 s, although the SDK exposes event-store change
  notifications.
  Acción: proponer notification-driven refresh and off-main transformation,
  preserving an explicit permission flow and a long fallback timer.
  Impacto: medio (periodic main-thread I/O and twelve wakeups/hour).
  Riesgo: 🟡 refactor con integration test.
  Evidencia: source inspection and
  `rg -n 'EKEventStoreChangedNotification'` in the installed macOS SDK — API
  availability Verificado. Actual navigation stalls from EventKit are
  Inferencia, confirmar with Instruments.

- [runtime] `Sources/Granipa/Audio/RecordingSession.swift:247-310`
  Qué: every mic/system callback calculates RMS, deep-copies a complete PCM
  buffer, and enqueues it on an unbounded serial writer queue; source production
  is not back-pressured.
  Acción: proponer instrumentation of queue depth first, then bounded coalescing
  only if a recording profile confirms this path.
  Impacto: alto during Record.
  Riesgo: 🔴 audio loss/timeline is a core persisted contract.
  Evidencia: `nl -ba Sources/Granipa/Audio/RecordingSession.swift | sed -n '247,311p'`
  — operations and absence of a bound Verificado. This being the remaining
  100% CPU source is Inferencia, confirmar with `sample <pid> 5` while recording.

- [runtime/duplication] `Sources/Granipa/Audio/RecordingSession.swift:273-282`
  and `Sources/Granipa/Audio/RecordingSession.swift:329-344`
  Qué: two loops materialize silence as newly allocated 16,384-frame buffers;
  long gaps perform repeated synchronous allocation and AAC writes.
  Acción: proponer a reusable zero buffer or deferred bounded padding after a
  real audio fixture locks exact duration.
  Impacto: alto for long device/system gaps.
  Riesgo: 🔴 audio timeline and persisted media.
  Evidencia: the two source loops are Verificado. Runtime dominance is
  Inferencia, confirmar with recording sample/counters.

- [runtime] `Sources/Granipa/Dictation/DictationOverlayView.swift:161-219` and
  `Sources/Granipa/Dictation/DictationController.swift:168-174`
  Qué: the Canvas redraws at 30 fps while waveform samples arrive at at most
  12.5 Hz, constructing gradients, arrays, and 144 points each frame.
  Acción: proponer a change-driven Canvas or profile a 15 fps design with the
  user; do not reduce motion silently.
  Impacto: medio while dictating.
  Riesgo: 🔴 visible animation contract explicitly matters to the user.
  Evidencia: `rg -n 'TimelineView|minimumInterval|LevelGate\(minInterval' Sources`
  — rates Verificado. CPU cost is Inferencia, confirmar with Instruments.

- [runtime] `Sources/Granipa/LLM/LLMProviders.swift:59-73`,
  `Sources/Granipa/UI/OnboardingView.swift:82-102`, and
  `Sources/Granipa/UI/SettingsView.swift:473-502`
  Qué: a single view evaluation repeatedly scans candidate paths and PATH;
  Onboarding calls it at least nine times and a ProviderRow reads it four times.
  Acción: refactorizar; resolve once per body evaluation without session-stale
  caching.
  Impacto: bajo (less synchronous filesystem work during navigation).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n 'resolveExecutable|installedPath' Sources/Granipa/UI Sources/Granipa/LLM`
  — Verificado.

- [runtime] `Sources/Granipa/LLM/LLMRunner.swift:49-149` and
  `Sources/Granipa/AppState.swift:467-519`
  Qué: different meetings can launch multiple CLI subprocesses; Swift task
  cancellation does not terminate the process, and prompt build/JSON salvage
  run on `MainActor`.
  Acción: proponer cancellation propagation and a serialized job owner before
  moving pure prompt/parse work off-main.
  Impacto: medio to alto during enhancement.
  Riesgo: 🟡 refactor con process/integration tests.
  Evidencia: `rg -n 'Process\(|group.wait|enhancingMeetingIDs|buildPrompt|parseResponse' Sources`
  — code paths Verificado. User-visible stalls/concurrent live CLIs are
  Inferencia, confirmar with cancellation and two-meeting smoke tests.

## Loading and dependencies

- [dependencies] `Package.swift:7-11` and production imports
  Qué: all three direct dependencies have verified callers; none is removable
  as unused. FluidAudio has one production import and is linked for optional
  post-meeting diarization.
  Acción: proponer measuring a release link map before considering target
  separation; do not remove or replace it.
  Impacto: potentially high bundle/startup, unmeasured.
  Riesgo: 🔴 removing it changes a shipped feature.
  Evidencia: `rg -n '^import (GRDB|FluidAudio|Sparkle)$' Sources Tests` — imports
  Verificado. FluidAudio's attributable binary size is Inferencia, confirmar
  with a release link map.

- [load] `Resources/AppIcon.icns`
  Qué: the 1.6 MiB icon is about 85% of the 1,884 KiB Resources directory.
  Acción: proponer inspecting icon representations and visual equality before
  recompression.
  Impacto: bajo (disk/download only; not proven resident).
  Riesgo: 🟡 visual asset change needs render comparison.
  Evidencia: `du -sk Resources/* | sort -n` — size Verificado. Memory effect is
  not claimed.

## Duplication and overengineering

- [duplication] `Sources/Granipa/Clipboard/ClipboardPanelController.swift:4-73`
  and `Sources/Granipa/Dictation/DictationHistoryPanelController.swift:4-73`
  Qué: keyable panel type, lifecycle, delegate, animation, and host replacement
  are line-for-line duplicates except content, dimensions, and origin.
  Acción: proponer; their current size is cheaper than a generic controller with
  one-caller flags. Reuse only the paste-dismiss completion needed by the bug.
  Impacto: bajo (maintenance; host recreation is small navigation work).
  Riesgo: 🟡 refactor with UI lifecycle tests.
  Evidencia: `diff -u` between both files — Verificado.

- [duplication] `Sources/Granipa/System/SMCClient.swift` and
  `Sources/BatteryHelper/HelperSMC.swift`
  Qué: the 80-byte SMC struct plus open/read/write/call protocol is duplicated,
  but one copy belongs to the app target and one to the privileged executable.
  Acción: proponer no consolidation now; a shared target would add packaging and
  privilege-boundary complexity for negligible runtime gain.
  Impacto: bajo (maintenance only).
  Riesgo: 🔴 privileged helper boundary.
  Evidencia: `diff -u Sources/Granipa/System/SMCClient.swift Sources/BatteryHelper/HelperSMC.swift`
  — shared blocks and intentional divergences Verificado.

- [overengineering] `Sources/Granipa/Transcription/MeetingASRPolicy.swift`,
  `Sources/Granipa/AppState.swift:333-350`, and live coordinator fan-out state
  Qué: an extensive live-meeting ASR path is controlled only by an undocumented
  `UserDefaults("liveMeetingASR")`; no UI writer exists and default is false.
  Acción: proponer a product decision. Do not delete because external defaults
  can enable it and it is a real behavior.
  Impacto: alto LOC/complexity, zero default runtime after Record begins.
  Riesgo: 🔴 hidden observable feature.
  Evidencia: `rg -n 'liveMeetingASR' Sources Tests README.md` shows reads/tests
  and no production writer — Verificado. External use is unknown.

- [overengineering] `Sources/Granipa/UI/SettingsView.swift:1-1134`
  Qué: one file contains 18 routing/section/editor view types.
  Acción: proponer splitting only on existing section seams; it does not itself
  prove runtime cost.
  Impacto: medio maintainability, unverified runtime.
  Riesgo: 🟡 broad UI refactor.
  Evidencia: `wc -l` and
  `rg -n '^(private )?(struct|enum)' Sources/Granipa/UI/SettingsView.swift` —
  Verificado.

## Dead code and tests

- [dead code] `Sources/Granipa/UI/Theme.swift:21-26,43-44,60`,
  `Sources/Granipa/System/WindowManager.swift:14-16`, and
  `Sources/Granipa/System/HyperKeyMonitor.swift:21-25`
  Qué: `brandGradient`, `spaceXS`, `spaceS`, `spring`, `registerHotkeys`, and
  `isRunning` have no production caller; some survive only through token tests.
  Acción: eliminar each verified unused surface and its assertion in separate,
  green cleanup slices.
  Impacto: bajo (LOC/maintenance; negligible runtime).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n -w 'brandGradient|spaceXS|spaceS|spring|registerHotkeys|isRunning' Sources Tests`
  returns only definitions and the named Theme tests — Verificado. Dynamic
  Objective-C selectors are not involved because these declarations are pure
  Swift and not `@objc`.

- [dead parameter] `Sources/Granipa/Audio/LevelGate.swift:13-21`
  Qué: `level` is accepted but never read; two production callers and one test
  pass it.
  Acción: eliminar the parameter and migrate all three verified callers.
  Impacto: bajo (clarity; no meaningful runtime allocation).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n 'shouldPublish\(' Sources Tests` plus function body —
  Verificado.

- [dead parameter] `Sources/Granipa/UI/MeetingSparkline.swift:47-53`
  Qué: `MeetingGlyph.seed` is explicitly discarded; its sole caller passes a
  meeting ID that has no visual effect.
  Acción: eliminar parameter and migrate the sole caller.
  Impacto: bajo.
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n 'MeetingGlyph|let _ = seed' Sources Tests` — Verificado.

- [tests de sobra] `Tests/GranipaTests/ThemeTests.swift:25-28,32-44`
  Qué: assignments only prove symbols type-check; `colorTokensExist` has no
  assertion and can never fail from behavior.
  Acción: eliminar no-op statements/test; retain behavioral token contracts.
  Impacto: bajo (simpler suite).
  Riesgo: 🟢 no behavioral coverage removed.
  Evidencia: direct inspection shows no `#expect`/`#require` in the test —
  Verificado.

- [tests de sobra] `Tests/GranipaTests/DictationTests.swift:86-90` and
  `Tests/GranipaTests/MeetingASRPolicyTests.swift:9-18`
  Qué: the dictation-suite case repeats the same three Muse policy inputs that
  the dedicated policy suite covers, while the latter also covers nil/empty.
  Acción: eliminar the weaker duplicate from `DictationTests`.
  Impacto: bajo.
  Riesgo: 🟢 equivalent or stronger assertions remain.
  Evidencia: direct assertion comparison — Verificado.

- [inconsistency] `Sources/Granipa/UI/SettingsView.swift:312` versus
  `Sources/Granipa/Transcription/FileMeetingTranscriber.swift:15-18`
  Qué: Settings says meetings probe languages, while the default file path
  starts exactly one locale.
  Acción: refactorizar the implementation for real bounded probes; do not weaken
  the UI promise to hide the regression.
  Impacto: alto correctness.
  Riesgo: 🟡 with deterministic planning tests and an audio smoke.
  Evidencia: UI string and `[0]` code path — Verificado.

## Storage, scripts, and safety proposals

- [storage] `Sources/Granipa/AppState.swift:627-638`
  Qué: deleting a meeting removes database state but not its audio directory;
  a read-only inventory found 11 audio directories with no meeting row.
  Acción: proponer explicit product-approved deletion and orphan recovery.
  Impacto: alto disk use (current audio root was 266 MiB).
  Riesgo: 🔴 destructive persisted-data behavior.
  Evidencia: absence of `removeItem` in `deleteMeeting` and read-only inventory
  are Verificado. The 11 directories being caused by this exact flow is
  Inferencia, confirmar by reproducing a meeting deletion against a copy.

- [script] `Scripts/bundle.sh` and `Scripts/release.sh`
  Qué: neither supports `--help`/`--dry-run`; release performs signing,
  notarization, ZIP replacement, Archive Utility launch, and appcast generation.
  Acción: proponer safe `--check` modes in a separate tooling task; do not alter
  release behavior during runtime optimization.
  Impacto: bajo runtime, medio release safety.
  Riesgo: 🟡 release workflow.
  Evidencia: both scripts read in full and `bash -n` exits 0 — Verificado.

- [security] `Sources/Granipa/System/AppRelocator.swift:63-70`
  Qué: a path is interpolated into `/bin/sh -c`; exploitability depends on
  whether an attacker can control the bundle path.
  Acción: proponer a separate security fix using direct process arguments.
  Impacto: security, not resource usage.
  Riesgo: 🔴 install/move behavior.
  Evidencia: shell interpolation Verificado. A reachable injection is Inferencia,
  confirmar with a signed bundle in a path containing shell metacharacters.

## Confirmed negatives

- No unused direct dependency was found.
- No `.skip`, `XCTSkip`, disabled test, tracked build artifact, `.bak`, `.orig`,
  `.tmp`, `.old`, `.DS_Store`, `TODO`, `FIXME`, debug `print`, or `debugPrint`
  was found in source/tests/scripts.
- `HomeView` already uses lazy stacks; no unvirtualized production list was
  identified.
- The 55 files under `docs/wip/` are already in the required ephemeral-doc
  location and do not affect runtime.

## Second pass after the first execution queue

Audited commit: `chore/optimize-2026-09-04@1cc9e60`. This pass was read-only;
the findings below were independently rechecked before being added here.

- [dead code] `Sources/Granipa/Clipboard/ImageCache.swift:82-84`
  Qué: `ImageCache.downsampled` only unwraps `loadDownsampled` and has zero
  callers; the private implementation has three live callers.
  Acción: eliminar.
  Impacto: bajo (maintenance only).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n -w 'downsampled|loadDownsampled' Sources Tests Resources Package.swift`
  returns one definition for the wrapper and three live calls to the private
  implementation — Verificado. String and Objective-C selector searches also
  return zero dynamic references — Verificado.

- [dead code/tests de sobra] `Sources/Granipa/Transcription/SpeechModels.swift:24-39`
  and `Tests/GranipaTests/SpeechGateTests.swift:70-80`
  Qué: `prewarmPreferredLocales` has zero callers; its helper is called only by
  that dead method and one test whose four cases duplicate
  `LanguageDetectionTests.startLocalesUsesOneAnalyzer`.
  Acción: eliminar both methods and the redundant suite.
  Impacto: bajo (less dead concurrency/download code and test surface; zero
  current runtime because the entry point is unreachable).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n -w 'prewarmPreferredLocales|prewarmLocaleIDs' Sources Tests Resources Package.swift`
  plus line-by-line assertion comparison at
  `LanguageDetectionTests.swift:96-109` — Verificado. String and Objective-C
  selector searches return zero dynamic references — Verificado.

- [runtime] `Sources/Granipa/Clipboard/ClipboardMonitor.swift:57-75,82-152`
  and `Sources/Granipa/Storage/AppDatabase.swift:190-200`
  Qué: every changed pasteboard value runs a retention fetch/delete transaction,
  including duplicate text or image values that return before insertion.
  Acción: proponer returning an insertion result and pruning only after a
  successful insert, with a real database retention test first.
  Impacto: medio (avoids an offset fetch/write transaction on duplicate copies).
  Riesgo: 🟡 changes retention timing and lacks an insertion-outcome test.
  Evidencia: the three unconditional `Self.prune` calls and both early duplicate
  returns are visible in the named lines — Verificado.

- [load/runtime] `Sources/Granipa/API/HTTPMessage.swift:3-8,25-60` and
  `Sources/Granipa/API/APIServer.swift:64-92`
  Qué: the server buffers up to 4 MiB and then copies the request body into
  `HTTPRequest`, while no production route reads `HTTPRequest.body`.
  Acción: proponer preserving Content-Length framing without retaining a second
  body copy, after locking the internal request contract with an integration test.
  Impacto: medio for large local API requests.
  Riesgo: 🟡 changes a shared parser shape currently asserted by a test.
  Evidencia: `rg -n '\.body\b|body:' Sources/Granipa/API Tests/GranipaTests/APITests.swift`
  shows the request-body write and one test read, but no production read —
  Verificado.

- [correctness] `Sources/Granipa/Detection/MeetingDetector.swift:51-56`
  Qué: `stop()` clears `detectedApp` and `lastActive` but leaves
  `meetingAppActive` at its previous value.
  Acción: proponer a lifecycle regression test before resetting the flag.
  Impacto: bajo.
  Riesgo: 🟡 observable state change without current lifecycle coverage.
  Evidencia: declaration, sole write, stop body, and sole reader were compared
  with `rg -n -w 'meetingAppActive' Sources Tests` — Verificado.

- [runtime] `Sources/Granipa/Transcription/FileMeetingTranscriber.swift:42-60,93-160`
  Qué: auto mode analyzes the 15-second prefix once per probe locale and then
  analyzes the full channel, so default two-locale operation reads the prefix
  three times; three configured languages read it four times.
  Acción: proponer measuring the new correctness path on longer real meetings
  before changing analyzer reuse or selection.
  Impacto: medio during post-record transcription.
  Riesgo: 🔴 meeting transcript correctness is a core persisted output.
  Evidencia: sequential probe loop and later full-channel call are present in
  the named lines — Verificado. Dominance on real workloads is an Inferencia;
  confirmar with a post-Stop time profile.

Second-pass negative sweep: zero `TODO`, `FIXME`, `HACK`, `XXX`, `print`,
`debugPrint`, `dump`, or `NSLog` occurrences in `Sources`, `Tests`, `Scripts`,
`Package.swift`, and `Resources` — Verificado with `rg`.

## Property and type closure pass

Audited commit: `chore/optimize-2026-09-04@d987597`. The prior zero-caller
scan covered functions; this read-only closure pass checked stored/computed
properties and type declarations as a separate category.

- [dead field] `Sources/Granipa/System/BatteryIO.swift:8,13,44-45,52`
  Qué: `BatterySnapshot.isPluggedIn` is declared and initialized but never read;
  its two IOPS parsing locals exist only to initialize that field.
  Acción: eliminar the field, both memberwise arguments, and both parsing locals.
  Impacto: bajo (one less dictionary lookup and smaller snapshot state every 5 s).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n -w 'isPluggedIn' Sources Tests Resources Package.swift`
  returns only declaration/initialization, while searches for `.isPluggedIn`,
  strings, reflection, selectors, and `Codable` return zero readers — Verificado.

- [dead field] `Sources/Granipa/LLM/LLMRunner.swift:44-46,138-148`
  Qué: `LLMRunner.Output.stderr` is initialized but never read; the local
  `stderr` must remain to drain the pipe and construct non-zero-exit errors.
  Acción: eliminar only the output field and constructor argument.
  Impacto: bajo (smaller result contract; pipe/error behavior unchanged).
  Riesgo: 🟢 sin comportamiento observable.
  Evidencia: `rg -n 'LLMRunner\.run|\.stdout\b|\.stderr\b|Output\(' Sources Tests`
  finds all output consumers reading only `.stdout`; string/selector/reflection
  searches find no dynamic field use — Verificado.

Closure sweep result: 405 function names and 228 type declarations were
checked. After excluding three `NSApplicationDelegate` callbacks and synthesized
`CodingKeys`, no further zero-caller function, property, or type was verified as
safe to remove. This is a lexical/caller audit, not a claim that profiling can
find no further runtime optimization.
