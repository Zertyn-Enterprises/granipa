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
  old-equivalent model 91.7 ms entry vs 84.8 ms full parse — i.e. entry cost
  the whole parse. (Arithmetic corrected from the first draft of this doc and
  from `21026b5`'s message, which quoted `entryNs × 8 = 733,799,672 ns` as if
  it were the entry time itself.) The new model passes `entry * 8 < full`
  with the prefix path; the boolean ratio test does not measure the new
  entry duration, only that it is well under an eighth of a full parse.
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

## Integrator audit round — lifecycle fixes (`5a678b4`)

Three findings on `a2e4beb`/`a4f97e6`, fixed in place (same actor design):

1. **Release on every load path.** `load(nil,nil)` and loading a missing path
   returned before any engine reset; a previously playing file stayed audible
   under an idle/failed facade. All abandoning paths now call `releaseEngine()`
   (main-actor delegate detach + chained `engine.reset()`); `stopAndRelease`
   reuses it; `openCurrentChannel` failures included.
   Red first, real audio: a 0.2 s tone played out after `load(nil,nil)` /
   `load(missing)` and its EOF callback flipped the facade to `.ended` —
   exact failing assertions:
   `(player.state → .ended) == .idle` and
   `(player.state → .ended) == (.failed(.missingFile)…)`. Both green after.
   Missing-file diagnostics stay synchronous; channel behavior covered by the
   untouched `channelSwitch…` test.
2. **Tick re-validation.** The tick's three engine awaits are not
   cancellable; it wrote `currentTime`/`duration` and could declare ended
   without re-checking cancellation/generation. `startTick` now captures the
   generation and re-validates `!Task.isCancelled, current == generation,
   state == .playing` after the awaits before publishing anything.
   `openCurrentChannel` cancels the tick (covers `selectChannel`).
3. **Tick after engine.play.** `play()` started the tick before the enqueued
   `engine.play`, so the tick's first `isPlaying` read could be served first
   and read as EOF. The tick starts only after `engine.play` succeeded for
   the same generation with still-playing intent; the button still flips
   immediately; a start that raced a generation change pauses what it should
   not have started (the queued replace resets it regardless).

Findings 2 and 3 are unguarded interleavings that usually resolve benignly —
their exact window is not reachable deterministically from the public API
(control-flow proof in the commit body), so coverage is the new 3-cycle rapid
play/pause/seek/channel/stop churn test plus five consecutive real-playback
suite runs, all green. The churn test also passes against the pre-fix tree;
it guards the fixed discipline, it is not the red evidence (finding 1's tests
are). The delegate-hop race window (EOF callback in flight across an abandon)
predates this lane and is unchanged; deliberately left unguarded so the
finding-1 tests keep their observable.

Post-fix gates: debug 372 tests / 65 suites; release 350 tests / 63 suites;
playback suite 5× green; format-lint warning profile identical to `ea6171e`
baseline; `git diff --check` clean; no new annotations or API surface.

## Grok screen-review reconciliation (follow-up round)

Review file: `docs/wip/2026-09-05-meeting-review-followup.md` (root-attached,
root's file — left uncommitted here). Verdict ISSUES; items and outcomes:

- Ticking before `engine.play`; nil/missing paths not releasing; stale async
  completions — overlap with the audit round, fixed in `5a678b4` above.
- **Missing-path channel change vs an in-flight replacement.** Covered by the
  same mechanism: `openCurrentChannel` bumps the generation (dropping the
  in-flight completion's publish) and chains `releaseEngine` after any queued
  `replace`, which resets whatever it created. Deterministic red found while
  testing this: `selectChannel` to a vanished file left `loadedURL` published
  after `.failed(.missingFile)` — `releaseEngine` now clears the loaded-file
  facade (`loadedURL`, `duration`, `currentTime`), `stopAndRelease` reuses it.
  New test `selectingAVanishedChannelFailsReleasesAndKeepsTheDiagnostic` was
  red against `771ef47` (both `.ended` clobber and stale `loadedURL`) and is
  green after. The interleaving where the previous `replace` is still queued
  is not deterministically reachable from the public API (the prepare window
  of a real file is ~1-10 ms); the generation/reset chaining that covers it
  is the same code the audit-round tests exercise.
- **AI Notes first frame / re-enhance flash.** `document.source` is now
  exposed; while it differs from the meeting's notes the view shows a real
  "Formatting notes…" row instead of an empty first frame or the previous
  source's blocks, until the prefix lands. No artificial delay; tab re-entry
  still hits the cache (source matches, no flash). View-level behavior — no
  UI test framework in this target, verified by the model's source-equality
  contract the view consumes.
- **LazyVStack nested in an eager VStack.** Unverified inference, flagged as
  such: SwiftUI's documented contract for lazy stacks is deferred child
  realization as they approach the viewport, and the eager parent only
  instantiates the container plus four card views — the thousands of row
  views remain the LazyVStack's children. This was NOT measured here (no app
  launch in this lane); root's live profiling should confirm row
  realization before/after, or the content can be flattened into one lazy
  list at that point.
- **EOF/channel test honesty.** EOF test now also restarts after `.ended`
  and requires real engine progress (catches a facade `.ended` over a dead
  player, and a missing tick at second play); the channel-switch test keeps
  playing a 0.3 s mic file across the switch and requires the facade to stay
  `.ready` past its natural EOF — the underlying stop is verified by the
  same EOF-observable mechanism as the release tests, not by UI flags alone.
  No assertion weakened; only additions.

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
