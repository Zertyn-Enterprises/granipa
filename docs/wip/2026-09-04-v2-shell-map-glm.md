# Grañipa V2 — T1 shell implementation map (GLM)

- **Lane:** `v2-shell-map-glm` · **Branch:** `docs/v2-shell-map-glm` · **Base:** `feat/granipa-v2@e90bb91`
- **Date:** 2026-09-04 · **Merge policy:** hold · **Deliverable:** this file only. No Swift, schema, or durable-doc edits.
- **Inputs read in full:** `AGENTS.md` (via `CLAUDE.md`), lane `PLAN.md`, canonical plan
  `.claude/plans/granipa-v2.md`, the reconciled product contract
  `docs/wip/2026-09-04-v2-product-contract.md` on branch `docs/v2-contract-grok@e8d5b91`
  (sibling worktree; not yet merged into this branch), both T0 audits
  (`2026-09-04-v2-audit-grok.md`, `2026-09-04-v2-audit-glm.md`) and both cross-reviews
  (`2026-09-04-v2-review-grok-on-glm.md` I1–I15, `2026-09-04-v2-review-glm-on-grok.md` I1–I7).
- **Refs:** `/private/tmp/granipa-v2-refs.V0xiDo/01…10` (1448×1086). Inspected this
  session: **01, 03, 07** (the three shells T1 covers). The remaining seven are covered
  by the T0 audits' inventories and are cited as V-img-audit.

Labels: **V** = verified this session in source at `e90bb91` (`file:line`) or as pixels
in a named PNG I opened. **V-img-audit** = pixel claim from a T0 audit/review, not
re-opened here. **V-prev** = measured in lineage docs, cited not re-measured.
**P** = proposal (reversible; not measured fact). **H** = human one-way door, not chosen.

Method: every `file:line` below was read this session in this worktree. Absence greps
run this session: `NavigationSplitView`/`.inspector(` (zero hits in `Sources/`),
`keyboardShortcut`/`KeyEquivalent` (only `MenuBarView.swift:68-80` ⌥⇧ menu items and
`OnboardingView.swift:209` defaultAction — **no ⌘K anywhere**), no `.swiftlint.yml` /
`.swiftformat` / lint script in the repo (gates are `swift build` + `swift test`).
Test tree counted this session: **197 `@Test` / 37 `@Suite`**. Swift source at my HEAD
equals `c7704c3` (the three commits since are docs-only — `git log --oneline -3`).

---

## 1. Verified current source seams

### 1.1 Scene and shell

| Seam | Where (V) | What |
|---|---|---|
| Scenes | `GranipaApp.swift:22-60` | main window (`.hiddenTitleBar` :27, `defaultSize 1120×720` :28), `MenuBarExtra`, onboarding, `recording-hud`, `Settings` :55-59 |
| Main layout | `MainWindow.swift:17-52` | `HStack(spacing: 0)`: `SidebarView().frame(width: 248)` :20-21 + `.background(Theme.bgSidebar)` :22, 1 px `Theme.border` divider :24-26, content `VStack` :28-46 |
| Content switch | `MainWindow.swift:36-45` | `if app.showsDictationHistory { DictationHistoryView() } else if let meeting = app.selectedMeeting { MeetingDetailView } else { HomeView() }` — **the only destination router** |
| Detection banner | `MainWindow.swift:29-35` (mount, Reduce Motion `.opacity` :32-34) + `87-111` (impl) | stays mounted over content |
| Window floor | `MainWindow.swift:55` | `minWidth 960, minHeight 600` |
| Appearance | `MainWindow.swift:53` `.preferredColorScheme(.dark)`; also `SettingsView.swift:26`, `OnboardingView.swift:28`, `DictationHistoryView.swift:69` | dark-only everywhere |
| Banner animation | `MainWindow.swift:47-49` | `.easeOut(Theme.motionNormal)`, nil under Reduce Motion |
| Error alert | `MainWindow.swift:69-78` | `app.loadError`; permission-looking errors offer Open Settings |

### 1.2 Navigation state (the seam T1 extends)

`AppState.swift:24-37` — `meetings` :24, `folders` :27, `selectedFolderID` :28,
`searchQuery` :29, `selectedMeetingID` :30, **`showsDictationHistory` :31 (bool — the
whole nav model today)**, `loadError` :32, `selectedMeeting` computed :34-37.
`pipelinePhase(for:)` :39-45.

**Every consumer of `showsDictationHistory` (V grep, 9 sites — all must be migrated in
the same commit as the nav change):**

| Site | Role |
|---|---|
| `AppState.swift:31` | declaration |
| `AppState.swift:562` | folder selection clears it |
| `MainWindow.swift:37` | destination router |
| `SidebarView.swift:12` | `isHomeActive` |
| `SidebarView.swift:27, 38` | Home / Dictation item actions |
| `SidebarView.swift:33` | Dictation `isActive` |
| `SidebarView.swift:75` | folder item action |
| `HomeView.swift:225` | meeting row click |

Related mutations that must keep working: `createMeeting` sets `selectedMeetingID`
(`AppState.swift:286`); folder clicks mutate `selectedFolderID` directly in the view
(`SidebarView.swift:73-76`); `createFolder` auto-selects the new folder
(`AppState.swift:560-562`); `deleteFolder` resets `selectedFolderID` :584-585;
`deleteMeeting` clears `selectedMeetingID` :653-654.

### 1.3 Sidebar

`SidebarView.swift` — top spacer under traffic lights :18; search field :148-175
(binds `$app.searchQuery` :154, `Theme.fillSubtle` fill + `Theme.border` stroke,
cornerRadius 10 :171-174, clear button :158-167); `SideItem` :185-233 (active fill
`Theme.fillSubtle` in RoundedRectangle 10 :214-219, icon 16 pt frame :201, title
semibold-when-active :203, hover via `.hoverHighlight(cornerRadius: 10)` :220);
Home item :23-28, Dictation item :30-39, SPACES label :41-49, folders+teams :51-94
(context menu rename/delete :78-86, Add folder :89-92); **Recording indicator footer
:98-108** (keep, per contract §2.1); `SettingsLink` footer :110-120.
No counts anywhere (V — `folderMeetingCounts()` `AppDatabase.swift:284-295` is
consumed only by `APIRouter.swift:129`).

### 1.4 Content surfaces T1 touches or hosts

- **Home** `HomeView.swift` — header row 42-69 (Quick note :47-54 `.bordered`,
  Record :56-68 `.borderedProminent`, `disabled(app.recorder.isBusy)` :68); title
  `Theme.titleFont` :44; hero card `HeroEventCard` :157-214 (mount :71-73);
  `shownMeetings` :14-18 (folder filter in memory); `headerTitle` :20-24; day groups
  :30-37; empty state :119-154 (search / folder / fresh variants — keep copy);
  insets `.horizontal 32` :94 + `maxWidth 780` :97 (contract §2.4 changes both);
  search debounce 200 ms cancel-on-change :100-116; `HomeMeetingRow` :217-301
  (row anatomy + context menu export/copy/delete :274-299; sets nav at :225-226).
- **Dictation** `Dictation/DictationHistoryView.swift` — period enum :4-26; state
  :32-38; reload on appear/period/search :70-87 (140 ms debounce :80-86); stats bar
  :90-114 (**four** real cells :100-105 — WPM/words/apps/saved); search bar :129-147;
  honest empty state :149-168 (`"Hold \(DictationController.shortcutLabel) to
  dictate. Entries land here."` :159 — keep verbatim); list/bubble :170-215; `reload()`
  :217-222 via `fetchDictationEntries` (limit 500, `AppDatabase.swift:209`).
  No page title today (stats bar is first).
- **Meeting detail** `MeetingDetailView.swift` — Tab enum :16-20 (Notes / Enhanced /
  Transcript — **T1 does not rename tabs**); init tab heuristic :22-28; header :64-119
  (back chevron :67-77 sets `selectedMeetingID = nil`; language chip :83-90; folder
  chip :92-99; overflow menu :151-174; title field :106-110; `RecordingBar` :112;
  tab bar :176-204; `.padding(.horizontal, 28)` :116).
- **Record controls** `RecordingBar.swift:13-39` (Record / Stop states), warnings
  :41-46, `LevelMeter` :65-83 (gated levels — untouched).
- **Permissions** `PermissionsView.swift` — six rows :8-66 (Microphone :8-13, System
  Audio custom row with Check/probe :14-44, Calendars :45-50, Notifications :51-56,
  Screen Recording OCR-only :57-61, Accessibility :62-66); badge vocabulary :110-131
  (Granted / Denied / Not asked yet / empty for unchecked); refresh on `.task` +
  become-active :68-74; pane deep links :12, 38, 49, 55, 61, 66; `PermissionsSettings`
  :144-164 (Form + welcome tour). Backing `System/PermissionCenter.swift`:
  `PermissionState` :6-11, six stored states :16-21, `probingSystemAudio` :22,
  `refresh()` :26-50, probe-creates-a-real-tap comment + `probeSystemAudio()` :52-70.
- **Settings scene** `SettingsView.swift:8-23` — seven tabs, label-for-label the IA of
  ref 03 (V both audits + my read); `640×600` :24; `.dark` :26.
- **Theme** `Theme.swift` — colors :14-32 (bg :14 `0x161412`, bgSidebar :15 `0x1C1A18`,
  card :16 `0x232120`, border :17 white 7%, accent :18 `0xF05423`, brandPurple/Pink
  :19-20, text 92/55/34 % :21-23, channelMe :24, fillSubtle/fillHover/strokeStrong
  :25-27, status×5 :28-32); fonts :34-35 (`titleFont` 34 serif semibold,
  `meetingTitleFont` 28 bold), semantic fonts :46-48; space :37-39; radius :41-44;
  motion :50-51; `avatarColor` :52-60; `dayHeader` :62-66; `CardStyle`/`.card()`
  :69-85; `HoverHighlight` :87-107 (Reduce Motion nil-animation :97-98); `AvatarView`
  :109-132. `PanelMotion.swift:6-9` (0.34/0.20/40).
- **Meeting model** `Meeting.swift:10-27` — fields T1 reads for Notes/Files pages:
  `notesMarkdown` :18, `audioMicPath`/`audioSystemPath` :25-26, `folderID` :27,
  `startedAt`/`endedAt` :14-15, `status` :17.
- **Dictation controller (observable, read-only)** `DictationController.swift` —
  `phase` :12, `preview` :13, `engineID` :16, `shortcutLabel` :36. T1's inspector only
  reads these; it never calls `beginCapture`.
- **Sparkline (known fake)** `MeetingSparkline.swift:4-19` seeded from meeting id;
  view :22-45 (148×18 Canvas, `accessibilityHidden` :43). Contract §3.1: keep as
  presentation-only until real peaks exist.

---

## 2. The slice

**Goal:** a compiled, navigable V2 shell — Family A geometry, canonical dark tokens,
Home / Dictation / Meetings / Notes / Files destinations with honest states, optional
inspector column with breakpoints, ⌘K search focus — with **zero** changes to capture,
dictation engine, DB schema, Settings scene behavior, or any preserved behavior in
contract §1.4. This is contract **T1** (§5.4, §8, §10.4).

**In (all `new-reversible`, no persisted shape):**

1. Dark token retint (`bg`, `bgSidebar`, `card` + new `accentGlow`) and `titleFont`
   34 → 32. No light tokens.
2. `AppSection` nav state replacing the `showsDictationHistory` bool (9 call sites),
   sidebar gains **Meetings, Notes, Files** items and **folder counts**.
3. Meetings page = the full library (Home rows, no calendar hero). Notes page v1 =
   meetings with non-empty `notesMarkdown` (quick notes included). Files page v1 =
   meetings with audio, labeled **Recordings** (Me/Them rows, real file existence).
   All three reuse `HomeMeetingRow`; empty states honest.
4. Inspector column: 300 pt at width ≥ 1280, collapsed at 960–1279 with a toolbar
   toggle revealing a trailing overlay (min 280), crossfade-only transitions.
   **T1 occupant (P — see §4.6): the Dictation destination's session panel in its
   real states** (phase, preview text, engine label, shortcut label — read-only, no
   waveform, no second capture).
5. ⌘K focuses the sidebar search field (new `Commands` scene; a11y label
   "Search meetings" — it filters meetings today).
6. Fixture mode (Debug launch arg) + screenshot matrix (§5) + idle CPU before/after.

**Out (explicitly, with owners in §9):** player/peaks, transcript pagination/search,
dictation library chrome (T2a), live stage (T3), meeting tab renames + Overview
inspector content (T4), Permissions health strip (T6), every §9 door.

**Honesty rules for this slice (from contract §1.2/§1.3):** no Accuracy tile, no
usage/plan/account rows, no IntentX wordmark or names, no "2 of 6"-style health copy,
no ⌘F chrome, no Pause/Resume, no play buttons, no Synced-to, no ES chrome. Notes and
Files pages show **real derived data only**; their dedicated objects stay T7 (C2:
the destination ships, the schema does not).

---

## 3. Reuse / extend / create / untouched

Search-before-new (this session): grep for `NavigationSplitView`/`inspector` (none),
`keyboardShortcut` (none for ⌘K), page-header-like components (none — headers are
inline in `HomeView`/`DictationHistoryView`/`MeetingDetailView`), stat/empty-state
patterns (`DictationHistoryView.statCell` :116-127, `HomeView.emptyState` :119-154 —
reuse shape), `SideItem` (`SidebarView.swift:185`), `HomeMeetingRow`
(`HomeView.swift:217`), `folderMeetingCounts` (`AppDatabase.swift:284`), hero card
(`HomeView.swift:157`). Near-matches exist for everything the shell needs; the only
new *components* are the ones below, each with multiple consumers.

| Action | Item | Notes |
|---|---|---|
| **Reuse unchanged** | `SideItem`, `HoverHighlight`, `.card()`, `AvatarView`, `Theme.dayHeader`, `HomeMeetingRow` (with a new optional subtitle parameter), `HeroEventCard`, `MeetingSparklineView` (presentation-only, unchanged), `RecordingBar`, `LevelMeter`, detection banner, `RecordingTimer`, `PermissionsListView`, `SettingsView` scene, `PanelMotion` | zero edits |
| **Extend** | `Theme.swift` (3 hex retints + `accentGlow` + hex constants + `sectionFont` 16 semibold + `titleFont` 32), `SidebarView` (3 dest items + counts + a11y labels + FocusState), `HomeView` (insets 32→28, drop `maxWidth 780` :97, parameterize hero/empty for reuse as the Meetings page), `AppState` (nav state + `folderCounts` + `searchFocusRequest`), `MainWindow` (router switch + width class + inspector column mount), `DictationHistoryView` (page title + subtitle only — no library chrome changes) | all extensions additive at the call sites named in §1 |
| **Create** | `UI/AppSection.swift` (enum + pure helpers), `UI/PageHeader.swift` (title + optional subtitle + trailing actions — used by 4 destinations), `UI/MeetingsLibraryView.swift` (Meetings page), `UI/NotesView.swift`, `UI/FilesView.swift` (Recordings list), `UI/InspectorColumn.swift` (container + visibility resolution), `UI/DictationSessionInspector.swift` (T1 occupant), `UI/WidthClass.swift` (pure `enum { narrow, wide }` + threshold), `Commands/SearchCommands.swift` (⌘K), `AppDatabase.open(at:)` overload for fixtures | each has ≥ 2 consumers or is a pure seam with tests; no speculative parameters |
| **Leave untouched** | `RecordingSession`, `RecordingEngine`, `SystemAudioTap`, `MicRecorder`, `Transcription/*`, `Dictation/*` engine paths, `DictationOverlayView` + its `TimelineView` (30 fps stays until T9/G10), `CaptionsOverlay*`, `MeetingDetailView` body/tabs, `EnhancedNotesView`, `API/*`, `WebhookService`, `LLM/*`, migrations v1–v8, `Package.swift`, all `System/*` except nothing | freeze per contract §5.1 |

---

## 4. Exact visual and interaction spec

### 4.1 Geometry (adopt; V where current, V-img-session where measured this session)

| Surface | Value | Evidence |
|---|---|---|
| Window | default 1120×720 (keep), min 960×600 (keep) | V `GranipaApp.swift:28`, `MainWindow.swift:55` |
| Sidebar | **248** fixed (keep) | V `MainWindow.swift:21`; V-img-session 01 ≈ 245 px |
| Divider | 1 px `Theme.border` between all columns (keep) | V `MainWindow.swift:24-26` |
| Content inset | **28** horizontal on every destination page (meeting header already 28) | V `MeetingDetailView.swift:116`; change from Home's 32 (`HomeView.swift:94`) |
| Content max width | drop the 780 cap (`HomeView.swift:97`) on wide layouts; lists remain leading-aligned `LazyVStack` | contract §2.4 |
| Inspector | **300** at ≥ 1280 window width; overlay variant min **280** at 960–1279 | V-img-session 01 ≈ 290 px inspector, 07 ≈ 390 px (analyzer estimates; 07's wider panel is the live-dictation variant); adopt 300 per contract §2.6 |
| Sidebar top spacer | 34 under traffic lights (keep) | V `SidebarView.swift:18` |
| Page header | title baseline row height ≈ 40, bottom padding 12; actions right-aligned | P (matches 01/07 title rows) |
| Rows | keep current anatomy; dictation/meeting rows already ~44–56 pt | V `HomeView.swift:264-265`, `DictationHistoryView.swift:204` |

### 4.2 Breakpoints and adaptive behavior

| Window width | Layout | Inspector |
|---|---|---|
| `< 960` | unsupported (min stays) | — |
| `960–1279` | sidebar 248 + content | hidden; toolbar toggle reveals trailing overlay ≥ 280 over content (dismiss by toggle or clicking content) |
| `≥ 1280` | sidebar 248 + content + inspector 300 | shown when the destination has inspector content (Dictation only in T1); toggle hides it entirely |

- Implementation: `WidthClass` pure enum, threshold constant **1280**, resolved in
  `MainWindow` via `onGeometryChange` (no `GeometryReader` re-layout churn) into
  `@State`; passed down. Pure function + constant are unit-tested.
- Crossing 1279↔1281: inspector collapses/expands with **opacity crossfade only**
  (contract §2.7); Reduce Motion already implied — no slide, ever, for the inspector.
- The floating dictation overlay is the live surface at narrow widths (contract
  §2.6) — nothing to do in T1; the overlay already exists.

### 4.3 Color (dark-only; light tokens not shipped — contract §1.2.12)

| Token | New value | Current (V) | Change |
|---|---|---|---|
| `bg` | `#141617` | `0x161412` :14 | retint |
| `bgSidebar` | `#17191A` | `0x1C1A18` :15 | retint |
| `card` | `#1E2123` | `0x232120` :16 | retint |
| `accentGlow` (new) | `accent` at 40 % opacity | — | static Record bloom; **no pulse** |
| all others (border, fills, stroke, text×3, accent, status×5, channelMe, brand×2, avatar palette) | unchanged | `Theme.swift:17-32, 52-60` | none |

Evidence: V-img-audit sampling (content `#131312–#191B1D`, sidebar `#17191A–#191C1D`,
cards `#1B1B1B–#242526`); V-img-session 01 sidebar ≈ `#171717–#1A1A1A`. Implementation
shape: expose `static let bgHex: UInt32` etc. so tests assert the constants, not
`Color` equality.

### 4.4 Typography and spacing

| Role | Spec | Change |
|---|---|---|
| Page title | 32 semibold serif (Home, Dictation, Meetings, Notes, Files) | `titleFont` 34 → 32 (`Theme.swift:34`); Onboarding keeps its local 28/24 (untouched, V `OnboardingView.swift:40, 59`) |
| Meeting title | 28 bold | unchanged :35 |
| Section (new token `sectionFont`) | 16 semibold | inspector card titles, stat group labels |
| Body / rows | current sizes stay (15 row title, 14 dictation text) | unchanged |
| Meta | 12 (current `Theme.fontBody` callout ≈ 12) | unchanged |
| Space/radius | `M12 L16 XL24`, `S8 M12 L16 Overlay24`, nav-active 10 | unchanged (locked `ThemeTests.swift:15-24`) |
| Shadow | overlays only; main-window cards flat | unchanged |
| Glow | static `accentGlow` behind Record pills | new, static |

### 4.5 Interaction states, focus, keyboard, a11y

- **Sidebar items**: hover = `fillHover` (existing `hoverHighlight`), active =
  `fillSubtle` + semibold (existing `SideItem`), Recording footer unchanged. New items
  get `accessibilityLabel`s equal to their titles; search field gets
  `accessibilityLabel("Search meetings")`.
- **Keyboard**: ⌘K focuses sidebar search (new `Commands` — `SearchCommands` posting
  through `AppState.searchFocusRequest`, `SidebarView` FocusState consumes);
  ⌘, opens Settings (system, existing); Esc behavior unchanged everywhere (dictation
  overlay/hotkey paths untouched). No new global hotkeys; no Carbon changes.
- **Record button**: exactly current semantics — disabled while `recorder.isBusy`
  (`HomeView.swift:68`), label "Recording…" when busy (:60-61). Never a second Record
  on a live surface (04 rejected).
- **Inspector toggle**: trailing toolbar button (SF `sidebar.right`), a11y
  "Show inspector"/"Hide inspector", visible at all widths on Dictation only in T1.
- **Reduce Motion** (mandatory, contract §2.7): banner already `.opacity` (V
  `MainWindow.swift:32-34`); destination switch and inspector transitions use
  `.opacity` only; **no new `TimelineView` exists in this slice** (waveform is T2a);
  hover animations already nil under Reduce Motion (V `Theme.swift:97-98`).
- **Light/dark**: `.preferredColorScheme(.dark)` stays on main/settings/onboarding;
  no light-mode code paths are introduced.

### 4.6 Inspector occupant — resolution of the one open layout tension (P)

The contract requires the inspector visible at ≥ 1280 (T1 DoD) but assigns every
*content* occupant to a later slice (dictation live inspector T2a, meeting details
T4b) and says lists never show one (§3.1). Shipping a column that renders nothing
would be untestable chrome. **Resolution (P, reversible, flagged for the director):**
the Dictation destination hosts a read-only session panel bound to the existing
`DictationController` observable (`phase`/`preview`/`engineID`/`shortcutLabel` —
V `DictationController.swift:12, 13, 16, 36`):

| State (real) | Panel shows |
|---|---|
| idle | "Dictation off" + "Hold {shortcutLabel} to dictate." (same honest copy as the library empty state) + engine label |
| preparing/processing | phase label + spinner |
| listening | preview text + "Dictation — press again to finish" + engine label |
| failed | failure message + Retry only if the overlay exposes it (reuse overlay strings; nothing invented) |

No waveform, no mic/language pickers, no second capture — `beginCapture` is never
called from the inspector (G5 territory stays T2a). **Alternative if rejected:**
ship the mechanism hidden everywhere and verify only toggle/breakpoint mechanics,
accepting that the DoD's three-pane proof lands with T2a. Either way no one-way door.

### 4.7 Destination state contracts (T1 scope)

| Destination | Ready | Empty | Live/error |
|---|---|---|---|
| Home | unchanged list + hero (inset change only) | current copy (V :119-154) | unchanged |
| Dictation | current stats/search/list + new serif page title + honest subtitle | current copy (:159 verbatim) | overlay unchanged |
| Meetings | full library, day-grouped, no hero, search-aware | "No meetings yet" (reuse Home copy) | pipeline phase labels reused |
| Notes | meetings with non-empty `notesMarkdown`, notes first line as preview subtitle | "No notes yet" + "Quick note" (creates a meeting note — real action) | rows open the meeting's existing Notes tab (V heuristic `MeetingDetailView.swift:25-27`) |
| Files | "Recordings" section: per meeting, Me/Them rows with real file existence (FileManager `fileExists`, size if cheap) | "No recordings yet" + Record | a recording-in-progress meeting shows "Recording…" without play controls |
| Settings/Permissions | Settings scene unchanged (7 tabs — already 03's IA, V) | n/a | PermissionsListView unchanged — already honest (V §1.4) |

Notes/Files predicates are pure functions over `[Meeting]` (`MeetingLibrary` helpers)
so they are unit-tested without `AppState` (whose `init` opens the real DB — V
`AppState.swift:47-69`; constructing it in tests is out of scope).

---

## 5. Fixture / screenshot matrix (traceable to all ten references)

Fixture mode (Debug-only launch arg `--v2-fixture <name>`): `AppDatabase.open(at:)`
overload + deterministic seed into a temp-dir DB. Fixtures render **real shapes**
(titles like "Product review — Thursday", segments with Speaker 1/2, real durations);
they are debug tooling, never shipped, never presented as user data.

| Ref | Covered by fixture / shot | Window | Verify present | Verify absent |
|---|---|---|---|---|
| 01 meeting-transcript | `meetings-open`: meeting selected from Meetings dest | 1448×1086 → wide class | 3 columns (248/…/300), tabs bar spacing, back chevron | IntentX, avatars' photos, Share/Synced-to, "582 lines" (no pager yet) |
| 02 dictation-live-card | `dictation-live`: session active via overlay, Dictation dest | wide | live inspector (§4.6 states), On-device label | in-list live card (02's duplicate — rejected), Accuracy tile, app logos |
| 03 permissions | Settings → Permissions pane shot | 640×600 | six rows, Granted/Not asked badges, Check button | "2 of 6" copy, 9:41 clock, Pro Plan/GB, camera dot (health strip is T6) |
| 04 live-recording | HUD + recording meeting selected | default | HUD still floats; Recording footer dot in sidebar (V :98-108) | Pause/rings/live-AI copy, Record-while-live |
| 05 meeting-overview-a | `meetings-open` | wide | header chevron+date+EN chip+folder chip (V :79-99) | named chapters, participants, In-progress status |
| 06 meeting-transcript-b | `meetings-open` transcript tab | wide | Speaker 1/2 honesty, disfluent text | ⌘F chrome, volume, highlight reel |
| 07 dictation-list | `dictation-idle` | wide | library + inspector side by side; day groups; "Showing k of n" **not yet** (T2a) | live card in list, green Accuracy, marketing subtitle |
| 08 meeting-overview-b | `meetings-open` | wide | overflow menu (export/copy/folder, V :151-174) | Resume, HD video, Key Moments, Invite |
| 09 dictation-list-rich | `dictation-idle` | wide | stat row of four | type tabs/Imports (T7), grid toggle (T2a), darker paint |
| 10 meeting-overview-c | `meetings-open` | wide | tab underline accent | chapter chips strip, Generated-ago, Synced-to |

Shot procedure (documented in the fixture commit): launch with arg → resize to
1280+ and 1120 → `screencapture -l$(osascript … window id)` into
`docs/wip/shots-t1/` (gitignored) → manual compare against this matrix. No snapshot
framework is added (no new dependency, contract §1.2.9).

---

## 6. Performance budgets and profiling commands

All numeric targets below are **P** unless marked V-prev; none has a measured
baseline in this repo for the T1 surfaces. Failure of any budget stops the slice
(contract §6.1).

| Budget | Target (P) | Command |
|---|---|---|
| Idle CPU (pre-T1 baseline vs post-T1) | ≤ 2 % avg over 60 s; **not worse than the pre-T1 run on the same machine** (DoD) | `top -pid $(pgrep -x Granipa) -l 13 -s 5 -stats pid,cpu,time` (drop first sample); record both runs |
| Idle wakeups | ≤ 3/s | `top -pid $(pgrep -x Granipa) -s 5 -stats pid,idlew` |
| Navigation (destination switch) | main-thread work ≤ 16 ms per switch (1 frame @ 60 Hz); no hitch | Instruments → Animation Hitches while clicking through all 5 destinations ×20 |
| Resize | 0 hitches over a 20 s continuous drag across 960↔1448; inspector crossfade only | Instruments → Animation Hitches during resize |
| Scrolling | 0 hitches scrolling a 200-meeting fixture list (`--v2-fixture meetings-many`) | Instruments → Animation Hitches; `LazyVStack` stays |
| Waveform rendering | **none added in T1** — dictation overlay stays 30 fps, untouched; ≤ 24 fps remains a T9 proposal (G10) | (no action; guard = diff shows no new `TimelineView`) |
| Memory | RSS ≤ 120 MiB after 10 min idle (V-prev single snapshot: 91,040 KiB RSS new process — not a controlled baseline) | `footprint $(pgrep -x Granipa)`; `top -stats rsize` |
| DB writes | navigation/resize/search-focus cause **0** commits; only folder-count reads (1 query on load + on folder/meeting mutations) | `sqlite3 -readonly "$HOME/Library/Application Support/Granipa/granipa.sqlite" 'pragma data_version'` sampled 1/s for 60 s idle — delta must be 0 |
| Startup | cold launch ≤ 2.0 s to interactive; T1 adds `os_signpost("appReady")` in `applicationDidFinishLaunching` (none exists today, V `GranipaApp.swift:4-6`) | Instruments → App Launch; signpost interval |

---

## 7. Tests and verification

Framework: swift-testing, existing suite **197 tests / 37 suites green at base**
(V count; runtime re-verified by the GLM audit at `c7704c3`). No UI-test
infrastructure exists (V — no ViewInspector/snapshot dep) and none is added.

**New-behavior tests (written first, seen to fail against pre-change code):**

| Test | Asserts | Fails-first against |
|---|---|---|
| `ThemeHexTests` | `Theme.bgHex == 0x141617`, `bgSidebarHex == 0x17191A`, `cardHex == 0x1E2123`, glow = accent 0.40 | current 0x161412/0x1C1A18/0x232120, no glow |
| `WidthClassTests` | threshold 1280; 959/1279 → narrow, 1280 → wide | new file |
| `InspectorVisibilityTests` | resolution from (widthClass, section, userToggle): narrow+Dictation → overlay-capable only; wide+Dictation → shown; wide+Home/Meetings → hidden; toggle overrides | new file |
| `AppSectionTests` | enum ↔ destination mapping; folder selection maps to `.home`; every legacy `showsDictationHistory` read/write site has an equivalent (mirrors the 9-site table §1.2) | post-refactor (fail-first on the refactor commit by writing tests before migrating) |
| `MeetingLibraryFilterTests` | notes predicate (non-empty `notesMarkdown`), recordings predicate (audio paths), sort order — over plain `[Meeting]` values | new file |

**Regression guards (green by construction — stated per Code Quality §1):** all 197
existing tests; in particular `ThemeTests` motion/space/radius/waveformBars/sparkline
(`ThemeTests.swift:7-33`) must stay untouched-green through the retint, proving the
retint changed only color constants, and `FolderTests.swift:22` keeps covering
`folderMeetingCounts()` (V) for the sidebar-counts commit.

**Behavior verification without UI tests:** the §5 screenshot matrix is the visual
proof (fixture mode); `swift build` + `swift test` are the gates (no linter exists in
the repo — V §method). Purely presentational styling (insets, serif size) gets no
render tests; every behavior-bearing piece (nav mapping, predicates, visibility,
counts, hex constants) has a unit test above.

---

## 8. Ordered commits (each builds, tests green, app runnable)

| # | Commit | Contents | Depends |
|---|---|---|---|
| 1 | `feat(v2-t1): retint dark theme tokens, add glow and section font` | `Theme.swift` hex constants + 3 retints + `accentGlow` + `titleFont` 32 + `sectionFont`; `ThemeHexTests` (fails-first, then green) | — |
| 2 | `feat(v2-t1): replace dictation-history bool with AppSection nav state` | `AppSection.swift` + `AppState` stored `section` (9-site migration table §1.2); `AppSectionTests`; zero visual change | 1 |
| 3 | `feat(v2-t1): add Meetings, Notes and Files destinations` | sidebar items (reuse `SideItem`), `PageHeader`, `MeetingsLibraryView`/`NotesView`/`FilesView` reusing `HomeMeetingRow` + honest empties; `MeetingLibrary` predicates + tests; Home insets 32→28, drop 780 cap | 2 |
| 4 | `feat(v2-t1): show folder counts in sidebar` | `AppState.folderCounts` wired to `folderMeetingCounts()` refresh points (load, create/move/delete meeting, folder CRUD); query itself already covered by `FolderTests.swift:22` (V) — the wiring is straight-line glue over it | 3 |
| 5 | `feat(v2-t1): add inspector column with width breakpoints` | `WidthClass` + tests, `MainWindow` router + `onGeometryChange`, `InspectorColumn`, `DictationSessionInspector` (§4.6 states), toggle button, crossfades; `InspectorVisibilityTests` | 2 |
| 6 | `feat(v2-t1): focus sidebar search with cmd-k` | `SearchCommands` + `AppState.searchFocusRequest` + `SidebarView` FocusState | 3 |
| 7 | `feat(v2-t1): add debug fixture mode and t1 shot matrix` | `AppDatabase.open(at:)` overload, `--v2-fixture` seeds, shot procedure doc in commit body, idle-CPU before/after recorded in `docs/wip/` | 1-6 |

Commit bodies carry the why (retint rationale = refs cooler than warm brown; bool →
enum = nav model for five destinations; inspector occupant = §4.6 tension + chosen
default). Reversal: every commit reverts independently; no schema, no persisted
shape anywhere in the sequence.

---

## 9. Exclusions and dependency constraints (later slices)

| Excluded from T1 | Owner | Constraint T1 leaves in place |
|---|---|---|
| Player, peaks, ±15 s, speed, chapter markers | T4 (S1/S2 first) | no `AVAudioPlayer` introduced; Meeting detail keeps `RecordingBar` |
| Transcript pagination, ⌘F, speaker filter, talk-time | T5 (S3) | transcript list untouched; no ⌘F chrome painted |
| Dictation library chrome: filter, load-more, type tabs, grid, live waveform, mic/lang pickers | T2a | `DictationHistoryView` internals untouched except page title; inspector adds no `TimelineView` |
| Dictation metadata migration (v9) | T2b + H (Q6/Q4) | no schema change in T1; G3 before any v9 |
| Live stage, Pause/Resume, mark moment, live AI | T3 / Q1 / Q2 | engine untouched; HUD unchanged |
| Meeting tab renames (Overview/AI Notes/Tasks), inspector details content | T4 / Q6 | `Tab` enum :16-20 untouched; Tasks never aliased to Action Items (C1) |
| Permissions health strip, Rescan, languages layout | T6 | `PermissionsListView` unchanged (already honest); G8 applies there |
| Notes/Files dedicated objects, tags, attachments | T7 / Q6 | destinations show derived data only |
| Integrations, sharing URLs | T8 / Q3 | sidebar shows no Slack/Notion/Linear/Jira rows |
| Accuracy substitute | Q8 | four-stat row only |
| Light mode | pending a light ref | dark-only |
| Localization | Q9 | English chrome |
| 24 fps overlay change | T9 / G10 | overlay stays 30 fps |

Cross-review issues resolved by this map: Grok-on-GLM I2 (Notes/Files shipped as
dests — §2/§4.7), I10 (Family A shell recorded, Live Recording is a state — §2),
I11 (no fake n-of-6 — §4.7 Settings row), I7 (network surfaces: T1 adds none — §6);
GLM-on-Grok I1 (overlay+inspector one session — T1's inspector is read-only, §4.6),
I7 (captions geometry 656 panel / 640 card cited correctly — §1.1), I3/I5 (no fps or
shortcut mistakes introduced — §4.5/§6). Issues concerning later slices (I1 Tasks,
I3 Pause, I4/I5 stage/peaks, I6 Accuracy, I8 migration precedent, I9 moments, I13
tags, I14 channels, I2/I15 budgets/tests) are carried by the contract's C1–C21
mapping and the owners above; none is silently decided inside T1.

---

## 10. GO/NO-GO

**GO.**

Rationale:

1. **No one-way door is touched.** No schema, no engine, no auth/cloud/billing/
   retention/token contract, no new dependency, no persisted shape. Every commit
   reverts independently (§8).
2. **The product contract explicitly green-lights T1 before §9** (contract §10.4:
   "T1 can start… It must not paint Pause, Accuracy %, Synced-to, fake n-of-6,
   ⌘F-without-search, play-without-files, or live AI copy" — §2/§4/§5 enforce each).
3. **All in-slice decisions are reversible visual/layout picks already made by the
   contract** (§2: Family A geometry, dark tokens, serif 32, inspector 300/collapse,
   Stop-only chrome, Settings scene unchanged).
4. **Preserved behaviors are verifiable** (§1.4 of the contract maps to V seams in
   §1 here; the 197-test suite plus the fixture matrix covers them).

**Minimal human decision still required (non-blocking, reversible):** confirm the
T1 inspector occupant (§4.6) — default **Dictation session panel with honest idle
state**; alternative **mechanism-only, hidden until T2a**. If unanswered, implement
the default and record it in the PR description.

**Blocked-forever-on-nothing:** nothing in T1 waits on §9 Q1–Q9.

---

*End of map. Implementer starts at §8 commit 1 in a fresh code lane; this file is
history the moment it is written and is superseded by the implementing PRs.*
