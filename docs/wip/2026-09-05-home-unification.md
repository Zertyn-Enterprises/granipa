# Home unification — 2026-09-05

Human-approved T1/T7/T9 navigation consolidation. No schema, capture
shortcut, dictation, signing, or dependency changes.

## What landed

- Sidebar app destinations are Home and Dictation. Settings and Collections
  stay. Meetings, Notes, and Files are leftover transient enum cases for
  fixtures; they are not sidebar rows and highlight Home.
- Home keeps its title (or Search / folder name). It is never a Meetings page.
- Compact All / Notes / Recordings strip on Home. Default All. Selected
  state uses `accessibilityAddTraits(.isSelected)`. Geometry is a fixed
  three-capsule row (Theme accent fill, 13pt, minHeight 28).
- Filter is transient `AppState.homeLibraryFilter`. Opening a meeting, going
  back, and Settings snapshot/restore keep it. Home/Dictation reveal keep it;
  leftover Notes/Files/Meetings reveals canonicalize onto Home + filter.
- Collections (`revealFolder`) stay on Home.
- Folder ∩ search ∩ type filter via `MeetingLibrary.shown` on the existing
  `notes` / `recordings` predicates. Calendar card only on unfiltered Home All.
- Recordings reuses `FilesLibraryRow` + off-main `fileStatuses`. Notes reuses
  `NotesLibraryRow`. Context menu / Quick note / Record wiring unchanged.

## Red (against pre-change `feat/granipa-v2`)

Command: `swift test --filter appSidebarDestinationsAreHomeAndDictationOnly --filter homeHeaderIsNeverAMeetingsPage`

Log: `/private/tmp/granipa-home-unify-red.log`

- `appDestinations` was `["Home", "Dictation", "Meetings", "Notes", "Files"]`
- `LibraryCopy.homeTitle(..., mode: .library)` returned `"Meetings"`
- Exit 1, 2 tests / 6 issues

`destinationChromeMatchesTheContract` still asserted five sidebar titles.
Updated with an explicit reason: human-approved new UI contract, leftover
cases remain on `allCases`. Assertions were not weakened.

## Green

`swift test` → **446 tests / 74 suites**, exit 0.
Log: `/private/tmp/granipa-home-unify-full.log`
`git diff --check` clean. Swift 6 compile via `swift test`.

Prior Debug count on this branch was 431/74; this change adds 15 tests.

## Limitations

- Worker did not run pixel / AX geometry QA; integrated AX results are below.
- `NotesLibraryView` / `FilesLibraryView` page wrappers remain; MainWindow
  mounts `HomeView` for leftover routes and reuses their rows.
- File status lookup runs only while Recordings is selected (no extra polling).

## Integrated verification (Codex)

- Base `b622a68`, implementation `ebc7f76`, branch `feat/granipa-v2`; main
  remains untouched. Baseline `swift test`: 431 tests / 74 suites, 2.198s
  execution / 4.39s wall. Implementation: 446 / 74, 7.488s execution.
  These are single runs under different host load, not a speed comparison.
- The first new GRDB integration test run failed because its fixture assigned
  a second folder that it had not inserted. The fixture now persists that
  folder; all assertions remain. No production data/schema fix was involved.
- `xreview --base b622a68 --family glm`: **VERDICT: OK**, three nits:
  unresolved stale folder IDs suppress the calendar card; the old page
  wrappers remain unmounted; `fileStatusTaskID` names a path list. These are
  documented rather than expanding this delivery. Log:
  `/private/tmp/granipa-home-unify-review-glm.log`.
- `git diff b622a68..HEAD --check`: exit 0. No configured project linter.
  Supplemental `swift format lint` with four-space indentation: exit 0,
  55 diagnostics on touched files versus 57 on the same baseline files.
  This is not a zero-warning whole-repo lint claim.
- Prepared real-app navigation smoke failed on the OLD build because its
  sidebar still included Meetings, as expected. Log:
  `/private/tmp/granipa-home-unify-smoke-red.log`.
- Prior polish verification resumed on the unlocked Mac, PID 70849, window
  1249 × 866 points. AXHeading requires its native role, not AXStaticText.
  Home and Dictation now both have heading x/y 277/76, Quick note 966.5/79.5,
  Record 1099/79, sidebar Home 10/171 and Dictation 10/211, in two cycles.
  Log: `/private/tmp/granipa-home-unify-before-geometry-heading.log`.
  This confirms geometry, not pixel appearance or FPS.
- The older Dictation-search probe reflected/restored its input but did not
  locate the expected empty-state element; that probe remains inconclusive.
  Dictation implementation is unchanged in this task; no Dictation search
  end-to-end claim is made here.
- Rollback copy of the previous signed app:
  `/private/tmp/granipa-home-unify-backup.uT1Wmo/Grañipa.app`.
- `swift build -c release`: exit 0; build 382.38s, wall 388.63s, user
  162.69s, sys 14.42s. No compiler warnings/errors in its log. The cause of
  the longer wall time has not been established.
- Previous app window had been closed. Reopening it allowed the guarded
  normal quit to verify idle capture and report `normalQuitConfirmed=true`.
- `Scripts/bundle.sh release`: exit 0, cached build 1.21s / total 9.64s.
  App is 26M (`du -sh`). Host deep/strict signature verification passes;
  app and embedded Sparkle both use Team ID `R4V252C833` with Apple
  Development identity. Hardened runtime retained. No installation into
  `/Applications`, ad-hoc signing, schema change or new dependency.
- New app launched as PID 29806. Real AX smoke passed: Meetings/Notes/Files
  absent from sidebar; All/Notes/Recordings selected states reflected; Notes
  preserved across Settings/Back; Dictation/Home navigation intact. The
  identical smoke failed on the prior build. Log:
  `/private/tmp/granipa-home-unify-smoke-green.log`.
- New Home/Dictation geometry repeats the exact positions listed above at
  1249 × 866. Log: `/private/tmp/granipa-home-unify-final-geometry.log`.
- An additional meeting-open probe returned AX error -25204 after
  1.509237666s; its follow-up reported no available window. That extra smoke
  is inconclusive, not a passed end-to-end meeting-open measurement. No user
  content was edited by either probe.
- Final root suite repeated the existing `cancelledWaitReportsStop` timing
  flake: 1.0866990089416504s against <1s, while its cancellation-result check
  passed. The unchanged default-mode rerun failed the same bound at
  1.169471025466919s. No test/assertion was altered.
- Final complete `swift test --no-parallel`: **446 tests / 74 suites pass**,
  exit 0, 76.101s execution / 106.87s wall. The cancellation test passes in
  0.001s. Log: `/private/tmp/granipa-home-unify-final-tests-serial.log`.
  This is an execution-mode change, not a skipped test or relaxed assertion.
  Default-mode timing instability remains unresolved; serial success does not
  establish its cause or fix it. The earlier worker default-mode full run also
  passed with the same implementation. No general performance claim is made.
