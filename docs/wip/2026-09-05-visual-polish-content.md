# V2 polish — content loading and live inspector (lane `fix/v2-polish-content`)

Scope: `Dictation/DictationHistoryView.swift`, `UI/InspectorViews.swift`, their tests.
Base `d54906e`; rebased onto shared shell `33e655b` (review commit `b6bd875`,
followups below). Shared Theme/Chrome/Shell untouched (Grok's lane). No schema,
preferences, audio or behavior changes beyond the states described below.

## History list: truthful load lifecycle

Problem: the first render showed the empty state and zeroed metrics before the
first fetch answered; a failed refresh replaced good rows with the full-screen
error; a straggler fetch for a superseded query could land rows from an old
search; nothing was cancelled on disappear.

Fix: `DictationLibraryModel` (value type, no I/O) owns the lifecycle —
`begin/succeed/fail/abandonInFlight/appendPage/removeEntry` — and the view
renders only what it derives:

- First load: centered "Loading history…" and "—" stat cards of the real
  grid's shape. Zeros never pose as measured data.
- Refresh (rows on screen): rows, stats and paging cursor stay; a slim
  "Updating results" indicator runs while the fetch is in flight. Old-query
  rows never silently pretend to be the new search's results.
- Refresh failure: inline "Couldn't refresh — showing previous results" with
  Retry. The full-screen error appears only when no snapshot has ever applied.
- Straggler guard: `succeed`/`fail` accept only the in-flight query; snapshots
  for superseded queries are dropped.
- `onDisappear` cancels the load task and the search debounce.
- Paging unchanged: `pageQuery(applied:current:)` gate and keyset cursor kept;
  `loadMore` calls `abandonInFlight()` so cancelling a pending reload for a
  page can't leave the refresh flag stuck.
- Empty-state guidance updated to the real gesture contract: tap toggles,
  hold talks (matches `DictationTrigger`'s 0.22 s threshold).

Deviation noted: with `app.database == nil` the database is missing, which is
an error state; reload records a failure (retryable) instead of silently
showing an empty library. No claim is made here about how reachable that
state is.

### Test evidence (RED first)

The model was first extracted carrying the pre-change view semantics
(behavior-preserving; existing suites stayed green), then the new contract
tests were run against it and failed — 6 of 7 — on exactly the new behaviors:
phantom empty state, phantom zero stats, straggler overwrite (3 rows applied
where 2 were on screen), refresh failure dropping rows to the full-screen
error, missing inline refresh error, retry not re-entering loading. The
implementation then turned them green. Snapshots come from a real ephemeral
`AppDatabase(writer: DatabaseQueue())`; nothing is mocked.
`deletingAShownRowAdjustsTheShownCount` guards pre-existing behavior and was
green by construction.

## Live inspector

### Elapsed-clock runaway (confirmed and fixed)

`.task(id: phase)` is cancelled by SwiftUI on disappear, but the controller is
app-scoped and can still be `.listening`; the old loop
(`while active { now = .now; try? await Task.sleep(500ms) }`) swallowed the
`CancellationError`, and a cancelled `Task.sleep` throws without suspending —
so the loop degenerated into a tight busy loop. Measured in the RED run of
`tickerLoopBuiltOnWaitStopsAfterCancellation`: **97,434 extra ticks in 150 ms**
after cancellation.

Fix: the cadence step is `DictationLiveTicker.wait(interval:)`, which converts
cancellation into an explicit stop signal for the caller. Tests:
`DictationLiveTickerTests` (RED → GREEN as above); clock cadence (500 ms),
`DictationSessionClock` behavior and the `.task(id:)` restart-on-phase-change
are unchanged. No other loop of this shape exists in `Sources/`.

### Content polish (all within the two files)

- Idle guidance is truthful and names the configured shortcut (dynamic
  `DictationController.shortcutLabel`; Right ⌥ is only the default): "Tap
  <shortcut> to start and stop, or hold it and speak — release to finish."
  (matches the gesture fix in `ddf16a8`).
- Language labels are meaningful: `InspectorFormat.languageLabel` renders
  "Spanish (ES)" from "es-ES" via Foundation's localized names, "Auto" for
  `auto`, and the raw identifier when no name exists. Used by the idle
  Readiness card, the live Session card, and meeting details. Existing
  truthfulness rules kept (Apple-locale row hidden for Muse).
- Meeting details regrouped: calendar rows split into their own "Calendar"
  card; the meeting ID row is monospaced, single-line, middle-truncated.
- Perf: `SpeakerTalkTime.report` was computed on every body evaluation of the
  meeting inspector (every hover/state change re-walked the whole transcript);
  it is now derived once per segment fetch and cached in `@State`.
- Motion, per the active-signal-only rule: quick-action rows gained the shared
  `hoverHighlight` (already Reduce Motion-aware); the live status dot pulses
  its opacity only while actually listening and renders steady under Reduce
  Motion. No other repeating animation; no idle timers.

## Gates

- `swift build` — clean, 0 warnings.
- `swift test` — all suites pass; 403/70 at the first round (baseline 390/67,
  +13 new), 415/71 after the review round (+6 presentation tests and shared
  shell tests from `33e655b`).
- Lint: no project linter config exists (no `.swift-format`/`.swiftlint.yml`).
  The toolchain `swift format` subcommand is available (an earlier note in
  this doc wrongly claimed it was not — I had only probed the standalone
  `swift-format` binary). Root's `swift format lint` run reported 42 warnings
  including existing ones in these four files; the review round applied
  `swift format format --configuration '{"indentation":{"spaces":4}}'
  --in-place` to the four touched files and `swift format lint` on them now
  exits 0 with no findings.
- Not run by this session: app bundle, app launch, visual capture. Visual QA
  of the reference PNGs was not possible from here — this session could not
  view them natively (they routed through a remote vision service), and no
  claim about the host's lock state is made; root's AX navigation of the real
  UI is the visual check of record.

## Review round 2 (integrated-screen review, fixed)

Root-confirmed findings and fixes, all RED-first at the new
`DictationHistoryListState.resolve` seam (presentation selection, extracted
first carrying the shipped wiring):

1. A last-good EMPTY snapshot suppressed the "Updating results" indicator and
   the inline refresh failure/Retry — a failed reload after an empty verdict
   looked like a finished empty library. The banner now reports the
   transition independently of the applied row count. RED:
   `refreshOverAnEmptyLastGoodSnapshotStillShowsProgress`,
   `refreshFailureOverAnEmptyLastGoodSnapshotShowsInlineRetry`.
2. Empty-state copy read the live filter fields while the shown snapshot
   belonged to `appliedQuery` — during debounce/in-flight changes the UI
   relabeled the old query's empty as the new input's result. Copy is frozen
   to the applied query (`empty(search:sourceApp:)` carries it), and filters
   that differ from the applied query show "Updating results" immediately,
   inside the debounce window, before any fetch begins. Superseded in-flight
   fetches were already dropped by the model's in-flight guard; the paging
   query/cursor guards are unchanged. RED:
   `changedFiltersShowProgressBeforeAnyFetchBegins`;
   `emptyCopyIsFrozenToTheAppliedQuery` is the contract test for the frozen
   copy (green by construction at the seam).
3. `InspectorStatusDot` kept `dimmed` on the parent view, so a later
   `.listening` stretch (retry after failure, Reduce Motion toggle) inherited
   a finished pulse and never restarted. The pulsing dot is now its own
   branch-owned view (`PulsingDot`), so structural identity resets its state
   on every entry; still the only repeating motion, only while actually
   listening, steady under Reduce Motion, no tasks. Presentational — no test.

## Out-of-scope followups (proposals only)

1. The placeholder stats row is a plain `HStack`; at very narrow widths the
   real `DictationStatsGrid` falls back via `ViewThatFits` and the placeholder
   does not. If the panel ever gets narrower than ~340 pt, give the
   placeholder the same fallback (Chrome file, Grok's lane).
2. `DictationHistoryView.groups` recomputes day groups per body evaluation —
   one sort of at most a few hundred rows; unmeasured, expected negligible,
   but it could move into the model's apply step if paging ever grows large.
3. A live input-level meter (reference's orange level bar) needs a level feed
   from `DictationController` — shared controller, human decision.
