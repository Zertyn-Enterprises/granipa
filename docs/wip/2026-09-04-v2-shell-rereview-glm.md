# Grañipa V2 — T1a shell re-review (GLM, corrections round)

- **Lane:** `v2-shell-rereview-glm` · **Branch:** `review/v2-shell-rereview-glm` · **Base:** `feat/v2-shell-grok@f4b83e1`
- **Review target:** `5fe7509...HEAD` — the three T1a implementation commits
  (ec7f841, 0554368, 4ab925e) plus Grok's three correction commits
  (f32a43c inspector occupant, be2ced5 file-metadata cache, f4b83e1 debounced DB search).
- **Date:** 2026-09-04 · **Reviewer model family:** GLM (xhigh). Independent re-review: neither the
  correction commit messages nor their embedded verification claims were trusted; every claim below
  was re-verified in this worktree this session.
- **Prior round:** `docs/wip/2026-09-04-v2-shell-review-glm.md` (verdict ISSUES, findings F1–F7).
  That file lives on `review/v2-shell-glm` / `feat/granipa-v2`; it is not in this branch's tree, and
  was read via `git show review/v2-shell-glm:docs/wip/…`.
- **Inputs read in full:** `AGENTS.md`, lane `PLAN.md`,
  `docs/wip/2026-09-04-v2-product-contract.md`, the prior review, and the full
  `git diff 5fe7509...HEAD` (17 files, +1227/−111) plus the correction-only diff
  `4ab925e..HEAD` (6 files).

Labels: **V** = verified this session in source or command output (`file:line` at HEAD = f4b83e1).
**U** = unverified, check named. Nothing below was assumed from the implementing commits.

---

## VERDICT: OK

All gates pass. F1, F2, F3, F4, and F7 from the prior round are verified **fixed** in source, each
pinned by tests. F5 belongs to T2a and F6 to the next T1b slice — both intentionally pending and not
charged here. No new medium-or-higher issue was found in the correction diff: no capture/ASR/AEC/
writer/schema/persisted-shape/dependency change, no weakened or deleted assertion, no fake UI, no
new timer/animation, no unbounded load, no state churn. Three nits remain (§4), none blocking.

---

## 1. Gates (exact output, re-run this session)

| Gate | Result |
|---|---|
| `git diff --check 5fe7509...HEAD` | clean — no output, exit 0 (**V**) |
| `swift build` | `Build complete! (110.82s)` — exit 0 (**V**; cold-ish compile in this worktree, not comparable to the implementer's incremental 0.31 s claim) |
| `swift test` | `Test run with 217 tests in 39 suites passed after 0.663 seconds.` — exit 0 (**V**) |

Test integrity (**V** `git grep -c` both revs): 197 `@Test` / 37 `@Suite` at `5fe7509` →
217 / 39 at HEAD (+20/+2: `ShellLayoutTests` 5, `ShellNavigationTests` 14, `ThemeTests` +1).
`git diff 5fe7509...HEAD -- Tests/` contains **zero deleted lines** — no pre-existing assertion was
weakened or removed. The correction commits did rewrite tests inside `ShellNavigationTests`, but only
tests of code the same corrections deleted (`matching`, the `.meeting` inspector case, the old
`fileStatus`/`fileLabel` signatures), each replaced by a stronger successor — e.g.
`sidebarSearchFiltersTitleAndNotes` (in-memory title/notes contains) became
`notesAndFilesSearchUseDatabaseSemanticsIncludingTranscript` (real GRDB, transcript hits), and
`meetingInspectorFollowsTheOpenMeetingNotTheList` became `selectedMeetingHasNoInspectorOccupant`
(4 destinations × 4 widths assert no meeting inspector) (**V** correction diff + `:119-136`).
No `.skip`/`xit`/`disabled` anywhere in Tests (**V** grep).

## 2. Prior findings — re-verified

### F1 (medium, slice scope + unbounded load + third live timer) — FIXED

- The `.meeting` inspector case, `MeetingInspectorView`, `loadSpeakers`, and its unbounded
  `db.fetchSegments` are gone: zero hits for `MeetingInspectorView|InspectorWaveform|loadSpeakers`
  in Sources and Tests (**V** grep, exit 1). `inspectorKind` now returns `.none` for every
  non-dictation destination (`AppNavigation.swift:80`), pinned by
  `selectedMeetingHasNoInspectorOccupant` over home/meetings/notes/files × {1120, 1279, 1280, 1440}
  (`ShellNavigationTests.swift:119-136`).
- No extra `RecordingTimer` in the shell: `RecordingTimer` survives only in the pre-existing HUD
  (`RecordingHUD.swift:69,118`) and detail header (`RecordingBar.swift:18`) (**V** grep
  `Sources/Granipa/UI`). `fetchSegments` callers are exactly the pre-existing five
  (AppState ×2, MeetingDetailView:315, APIRouter, DiarizationService ×2, MeetingExporter ×2) —
  the shell adds none (**V** grep).
- Breakpoint state machine (**V** `AppNavigation.swift:74-85` + `ShellLayout.swift:30-40`):
  - Dictation **idle** (phase `.idle`/`.done`): `.dictationIdle` at **every** width → truthful
    read-only occupant ("Dictation off" + "Hold {shortcut} to dictate.", reusing
    `DictationController.shortcutLabel` and the `DictationHistoryView.swift:159` honest-copy
    pattern) and the toolbar toggle at 1120/1279 (`MainWindow.swift:78-90` renders the toggle
    whenever `inspectorKind != .none`; `ShellLayout.presentation(1120, nil, true) == .hidden`
    until the user expands → `.overlay` ≥ 280 pt).
  - Dictation **active below 1280**: `inspectorKind == .none` → `hasContent false` → no inspector
    even if the user had expanded one; the floating overlay (`DictationOverlayController`, untouched
    by the diff — no Dictation/ files in `git diff --name-only`) is the sole live surface.
  - **Idle and live at ≥1280**: 300 pt column (`ShellLayoutTests.swift:25-34` pins 1280/1440;
    `idleDictationInspectorIsAvailableAtEveryWidth` `:138-146`;
    `liveDictationInspectorDocksOnlyWhenWide` `:148-162`).
- The state machine stays single-sourced: `inspectorOverride` (MainWindow) is the only user state,
  `windowWidth` the only width state; tests cover all four widths (**V**).

### F4 (low-medium, T2a chrome pulled forward) — FIXED

- `InspectorWaveform`, the engine chip (`engineID` → "On device"/"Muse"), and the
  "Entries persist locally" persistence shield are all deleted (**V** correction diff removals +
  zero hits at HEAD). The live inspector is now: status dot, status title, body text, and Retry
  (only `failed` + `lastFailureRetryable`) (`InspectorViews.swift:54-80`) — every string reuses the
  overlay's existing copy; Retry reuses `dictation.retry()` on the same controller. No second
  waveform/Canvas, no new `TimelineView`, no timer in any new shell file (**V** grep
  `TimelineView|Timer|DispatchSource|CADisplayLink` over the seven new UI files → none).
- Idle/live both read the one `DictationController`; the panel has no capture-start control, so the
  G5 single-capture rule is respected by construction (**V** `InspectorViews.swift:72-76`).

### F2 (medium, sync FileManager in a body path) — FIXED

- `fileLabel` no longer stats: it takes `status:` as a parameter
  (`AppNavigation.swift:173-184`); `fileStatus`/`fileStatuses` (the only FileManager *metadata*
  calls in the shell, `AppNavigation.swift:147-171`) have exactly one production caller — the
  `Task.detached(priority: .utility)` block in `FilesLibraryView.swift:82-89`, keyed by
  `.task(id: recordingPaths)` (**V** grep of all `fileStatus|fileLabel` call sites). Row bodies read
  only the `@State [String: RecordingFileStatus]` cache (`FilesLibraryView.swift:131-139`). The
  function itself carries the contract as a doc comment (`AppNavigation.swift:147`). The only other
  FileManager use in UI/ is a `removeItem` inside a Settings button action (`SettingsView.swift:606`,
  untouched by this diff) — not a body path.
- Pending (nil) status shows the bare filename, not "Audio file missing"
  (`fileLabelUsesCachedStatusWithoutTreatingPendingAsMissing`, `ShellNavigationTests.swift:204-215`).
- **Cache invalidation, traced through the in-app lifecycles (**V**,AppState + view lifecycle):**
  - First recording of a meeting: in-memory paths stay nil while `status == .recording`
    (`AppState.swift:343-345` sets status only; paths are written at stop, `:396-397`), so a live
    meeting contributes no path to `recordingPaths` and its row shows "Recording…" with no byte
    count (`FilesLibraryView.swift:125-128`). At stop the two new paths change the id → the task
    re-fires → fresh stat on the finalized files. Not stale.
  - Re-record into an existing meeting (`RecordingBar.swift:30`, same meetingID → same
    `audio/{meetingID}/mic.m4a|system.m4a` paths, `AppPaths.swift:22-28` deterministic): reachable
      only from the meeting detail, and selecting a meeting replaces the content column
    (`MainWindow.swift:132-140`) — FilesLibraryView unmounts, `@State fileStatuses` resets, and the
    return visit re-stats. Not stale.
  - Retention sweep `purgeOldAudio` (`AppState.swift:126-145`, pre-existing): nils paths → the path
    set shrinks → task re-fires, and the meeting leaves `recordings(in:)` entirely. Not stale.
  - Residual (nit N2): out-of-app mutation (Finder delete/overwrite) while the Files view stays
    mounted leaves a stale size label until remount or path-set change. Cosmetic; closing it needs
    a refresh trigger (re-stat on `app.meetings` change or window focus) — reasonable T1b/T4 polish.

### F3 (medium, per-keystroke full-library filter) — FIXED

- `MeetingLibrary.matching` (in-memory title+notes contains over the unbounded library) is deleted.
  Notes and Files now search via `.task(id: app.searchQuery)` + 200 ms sleep + detached
  `searchMeetings` (`NotesLibraryView.swift:62-76`, `FilesLibraryView.swift:90-103`) — the same
  debounce/cancel/DB pattern as the preserved Home path (`HomeView.swift:79-95`). `.task(id:)`
  cancels the in-flight task on query change and both post-await `Task.isCancelled` guards prevent
  stale commits — cancellation is real, not decorative (**V** source).
- While searching, `shown` is `searchResults` (DB-filtered); the full in-memory
  `notes(in:)`/`recordings(in:)` filter + `dayGroups` run only when the query is empty — i.e. not
  on the typing path — matching the preserved HomeView body pattern (`HomeView.swift:20-41`)
  (**V**).

### F7 (low, per-destination search semantics) — FIXED

- Both destinations call the same `AppDatabase.searchMeetings` Home uses
  (`AppDatabase.swift:372-393`: title, notesMarkdown, enhancedNotesMarkdown, summary, and
  `transcriptSegment.text`, DISTINCT, escaped LIKE), then apply the destination predicate
  (`AppNavigation.swift:116-126`). A transcript-only hit now finds the meeting from Notes/Files the
  same way it does from Home/Meetings. Pinned against real GRDB by
  `notesAndFilesSearchUseDatabaseSemanticsIncludingTranscript`
  (`ShellNavigationTests.swift:89-117`: transcript token hits the noted meeting via searchNotes and
  the recording-only meeting via searchRecordings; notes-text and blank-query cases covered).

### F5 / F6 — intentionally pending, not charged

- F5 (Dictation serif page title): `DictationHistoryView` is untouched by the whole range
  (**V** file list) — belongs to T2a per the prior round.
- F6 (runtime/screenshot/toolbar-rendering/CPU proof): no `--v2-fixture` or measurement artifacts
  exist (**V** zero hits in Sources) — belongs to the next T1b slice. Whether `.toolbar` renders in
  the `.hiddenTitleBar` window remains **U**; this code re-review does not fail on it per the task
  brief.

## 3. Freeze / scope verification

- **Files touched by `5fe7509...HEAD`:** AppState (nav-state enum, `reveal`/`revealFolder`,
  createFolder body), GranipaApp (os_signpost "appReady" + defaultSize constant), 11 UI files
  (7 new), 3 test files. **Zero** files under Audio/, Transcription/, Dictation/, Storage/,
  Diarization/, LLM/, API/, System/; no Package.swift, no SettingsView, no RecordingHUD, no
  CaptionsOverlay*, no PasteService/BatteryService (**V** `git diff --name-only` + freeze-pattern
  grep → NONE).
- No migration, no schema, no persisted-shape, no external-contract, no entitlements, no dependency
  change (**V** same file list). `usesLiveASR` default and meeting AEC untouched by construction.
- Settings scene and preserved flows: Settings code untouched; corrections themselves touch only
  AppNavigation / FilesLibraryView / InspectorViews / one MainWindow parameter line /
  NotesLibraryView / ShellNavigationTests (**V** `git diff 4ab925e..HEAD --stat`). The
  `showsDictationHistory` → `sidebarDestination` migration leaves zero residue (**V** grep).
- No fake UI/data: empty states are real ("No recordings yet" + working Record, "No notes yet" +
  working Quick note, search miss shows the actual query); the idle inspector states only what is
  true; no invented counts, providers, or percentages anywhere in the new views (**V** full diff
  read).

## 4. New findings (all nits — none block this slice)

- **N1 — `.done` window shows "Dictation off" early.** `dictationShowsInspector` excludes `.done`
  (`AppNavigation.swift:68-73`), so during the paste/auto-hide window (~0.7–1.6 s,
  `DictationController` auto-hide) the ≥1280 column flips to the idle panel while the overlay still
  shows the pasted preview. One honest-adjacent transition; the full live-inspector spec (including
  its Done row) is T2a's. `AppNavigation.swift:68-73`, `InspectorViews.swift:41-52`.
- **N2 — external file mutation staleness.** See F2 residual above: a file deleted/replaced outside
  the app while FilesLibraryView stays mounted keeps its cached size/presence until remount or
  path-set change. `FilesLibraryView.swift:82-89`.
- **N3 — `isSearching` trim inconsistency.** Notes/Files trim the query before deciding "searching"
  (`NotesLibraryView.swift:8-10`); Home does not (`HomeView.swift:14`). A whitespace-only query
  yields the normal list on Notes/Files but a "Search" header + empty results on Home. New views
  chose the stricter behavior; unifying (or trimming in Home too) is a one-liner for a later slice.
- Carried proposals from the prior round, unchanged by the corrections: row-anatomy duplication
  across the three library rows; the unreachable `.dictation` case in MainWindow's inner switch
  (`MainWindow.swift:150-151`); the narrow-overlay inspector has no click-outside-to-dismiss.

## 5. Regression sweep over the correction diff (as tasked)

| Check | Result |
|---|---|
| Unnecessary timers | None added. New shell files contain no `TimelineView`/`Timer`/display link (**V** grep). The only periodic work added is two `.task` modifiers per library view that sleep/await and exit. |
| Animations | No new animation sites in the correction diff. `MainWindow.animation(value: inspectorPresentation)` (pre-existing from 4ab925e) fires only on hidden↔overlay↔column changes; nil under Reduce Motion; transitions are `.opacity` only. |
| Memory-unbounded loads | None new. `searchResults` is bounded by DB matches (same as Home); `fileStatuses` is bounded by distinct audio paths; `fetchMeetings` remains unbounded but pre-existing and now feeds the same body paths as before plus nothing new. |
| State churn | MainWindow's body depends on `dictation.phase` only (not `preview`), so volatile dictation text re-renders only the inspector's child body. Idle↔live inspector flips are single transitions. The `.recording`→terminal path adds one `.task` re-fire per stop (two stats). |
| Main-thread I/O on typing/scroll paths | Gone: bodies read caches/state only; stats and SQL run detached (F2/F3 evidence above). |
| Search surfaces double-firing | Only the mounted destination's search task runs (content column switches views); Dictation's own 140 ms search untouched. |

## 6. Verdict rationale

- **OK:** every charged finding (F1, F2, F3, F4, F7) is fixed in the smallest way the prior round
  sketched, with the state machine and semantics pinned by pure tests at all four widths and by a
  real-GRDB search test; gates exit 0 with 217/39 green; the diff stays inside the T1a shell scope
  with freeze surfaces untouched; no assertion was weakened; the correction commits introduce no
  timer, animation, unbounded load, churn, or dishonest chrome. Residuals are three cosmetic nits
  plus the two intentionally-pending slices (F5 → T2a, F6 → T1b).
- Not BLOCK for the same reasons as before, and nothing new rises above nit severity.

---

*End of re-review. Deliverable of this lane: this file only. No Swift, test, schema, or durable doc
was modified.*
