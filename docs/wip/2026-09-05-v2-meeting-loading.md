# V2 meeting navigation/loading — 2026-09-05

GLM implementation lane `fix/v2-meeting-loading`, base `feat/granipa-v2@ea6171e`.
Codex profiles/integrates; Grok reviews the finished screen. All measurements
below were run in this session on synthetic content only; no private meeting
or transcript content appears in any log.

## Baseline (verified this session)

- `swift build`: complete, 0 warnings.
- `swift test` (debug): 355 tests / 62 suites pass, 1.560 s.
- No PLAN.md/NOTAS.md in the worktree; AGENTS.md read before editing.

## Commits (one logical change each)

| Commit | Change |
|---|---|
| `4f0ac2d` | refactor: extract `MeetingDetailView.initialTab(for:preferNotes:)` (pure, behavior-preserving) |
| `8c15490` | default tab Overview for every normal entry; Notes-library `preferNotes` route keeps Notes |
| `8546a25` | `MeetingTranscriptModel`: off-main load, truthful loading/failed/retry, stale-load guard, last-good rows kept during rename refresh |
| `21026b5` | `EnhancedNotesDocument`: 30-block prefix synchronously, full parse detached, source-keyed cache; `MarkdownBlocksView` renders pre-parsed blocks in `LazyVStack` |
| `a2e4beb` | `PlaybackEngine` actor owns `AVAudioPlayer`; controller is a MainActor facade; `.preparing` state; spinner in the transport slot |
| `a4f97e6` | pause freezes the clock at the last tick (flake fix, same class as `a35670f`) |
| `1124455` | test formatting to match repo style |

## Red/green evidence (exact failing assertions)

- Default tab: tests written after the pure extraction, run against the
  pre-change decision → red:
  `initialTab(for: recorded, preferNotes: false) → .transcript) == .overview`,
  `…(bare…) → .notes) == .overview` (4 issues / 2 of 3 tests). After the flip:
  2 tests pass. `notesLibraryRouteStillLandsOnNotes` is green by construction
  (regression guard).
- Transcript model: implemented first as the swallow-as-`[]` equivalent of the
  old `loadSegments`, tests run red (3 of 5):
  - stale clobber: `model.phase → .loaded([… text: "slow stale row" …])) == (.loaded([fast])…`
  - failure swallowed: `timed out waiting for a failed phase` (phase stayed `.loaded([])`)
  - retry-after-failure: same timeout. Real-DB path and empty-is-not-failure
    passed in both versions (regression guards).
  After the generation guard + error propagation: 5/5 green.
- AI Notes document: implemented first as the sync full-parse equivalent → red
  (2 of 6): `!((document).isComplete → true)` and
  `blocks.count → 50002) == (previewBlockLimit → 30)`; timing test
  `entryNs * 8 → 733799672) < (fullNs → 84840000)` failed (entry ≈ full parse).
  After prefix/detached/cache: 6/6 green.
- Audio: `loadReturnsBeforePreparationBlocksTheMainActor` run with the three
  changed source files temporarily reverted to HEAD: red with
  `(player.state → .ready) != .ready`; the four pre-existing playback tests
  pass unchanged against the old controller in their awaited form. After the
  engine actor: 7/7 green.

## Measurements

- `AVAudioPlayer(contentsOf:)` + `prepareToPlay()`, 60-minute mono AAC (10 MB),
  generated this session: round 1 = 14 ms + 135 ms; warm rounds ≈ 15 + 10 ms.
  The old open path paid round-1 numbers synchronously on the main actor per
  open/channel switch; slow disks make it unbounded.
- AI-notes entry vs full parse (20k filler lines, min of 3, debug tests):
  old-equivalent model 733.8 ms entry vs 84.8 ms full parse; new model passes
  `entry * 8 < full` with the prefix path.
- Vendor docs checked: Apple documents `AVAudioPlayer` as Sendable
  (Conforms To, current docs), but the installed macOS SDK interface does not
  expose it — compile probe under Swift 6 strict concurrency fails. Hence
  actor ownership instead of a detached handoff; no `@unchecked Sendable`,
  `@preconcurrency`, or `nonisolated(unsafe)` added (the pre-existing
  `PlaybackDelegateBox` hop is reused verbatim).

## Gates

- Debug full suite on final tree: 369 tests / 65 suites pass. Five consecutive
  runs green after the pause-clock fix (one earlier run had flaked: the pause
  assertion's 0.05 s bound vs one tick period of staleness).
- Release suite: 347 tests / 63 suites pass (final-tree run recorded in the
  session log; delta vs debug is DEBUG-only fixture tests).
- `swift format lint --configuration '{"indentation":{"spaces":4}}'` on the
  eight changed files: warning profile identical to the same files at `ea6171e`
  after fixing two new-format warnings in the new test code; unrelated
  pre-existing style warnings were not reformatted.
- `git diff --check`: clean. No schema/API/identity/preference changes; no
  dependencies added.

## Remaining caveats

- Live UI frame-rate was not measured here (root profiles in parallel).
- The EOF delegate callback retains the pre-existing theoretical race against
  an immediately following `load` (MainActor hop unordered vs the state
  overwrite); same window existed before this lane, not widened.
- A failed *refresh* while rows are on screen keeps the last-good rows without
  an inline error (no flash of emptiness); first-load failures show the full
  error/retry state. Surfacing refresh errors non-modally is a product call.
- During `.preparing` the audio clock shows 0:00 and controls are disabled —
  truthful, but the previous audio (if a channel/path change interrupts
  playback) stops only when the engine command chain reaches `replace`.
