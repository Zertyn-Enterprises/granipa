# Meeting and Permissions polish — 2026-09-05

Lane `v2-polish-shell` · base `33e655b`. Codex-verified source findings only.
No bundle, run, or hardware. Existing `.build` reused. No external review
this pass; root reviews the finished screens once.

Files: `UI/MeetingRecordedViews.swift`, `UI/MeetingPlaybackBar.swift`,
`UI/RecordingBar.swift`, `UI/PermissionsView.swift`, tests, this doc.

## Commits

| SHA | Change |
|---|---|
| `79f5255` | keep overview summary/notes/actions mounted while enhancing |
| `72cba8e` | language chips: checking vs installed vs absent; keyed refresh |
| `0c4c796` | adopt `granipaPrimaryControl` / `granipaSecondaryControl` |

## 1. Overview loading

Verified pre-change: `MeetingOverviewView` replaced the whole overview when
`isEnhancing || isProcessing` (`MeetingRecordedViews.swift:99` at `33e655b`).

New layout: full-screen progress only when busy and nothing readable exists.
Populated re-enhance and raw notes during post-stop keep content mounted with
a compact in-content progress title (`Writing notes…` /
`Processing this recording…`). Enhance stays disabled while busy. No Ready
copy.

### Red first (old layout, tests for new branches)

`swift test --filter OverviewPresentationTests` against the extracted old
layout (any busy → `.fullProgress`): **7 tests / 1 suite, 2 issues**.

- `populatedReEnhanceKeepsContentWithEnhancingProgress`
  `layout(isEnhancing: true, isProcessing: true, hasReadableContent: true)
  → .fullProgress(.enhancing)` expected `.content(progress: .enhancing)`
- `rawNotesDuringPostStopKeepContentWithProcessingProgress`
  `layout(isEnhancing: false, isProcessing: true, hasReadableContent: true)
  → .fullProgress(.processing)` expected `.content(progress: .processing)`

Log: `/tmp/granipa-overview-presentation-red.log`

Idle, empty-busy, readable-content helpers, and enhance-disabled were green
on the old layout (regression guards / green by construction).

### Green

Same filter after the layout flip: **7 tests / 1 suite passed**.
Log: `/tmp/granipa-overview-presentation-green.log`

## 2. Permission language chips

Verified pre-change: `installedIDs: Set<String> = []` painted every chip
"Not installed" before `SpeechModels.isInstalled` returned, and
`.onChange` spawned an unmanaged `Task` with no activation refresh
(`PermissionsView.swift:482` at `33e655b`).

Now: `knownInstalled == nil` → `.checking`. Empty known set → `.absent`.
`.task(id:)` keyed by locale IDs plus an in-memory `refreshTick` for
`didBecomeActive` and `NSLocale.currentLocaleDidChangeNotification`.
Locale-list changes clear last-known status; activation keeps last-known
until the new probe lands; stale locale snapshots are dropped. Read-only
`isInstalled` only. Generic permission rescan and `probeLocales` unchanged.
No downloads, no permission requests, no tests that call macOS permission
APIs.

### Red first (nil treated as empty/absent)

`swift test --filter PermissionLanguagesTests`: **5 tests / 1 suite, 3 issues**
on `unknownProbeIsCheckingNotAbsent`:

- `resolve(knownInstalled: nil, localeID: "en-US") → .absent` expected `.checking`
- `.label → "Not installed"` expected `"Checking"`
- `.accessibilityStatus → "not installed"` expected `"checking"`

Log: `/tmp/granipa-permission-languages-red.log`

Stale-snapshot, locale-clear, and task-id tests were green by construction.

### Green

Same filter after the nil → checking flip: **5 tests / 1 suite passed**.
Log: `/tmp/granipa-permission-languages-green.log`

## 3. Shared control styles

Verified pre-change: playback Record `.bordered`, recording-bar Record
`.borderedProminent`, Enhance/Retry/Open notes `.bordered`, Rescan /
Open System Settings `.bordered`, Fix recommended `.borderedProminent`.

Adopted existing `granipaPrimaryControl` / `granipaSecondaryControl`.
Playback ring 44 / inner 28 / scrubber height 44 unchanged. Live Stop
stays `.borderedProminent` + `Theme.statusListening`. Row Request/Check
actions stay system bordered styles. No new styling helpers. No animation
of large trees.

### Red first (source still on system button styles)

`swift test --filter MeetingPermissionsStyleTests`: **4 tests / 1 suite, 8 issues**.

- missing `granipaPrimaryControl()` in playback and recording bar
- leftover `.buttonStyle(.bordered)` in playback and overview
- leftover `.tint(Theme.accent)` on recording-bar Record
- missing `granipaPrimaryControl()` / `granipaSecondaryControl()` in permissions

Log: `/tmp/granipa-style-red.log`

### Green

Same filter after the style swap: **4 tests / 1 suite passed**.
Log: `/tmp/granipa-style-green.log`

## Limits / not done

- Waveform `Canvas` in `PlaybackScrubber` was **not** changed. Its cost has
  not been measured this session; treat any redraw concern as a proposal.
- `DictationHistoryView` and `InspectorViews` untouched (GLM).
- No storage, settings key, permission grant, capture, audio engine, or API
  changes. `probeLocales` is still read-only here.
- No bundle, run, or hardware. No running-app visual QA.
- No external `xreview` this pass.

## Gates

- `swift test`: 412 tests / 70 suites passed. Log:
  `/tmp/granipa-meeting-permissions-full-test.log`
- `swift build`: complete, no `warning:` in the build log. Log:
  `/tmp/granipa-meeting-permissions-build.log`
- Supplemental `swift format lint --configuration '{"indentation":{"spaces":4}}'`
  on touched Swift files: warning counts match the pre-change files
  (AddLines/LineLength/Indentation already present). New test files have
  zero format warnings. No new format configuration.
