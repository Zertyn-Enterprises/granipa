# Visual polish — shell and libraries (2026-09-05)

Lane `v2-polish-shell` · baseline `d54906e`. Screenshots inspected:
`codex-clipboard-ry4GFT.png` (Home), `codex-clipboard-fN5rnk.png` (Dictation),
`codex-clipboard-82EVmZ.png` (rich Dictation reference). No running-app visual
QA — bundle/run was out of scope.

## Why Home and Dictation jumped

Two independent occupants, not a title-font mismatch.

1. **Toolbar.** `MainWindow` only inserted the inspector toggle when
   `inspectorKind != .none`. Home with no meeting is `.none`, so the hidden
   titlebar had no toolbar item. Idle Dictation is `.dictationIdle`, so the
   toggle appeared next to the traffic lights and the titlebar chrome changed.
2. **Idle inspector default.** Idle Dictation always counted as content, and
   `ShellLayout.presentation` expanded any content on windows ≥1280. Home has
   no inspector occupant, so the third column opened only on Dictation and the
   content width changed.

## Fixes

- Library destinations always keep the inspector toggle. It is disabled when
  there is nothing to show (`kind == .none`). Settings still omits it.
- Occupancy (`inspectorKind`) is separate from docking (`presentation`).
  Live Dictation is `.dictationLive` at every width so a narrow window can
  overlay it when the user expands. Idle Dictation stays `.dictationIdle` but
  `expandsByDefault` is false — hidden until the toggle is used. Meeting and
  live inspectors still open by default when wide. `inspectorOverride` remains
  in-memory `@State`; no new preference key.
- `DestinationChrome` is the shared title + actions row. Dictation dropped the
  40×40 orange mic box so the title shares Home's leading x, type, and control
  height. Subtitle sits under that row. Meeting Record still calls
  `startRecording()`; Dictation Record still calls `toggleFromMenu()`.
- Primary/secondary controls use a charcoal/orange capsule style in both
  windows, including disabled Record (dimmed orange, still labeled Record /
  Transcribing…). Press feedback is local and nil under Reduce Motion. No
  parent-tree animation on inspector presentation.
- Sidebar icons: `square.and.pencil` (Notes), `folder.fill` (Files), larger
  hierarchical SF Symbols, tighter but taller rows, hover + press. No bitmap
  assets.
- Metric cards: four real Dictation stats, icon not boxed. Entry cards: no
  letter-square; real `sourceApp` / folder names as `MetadataBadge`. No
  synthetic tags, favorites, accuracy, or sparklines.
- Search in Home/Notes/Files uses `LibraryListPhase.pending` instead of a
  flash-empty state.

## Deferred / proposals (not this lane)

- Root asked whether Notes/Files should collapse into Library. Destinations
  unchanged; Home still lists every meeting, Meetings is the same list minus
  the next-calendar card.
- `DictationHistoryView.swift` (GLM): filter row / load-more still use local
  bordered-prominent styling; vertical rhythm under the new subtitle is
  unverified in a running window.
- `InspectorViews.swift` (GLM): idle inspector chrome when explicitly opened.
- Running-app visual QA, idle CPU, and AX timing.

## Gates

- Red first against pre-change toolbar/kind/header/icon behavior (21 issues
  in the new contract tests).
- `swift test`: 396 tests / 67 suites pass.
- `swift build`: complete, no warnings in the build log.
- No project linter. Supplemental `swift format lint` (4-space) on touched
  Swift files: warnings remain, matching existing AddLines/LineLength noise
  in those files; no new format configuration added.
