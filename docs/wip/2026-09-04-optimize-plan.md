# Grañipa safe optimization plan — 2026-09-04

Planned from the findings at `chore/optimize-2026-09-04@c10dbb8`.
Order is impact multiplied by confidence and divided by risk. Each numbered
item is one logical commit unless its verification fails; no item gets a third
implementation approach.

## Success criteria

1. Right Command starts and stops dictation in another app.
2. Clipboard History pastes once into the app that owned focus before its panel.
3. A Spanish meeting with `language=auto` and stale `lastSpeechLocale=en-US`
   selects Spanish before full-file transcription.
4. The supplied Battery XPC startup crash cannot recur on a non-main reply queue.
5. Grañipa's menu-bar label has no battery percentage or second battery state.
6. Build and all tests stay green after every commit; unique compiler warnings
   do not increase and reach zero for files changed by this plan.
7. Safe runtime work removes unnecessary CoreAudio property calls, redundant
   SwiftUI publishes, and repeat executable-path scans without changing output.
8. Phase 4 repeats the baseline commands, profiles a signed core flow, runs a
   different-family cross-review, and opens one PR.

## Execution queue

### 1. Recover the Battery XPC crash

- Finding: XPC invokes an actor-isolated error reply from its private queue.
- Change: explicitly wrap asynchronous UI replies onto `MainActor`; protect the
  synchronous termination reply with a small lock/semaphore result container.
- Risk: 🟡.
- Before proof: the supplied crash report is the red reproduction
  (`_swift_task_checkIsolatedSwift` on the XPC queue).
- After proof: targeted `BatteryHelperTests`, including a reply delivered from a
  global queue and timeout/duplicate-reply cases; full build/test gate.

### 2. Remove Grañipa's duplicate battery readout

- Finding: `MenuBarLabel` appends BatteryService text to Grañipa's own status
  icon while macOS already owns the native battery icon.
- Change: render only Grañipa state (`waveform`, mic, record, processing).
- Risk: 🟢; explicitly requested observable UI change.
- Before proof: baseline source and the user's screenshot show the extra text.
- After proof: source grep has no BatteryService/menuBarText in `MenuBarLabel`;
  build/tests; signed screenshot/smoke when signing is approved.

### 3. Restore modifier-only Right Command dictation

- Finding: the only callback resamples physical state after an asynchronous
  actor hop. Capturing `CGEventSource.keyState` earlier was already tried once
  and did not repair the signed app.
- Change: use one genuinely different, event-derived edge strategy after signed
  diagnostic logging proves monitor/trust/event delivery. Remove diagnostics
  before commit.
- Risk: 🟡.
- Before proof: add an edge-sequence test first and record its red result; the
  user's current signed smoke is also red.
- After proof: targeted hotkey/trigger tests, full gates, then TextEdit signed
  smoke: hold/release and quick-toggle each generate exactly one lifecycle.
- Budget: the failed early-keyState variant was approach 1. The next strategy is
  approach 2; if it fails, revert and report blocked rather than adding a hack.

### 4. Paste after Clipboard/Dictation History actually relinquishes focus

- Finding: paste delay is 140 ms but panel hide completion is 200 ms.
- Change: pass the existing `PanelMotion.disappear` completion through both
  history panel close paths and post Command-V from that completion; remove both
  fixed paste sleeps.
- Risk: 🟡.
- Before proof: current timing/source is the deterministic red condition and the
  user reproduced copy-without-paste.
- After proof: compile-time caller grep, PanelMotion completion test, full gates,
  and a signed TextEdit smoke that pastes once after the panel is no longer key.

### 5. Make meeting `auto` language detection real without Record-time CPU

- Finding: the file transcriber selects only candidate `[0]` and cannot correct
  stale `lastSpeechLocale`.
- Change: create a deterministic sequential probe plan for distinct language
  codes; transcribe a bounded mic prefix one locale at a time; choose through
  existing `LanguageDetection.decide`; transcribe each complete channel once.
  Keep persisted schemas/shapes unchanged.
- Risk: 🟡 for the selection/transcription flow. No schema migration.
- Before proof: add a plan test first: auto + stale English + English/Spanish
  probes must schedule both; it fails under the one-locale baseline policy.
- After proof: existing LanguageDetection tests, new explicit/auto/dedup tests,
  full gates, and an ephemeral-db smoke against a copy of the user's Spanish
  audio. Verify raw Spanish text before enhancement.

### 6. Remove existing compiler warnings

- Finding A: PanelMotion accesses AppKit main-actor APIs without actor isolation.
- Change A: isolate PanelMotion and its completion on `MainActor`.
- Finding B: MuseSystemTranscriber has four `await` expressions with no async
  operation.
- Change B: remove only those redundant awaits.
- Finding C: two tests declare immutable meetings as `var`.
- Change C: use `let`.
- Risk: 🟢.
- Proof per commit: clean build/test and warning-location recount; expected 26
  source locations plus two test locations before, zero in touched files after.

### 7. Filter MeetingDetector before expensive CoreAudio state reads

- Finding: `IsRunningInput` is queried for every audio process before matching
  known meeting bundles; cancelled detached work can publish once more.
- Change: read bundle, reject unknown bundles, then query input state and return
  at first active match; guard cancellation before applying.
- Risk: 🟢.
- Proof: all existing CalendarDetection tests; source-level caller/query grep;
  full gates. The mapping and first-active result remain identical.

### 8. Reduce safe Battery churn without weakening protection

- Finding: unchanged snapshots/temperatures are assigned every 5 s; temperature
  is attempted even with no battery; successful fallback temperature key is not
  remembered.
- Change in separate slices: guard no-battery before SMC temperature work;
  assign observable fields only when changed; remember the first valid SMC key
  and fall back to the full list if it stops working.
- Risk: 🟢 for the early guard/equality and cached-key fallback.
- Proof: ChargePolicy/BatteryHelper tests, clean full gates, and an idle signed
  sample. Charging actions and the 5 s protection cadence remain unchanged.
- Not in this execution: notification-driven IOPS and off-main SMC require an
  integration seam and are retained as a proposal.

### 9. Resolve LLM executable paths once per view evaluation

- Finding: Onboarding repeats path/PATH scans at least nine times per body;
  ProviderRow reads the computed scan four times.
- Change: bind each result once inside the existing view evaluation. Do not add
  a session cache, so installing a CLI remains observable on reevaluation.
- Risk: 🟢.
- Proof: final grep demonstrates one call per row evaluation; full gates.

### 10. Remove proven dead surfaces and no-op tests

- Change A: remove the unused LevelGate `level` parameter and migrate all three
  verified callers.
- Change B: remove discarded `MeetingGlyph.seed` and its sole caller argument.
- Change C: remove pure-Swift Theme tokens and methods with zero production
  callers (`brandGradient`, `spaceXS`, `spaceS`, `spring`,
  `WindowManager.registerHotkeys`, `HyperKeyMonitor.isRunning`).
- Change D: remove the no-assert Theme test and the weaker duplicate Muse policy
  test; retain every stronger assertion.
- Risk: 🟢.
- Proof per commit: pre/post whole-repo `rg`, build/test gates, and exact
  assertion comparison recorded in the audit.

## Second execution loop

The read-only second pass at `1cc9e60` found two additional 🟢 removals. They
are planned before any source edit; every other new finding remains a proposal.

### 11. Remove the unused image downsampling wrapper

- Finding: `ImageCache.downsampled` has zero static, string, or Objective-C
  selector callers; `loadDownsampled` remains the three-call implementation.
- Change: remove only the three-line wrapper.
- Risk: 🟢.
- Proof: pre/post whole-repo caller grep, build, and all tests.

### 12. Remove unreachable speech-model prewarming

- Finding: `prewarmPreferredLocales` has zero callers; `prewarmLocaleIDs` is
  reachable only from it and a test that duplicates four stronger assertions.
- Change: remove both methods and only the redundant prewarm test suite.
- Risk: 🟢.
- Proof: whole-repo static/string/selector grep, exact assertion comparison,
  build, and all remaining tests.

### Second-loop proposals only

- Prune clipboard retention only after insertion, after a real database test.
- Stop retaining unused HTTP request bodies, after an API contract test.
- Reset `meetingAppActive` in `stop()`, after a lifecycle regression test.
- Reuse or reduce language-probe analysis only after a real long-audio profile.

## Third execution loop

The property/type closure pass at `d987597` found the last two additional 🟢
surfaces. The exhaustive lexical sweep found no further safe zero-caller item.

### 13. Remove the unread battery power-source field

- Finding: `BatterySnapshot.isPluggedIn` is only declared and initialized.
- Change: remove the field, its two initializer arguments, and the IOPS state
  locals used only to populate it.
- Risk: 🟢.
- Proof: whole-repo member/string/selector/reflection grep, build, and all tests.

### 14. Remove unread stderr from successful LLM results

- Finding: every successful-result consumer reads only `.stdout`; stderr is
  still drained and still included in non-zero-exit errors.
- Change: remove only `Output.stderr` and its constructor argument.
- Risk: 🟢.
- Proof: whole-repo consumer grep, existing process tests, build, and full suite.

## Proposals only — not executed

These are 🔴 or lack a test/profile that can prove behavior preservation:

- Coalesce/drop or change audio writer/padding behavior.
- Delete orphan meeting audio or add a storage migration/retention policy.
- Serialize/deduplicate webhooks or migrate their indexes/retention.
- Remove hidden live meeting ASR.
- Remove/separate FluidAudio or recompress visual assets.
- Reduce the dictation waveform frame rate or visual motion.
- Rewrite calendar refresh around EventKit notifications.
- Serialize/cancel LLM subprocess jobs.
- Consolidate app/helper SMC implementations across the privilege boundary.
- Split the 1,134-line SettingsView solely for style.
- Change release/notarization scripts.

Each remains documented with the exact confirming profile/test in the audit.

## Phase 4 gate

Repeat the exact baseline commands and tabulate before/after for LOC, files,
dependencies, SwiftPM/build artifacts, clean build wall time, full-test wall
time, warning count, and signed app size/startup/resource samples. Run a signed
end-to-end smoke for launch, navigation, Right Command dictation, Clipboard
History paste, meeting Record/Stop/language, and Battery UI. Run
`xreview --base main` with a non-Codex family, address its verdict, push this one
branch, and open one PR without merging it.
