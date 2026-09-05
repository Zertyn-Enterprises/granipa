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

- No pixel / AX geometry QA (not run).
- `NotesLibraryView` / `FilesLibraryView` page wrappers remain; MainWindow
  mounts `HomeView` for leftover routes and reuses their rows.
- File status lookup runs only while Recordings is selected (no extra polling).
