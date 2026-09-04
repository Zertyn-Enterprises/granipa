# Grañipa V2 — product / UI contract (T0)

Lane `v2-contract-grok` · branch `docs/v2-contract-grok` · base `feat/granipa-v2@e90bb91`.
This file is the executable contract for T1–T10. It reconciles:

- GLM architecture audit `docs/wip/2026-09-04-v2-audit-glm.md`
- Grok visual/interaction audit `docs/wip/2026-09-04-v2-audit-grok.md`
- GLM→Grok review `docs/wip/2026-09-04-v2-review-glm-on-grok.md` (I1–I7)
- Grok→GLM review `docs/wip/2026-09-04-v2-review-grok-on-glm.md` (I1–I15)

**Scope of this file:** product, visual, architecture, budgets, migration *proposals*, and T1–T10 definition of done. No Swift, schema, settings, or durable-doc edits accompany it.

**PNGs:** `/private/tmp/granipa-v2-refs.V0xiDo/01`…`10` (all 1448×1086). This session did not re-open them. Pixel claims are **V-img** from the two audits; GLM-on-Grok re-inspected 03, 06, 08, 09. Code claims are **V** against this worktree.

Product name: **Grañipa**. IntentX, mindtale.ai, Alex Morgan, Pablo Vega, Pro Plan, usage meters, 96% Accuracy, named “Synced to” rows, photographic faces, and Solver Operational Controls copy are reference chrome. They are not product claims.

---

## 1. Normative principles and evidence labels

### 1.1 How to read this file

| Label | Meaning |
|---|---|
| **V** | Verified this session in source (`path:line`). |
| **V-img** | Verified as pixels in a named PNG by a T0 audit/review. Not re-opened here. |
| **V-prev** | Measured in lineage docs (`docs/wip/2026-09-04-hang-handoff.md`, optimize-*). Cited, not re-measured. |
| **P** | Proposal. Reversible. Implementers may ship it; they may not treat it as measured fact. |
| **H** | Human one-way door. Listed in §9. Not chosen here. Chrome that needs **H** stays in the inventory and stays out of the hot path until answered. |
| **U** | Unverified inference. The check that would confirm it is named. |

Classes used in §4:

| Class | Meaning |
|---|---|
| `current` | Ships today. Preserve. |
| `presentation-only` | Visual of real data, or decorative motion. No new persistence. Must not look like a measured claim it is not. |
| `new-reversible` | New UI/behavior. No persisted contract. Can revert with a code revert. |
| `new-persisted` | Needs an append-only migration or a new file next to audio. Representation is a **proposal** until §9 answers (or T7/T2 explicitly adopts a listed proposal). |
| `external-contract` | Local API, webhooks, Sparkle, rewrite HTTP, Muse. Changing shape is a one-way for clients. |
| `excluded-fiction` | Do not ship. Fake SaaS, people, percentages, provider state, AI output, or actions. |
| `human-decision` | One-way or persisted-shape door. Visible in refs; not implemented as if decided. |

A control may carry two classes (example: Tasks tab = `new-reversible` IA + `human-decision` persisted shape). Both are stated. Neither is collapsed.

### 1.2 Product principles (normative)

1. **Honest mock.** Empty, loading, error, and live states are real. Do not paint chrome that no-ops (`⌘F` with no search, Pause with no engine, play on a row with no file, “2 of 6” that is not the count).
2. **Complete product, not the easiest subset.** Every real feature implied by images 01–10 stays in the inventory: Tasks, Notes, Files, Pause/Resume, Accuracy, playback channels, tags/favorites, dictation audio, sharing, participants, integrations. Absence of a table today is not “out of V2”.
3. **Do not fake.** No invented people, photos, billing, quotas, accuracy percentages, Synced-to providers, Google Doc/Slides stand-ins, live AI paragraphs, or health math that contradicts `PermissionState`.
4. **Preserve working behavior** (§1.4). V2 redesigns the shell; it does not rip out dictation, clipboard, recording, local storage, export, email draft, or battery.
5. **Capture pipeline freeze.** No writer / coalescing / padding / AEC / live-ASR-default change without a Record profile. `usesLiveASR` stays default **false** (**V** `MeetingASRPolicy.swift:13-17`). Meeting AEC stays hard-off (**V** `RecordingEngine.swift:65-69`). Hang pids **25501 / 62139** remain binding (**V-prev** hang-handoff).
6. **Single capture.** One mic at a time. Meeting recording wins (`DictationError.micBusy`, **V** `DictationController.swift:161`). Overlay and inspector bind the same `DictationController`. No second engine.
7. **Timestamps** are meeting-relative seconds everywhere (transcript, diarization, API, bookmarks, player). **V** `AGENTS.md`.
8. **Migrations are append-only.** Never reorder. New columns nullable. New tables additive. Destructive retention is **H**.
9. **No new top-level dependency** unless the human explicitly adds one. SwiftUI + GRDB + FluidAudio 0.15.2 + Sparkle stay.
10. **Minimum resource use.** New UI observers reuse gated RMS. A live waveform may only republish already-gated levels at **≤ 12 Hz** and render at **≤ 24 fps** (**P** — 24 fps is a proposal; see §6.3). Reduce Motion is mandatory on every new `TimelineView`.
11. **English chrome** until **H** localization. Transcript/notes/dictation content already follows the meeting/utterance language. Do not fake bilingual previews.
12. **Light appearance is pending.** Every ref is dark. The app forces `.dark` (**V** `MainWindow.swift:53`, `SettingsView.swift:26`, overlays). Do not ship light tokens.

### 1.3 Explicit corrections (do not repeat the audits' mistakes)

These are the known mistakes the reviews named. The rest of this contract is written as if they were never true.

| # | Wrong claim | Correct contract | Source |
|---|---|---|---|
| C1 | Tasks = Action Items, no table | Both tabs stay. Counts may differ. Empty Tasks is allowed until **H** picks same rows / second list / derived filter. Do not ship Overview as “Tasks = Action Items”. | Grok→GLM **I1**; images **01, 08, 10** (**V-img**) |
| C2 | Notes and Files are out of smallest V2 | Both are real sidebar destinations from T1, with honest empty/error states. Object schema is T7 / **H**. Do not treat “no table today” as “omit the dest”. | Grok→GLM **I2**; images **01, 02, 04–10** (**V-img**); sidebar today is Home + Dictation only (**V** `SidebarView.swift:23-38`) |
| C3 | Resume = re-record into the same folder; Pause deferred separately | **One** door: pause/resume of a live session vs stop-only vs append/re-record after Stop. Until then Pause and Resume stay in the inventory and **out of the engine slices**. Stop today is terminal per meeting (**V** `RecordingEngine.swift:15-30, 169-180`). | Grok→GLM **I3**; images **04, 08, 10** |
| C4 | Live recording stage is “only the view is new” | HUD restyle (timer, dual meters, Stop, warnings, “Transcript after you stop”) is composition. Stage extras (full waveform, mark moment, mic picker, Pause, rings, live AI) are seams or **H**. Do not treat T3 as a HUD restyle. | Grok→GLM **I4** |
| C5 | Capture-time peaks on the Record path; C14 depends on C2 | Post-stop peaks = file scan after Stop (and legacy backfill). Live Record UI keeps gated meters + 1 Hz timer. A live sparkline, if shown, **only** reuses already-gated RMS at ≤12 Hz publish / ≤24 fps render / Reduce Motion = static. T3 does **not** depend on the peaks extractor. | Grok→GLM **I5**; this task’s Record-path rule |
| C6 | Accuracy ring blocked by billing/metering | Accuracy is a separate undecided substitute (omit vs real metric). Quota/Upgrade/Pro Plan stay `excluded-fiction`. | Grok→GLM **I6**; images **02, 07, 09** |
| C7 | “No external HTTP except Muse/webhooks” | HTTP today = Muse WebSocket, HMAC webhooks, optional rewrite (`RewriteClient` → `https://api.x.ai/v1` or custom URL, **V** `RewriteClient.swift:21-22, 99-107`), Sparkle (**V** `Package.swift:11, 19`, `UpdaterManager.swift:11-23`). No OAuth. Integrations remain **H**. | Grok→GLM **I7** |
| C8 | `ActionItem.done` as a nullable-column migration precedent | `done` is an optional **JSON field** on `actionItemsJSON` (**V** `ActionItem.swift:5`, `LLMTests.swift:49-59`). Column adds use `alter(table:)` — cite **v4 `folderID`** (**V** `AppDatabase.swift:95-97`). Keep G3. | Grok→GLM **I8** |
| C9 | C11 = dictation cards + meeting Key Moments | Split. Dictation library ≠ meeting Key Moments. Moments ride the meeting bookmark/player slices. | Grok→GLM **I9** |
| C10 | One sidebar family | Three families. Canonical shell is chosen in §2 (reversible). Live Recording is a **meeting state**, not a fourth IA. | Grok→GLM **I10**; Grok audit §2 |
| C11 | Image 03 health copy is normative; `installedLocales` = “models up to date 9:41 AM” | Derive *n of 6* from real `PermissionState`. Do not copy “2 of 6”. Installed vs not is allowed; a freshness clock is not. | Grok→GLM **I11**; GLM-on-Grok agreement 1 |
| C12 | Image 07 “minus live panel” | 07 = library + live inspector, **no** in-list live card. Canonical vs 02’s duplicate card+panel. | Grok→GLM **I12** |
| C13 | Tags = JSON column on meeting, folded into dictation v9 | Tags representation (blob vs table) is **H**. Meeting tags are not dictation metadata. | Grok→GLM **I13** |
| C14 | Playback maps to system channel or a chosen channel | Single transport. Mixing vs one channel vs A/B toggle is **H**. Player tests must not assume system-only. | Grok→GLM **I14**; dual files **V** `Meeting.swift:25-26` |
| C15 | Overlay vs inspector left both decided and unresolved | Overlay **and** inspector, one `DictationController` session. Duplicate live **card** is rejected. Not an open question. | GLM-on-Grok **I1**; Grok §2/§6 |
| C16 | Additive GRDB only if doors 3/5/8/9/10 ship | Bookmarks, chapters, dictation metadata, key moments, enhance timestamp also need append-only migrations if those features persist. Tags/favorites are persisted-shape **H**. | GLM-on-Grok **I2** |
| C17 | “30 fps already over budget” | **P:** cap new/changed render at ≤ 24 fps. Current dictation overlay is 30 fps (`DictationOverlayView.swift:161-164`) on ~12.5 Hz samples (`LevelGate(minInterval: 0.08)`, **V** `DictationController.swift:32`). Cost is unmeasured. Profile before changing. Reduce Motion already pauses the overlay TimelineView. | GLM-on-Grok **I3** |
| C18 | Wrong file/line citations in Grok §3 | `SegmentRow` lives in `MeetingDetailView.swift:328-362`. `AvatarView` lives in `Theme.swift:109-132`. Motion tokens `Theme.swift:50-51`. Title fonts `Theme.swift:34-35`. | GLM-on-Grok **I4** |
| C19 | Mark action `⌘M` | Mark action is **⌘⇧M** (**V-img** image 04). Mark moment is **⌘B**. | GLM-on-Grok **I5** |
| C20 | Ultra-lightweight budgets omit memory, DB writes, startup, writer queue, LLM cancel | §6 imports GLM’s budget table and G1–G5, plus G6–G10 from the reviews. | GLM-on-Grok **I6**; Grok→GLM **I15** |
| C21 | Captions geometry = 640 | Captions **panel** 656×176 (fixed bounding box, **V** `CaptionsOverlayController.swift:11`). **Card** width 640 (**V** `CaptionsOverlayView.swift:40`). | GLM-on-Grok **I7**; Grok→GLM agreements |

### 1.4 Current working behavior that V2 must preserve

Do not regress these. T1–T10 add around them.

| Behavior | Evidence |
|---|---|
| Hold-to-talk dictation. Default binding Right Option (`kVK_RightOption`, AppStorage `dictationShortcut` default `"rightOption"`). Right Command and ⌥Space are supported. Quick tap toggles; Esc cancels while held, not in toggle. Accessibility required for modifier-only keys so they work in other apps. | **V** `SettingsView.swift:293-320`, `AppState.swift:97-115`, `DictationController.swift:36-43, 45-68`, `HotkeyManager.swift:7-8, 62-63` |
| Right Command dictation specifically remains a working path (user-validated). | **V-prev** `docs/wip/2026-09-04-optimize-results.md`; tests `HotkeyBindingTests.swift` |
| On stop/release: transcribe → optional rewrite → `PasteService` Cmd-V into the front app → `DictationEntry` insert + prune keep-2000. | **V** `AppState.swift:117-124`, `AppDatabase.swift:258`, `PasteService.swift:19-35` |
| Meeting recording: mic + system m4a, silence-pad so file time == meeting time, Stop-only engine, file ASR after Stop by default. | **V** `RecordingSession.swift:270-319`, `RecordingEngine.swift:15-90`, `AppState.swift:367-420` |
| Dual-channel files `audioMicPath` / `audioSystemPath`. | **V** `Meeting.swift:25-26` |
| Local GRDB at `~/Library/Application Support/Granipa/granipa.sqlite`, migrations v1…v8. | **V** `AppDatabase.swift:12-135` |
| Export Markdown via save panel; copy transcript. | **V** `MeetingExporter.swift:54-75` |
| Email draft on Enhanced notes (absent from refs — **keep**). | **V** `EnhancedNotesView.swift:84-109` |
| Enhance now / Re-enhance. | **V** `EnhancedNotesView.swift:43, 131-141` |
| Battery readout + optional SMC charge limit via `GranipaBatteryHelper`; restore charging on quit. | **V** `GranipaApp.swift:8-9`, `BatteryService.swift`, Settings Extras → Battery |
| Clipboard history panel ⌥⇧V; OCR ⌥⇧T; emoji ⌥⇧E; dictation history panel ⌥⇧H. | **V** `MenuBarView.swift:65-80`, `ShortcutHub.swift:62-71` |
| Floating recording HUD (compact pill / expanded 520). Do not delete it if a live stage ships. | **V** `RecordingHUD.swift:66-183`, `GranipaApp.swift:45-53` |
| Captions overlay when live ASR + captions prefs. | **V** `MeetingASRPolicy.swift:19-39` |
| Detection banner + Record from detection. | **V** `MainWindow.swift:29-34, 87-111` |
| Folders (collections), templates, local API (opt-in, localhost + bearer), HMAC webhooks. | **V** models + `APIRouter.swift` + `WebhookService.swift` |
| Menu bar Record / Dictate / pipeline status. | **V** `MenuBarView.swift` |
| Dark-only color scheme. | **V** `preferredColorScheme(.dark)` on main, settings, overlays |
| “Transcript after you stop” when live ASR is off. | **V** `RecordingHUD.swift:167-170` |
| Speaker rename. | **V** `MeetingDetailView.swift:44-58`, `AppDatabase.swift:419-424` |
| Onboarding: “no accounts, no telemetry”. | **V** `OnboardingView.swift:47` |

Settings → General still shows “Echo cancellation (mic)” (**V** `SettingsView.swift:204`). Meeting Record ignores it (AEC hard-off). Do not re-enable AEC on the Record path to make the toggle “work”.

---

## 2. Canonical shell, layout, theme, motion

Reversible visual contradictions are resolved here so T1 is not blocked. Light mode stays pending. One-way doors stay in §9.

### 2.1 Shell families → one canonical shell

| Family | Images | Traits |
|---|---|---|
| A | 01, 02, 07, 08, 09, 10 | Search **in** the sidebar; Meetings dest; Linear (ignored); usage-week (excluded); Alex Morgan (excluded) |
| B | 04, 05, 06 | Wordmark; **Live Recording** dest; Search as a **nav row**; Jira (excluded); Pro Plan GB (excluded); Pablo (excluded) |
| C | 03 | Settings tabs matching current Settings (**V** `SettingsView.swift:8-22`) |

**Adopt (reversible):**

- **Geometry of Family A:** hidden title bar, traffic lights over left chrome, search field in the sidebar, Home + Dictation + Meetings + Notes + Files + Collections.
- **Live Recording is a meeting state**, not a sidebar destination. When the recording’s meeting is selected, the content column is the live stage (Family B’s stage). The floating HUD always remains. Sidebar footer already shows a Recording indicator (**V** `SidebarView.swift:98-108`) — keep it.
- **Settings stays the macOS Settings scene** (Family C). Do not rebuild Settings as an in-window third IA.
- **Home** is the inbox (calendar hero + recent meetings). **Meetings** is the full library (same rows, no calendar hero, folder filter). Opening a meeting from Home keeps Home highlighted (compatible with current `isHomeActive`, **V** `SidebarView.swift:11-13, 23-28`). Opening from Meetings highlights Meetings.
- App name **Grañipa**. No IntentX wordmark. Icon remains `Resources/icon-512.png`.
- Footer: **Settings** link (current), not a fake account/plan row.
- Integrations in the sidebar: **Calendar** may show EventKit status or deep-link Settings. Slack / Notion / Linear / Jira **hidden** until §9. Local API + webhooks stay in Settings → Integrations.
- Usage / Upgrade / Pro Plan / account menus: `excluded-fiction`.

**Rejected as product paint:** image 09 crushed darker chrome (`#0C0F12`); image 04 true gray `#161616` as a third theme; Record button offered while already recording (04).

### 2.2 Dark color tokens (adopt)

Current Theme is warm brown (`bg #161412`, `bgSidebar #1C1A18`, `card #232120`, **V** `Theme.swift:14-16`). Refs are cooler. T1 retints dark tokens to the table below. Accents, status, channel, and brand overlay colors stay.

Light column is **not adopted**. Listed only so a future light frame has a starting map. **U** until a light PNG exists.

| Token | Role | Dark (normative) | Current (V) | Evidence |
|---|---|---|---|---|
| `bg` | Window / content | `#141617` | `#161412` | **V-img** content ~`#131312`–`#191B1D` (Grok §3.1) |
| `bgSidebar` | Sidebar | `#17191A` | `#1C1A18` | **V-img** sidebar ~`#17191A`–`#191C1D` |
| `card` | Surfaces | `#1E2123` | `#232120` | **V-img** cards ~`#1B1B1B`–`#242526` |
| `border` | Hairline | white 7% | same | **V** `Theme.swift:17` |
| `strokeStrong` | Overlay edge, selected | white 12% | same | **V** `Theme.swift:27` |
| `fillSubtle` | Active nav, chips | white 8% | same | **V** `Theme.swift:25` |
| `fillHover` | Hover wash | white 4% | same | **V** `Theme.swift:26` |
| `accent` | Primary CTA, tab ink, playhead | `#F05423` | same | **V** `Theme.swift:18`; **V-img** Record/waveform `#E05020`–`#F86018` |
| `accentGlow` | Record bloom | accent @ 40% | n/a | **V-img** 01, 04. Static. No pulse when Reduce Motion |
| `textPrimary` | Titles, body | white 92% | same | **V** `Theme.swift:21` |
| `textSecondary` | Meta, tabs idle | white 55% | same | **V** `Theme.swift:22` |
| `textTertiary` | Timestamps, hints | white 34% | same | **V** `Theme.swift:23` |
| `statusListening` | Live / rec / denied | `#E24B4A` | same | **V** `Theme.swift:28` |
| `statusProcessing` | Transcribe / enhance | `#5B8DEF` | same | **V** `Theme.swift:29` |
| `statusDone` | Granted, saved | `#4CD981` | same | **V** `Theme.swift:30` |
| `statusLoading` | Not asked / unknown | `#E6C35C` | same | **V** `Theme.swift:31` |
| `statusFailed` | Failed / warning | `#E08A3C` | same | **V** `Theme.swift:32` |
| `channelMe` | Mic / Me | `#6FA8DC` | same | **V** `Theme.swift:24`; `MeetingDetailView.swift:334` |
| `brandPurple` / `brandPink` | Dictation overlay waveform **only** | `#7C5CFF` / `#E879A8` | same | **V** `Theme.swift:19-20`; `DictationOverlayView.swift:170-174`. Meeting waveforms are orange-only |

Do not invent a 7th status color. 03 “Not checked” maps to `statusListening` (action needed) or the existing Unchecked empty-badge + Check button. 03 “Unknown” maps to `statusLoading` / Not asked.

**Avatar palette:** keep `Theme.avatarColor` (**V** `Theme.swift:52-60`, `AvatarView` `Theme.swift:109-132`). Letter avatars. No photographic faces from the refs.

`ThemeTests` today lock motion, space, radius, `waveformBars == 40`, sparkline 52 (**V** `ThemeTests.swift:7-32`). T1 updates tests that pin hex if any are added; existing duration/scale assertions stay.

### 2.3 Type scale

| Role | Spec | Notes |
|---|---|---|
| Page title | 32 semibold **serif** | Brand pick (reversible). Current `Theme.titleFont` is 34 serif (**V** `Theme.swift:34`). Refs are sans 28–32 (**V-img**). Grañipa keeps serif for Home / Dictation / Permissions / Onboarding titles. T1: 34 → 32. |
| Meeting title | 28 bold (sans) | Keep `Theme.meetingTitleFont` (**V** `Theme.swift:35`). Matches 01/05/08/10 scale. |
| Section | 16 semibold | Inspector and Overview card titles |
| Body | 15 regular, lineSpacing 7 | `SegmentRow` (**V** `MeetingDetailView.swift:354-356`) |
| Meta | 12 regular | Timestamps, chips, sidebar secondary |
| Tab | 13 semibold active / regular idle | **V** `MeetingDetailView.swift:185` |
| Numeric / timer | tabular figures | Live stage and dictation inspector: **HH:MM:SS** (**V-img** 04, 02). RecordingTimer today is `m:ss` (**V** `RecordingSharedViews.swift:54-56`) — extend when elapsed ≥ 1 h; keep `m:ss` under 1 h. Transcript stamps **M:SS** / **H:MM:SS** from `startSeconds`. |
| Dictation overlay body | 15.5 medium | Keep (**V** `DictationOverlayView.swift:16`) |

Do not copy IntentX marketing subtitles. Dictation empty copy stays honest: “Hold {`DictationController.shortcutLabel`} to dictate.” (**V** `DictationHistoryView.swift:159`).

### 2.4 Spacing, radius, border, shadow, glow

Keep the tested scale (**V** `ThemeTests.swift:16-22`):

| Token | Value |
|---|---|
| `spaceM` | 12 |
| `spaceL` | 16 |
| `spaceXL` | 24 |
| `radiusS` | 8 (chips, badges) |
| `radiusM` | 12 (cards, rows) |
| `radiusL` | 16 (large cards) |
| `radiusOverlay` | 24 (HUD, health, settings overlays) |
| Nav active | 10 continuous (**V** `SidebarView.swift:216`) |

- Content horizontal inset on three-pane screens: **28** (meeting header, **V** `MeetingDetailView.swift:116`). Do not keep Home’s `maxWidth 780` / inset 32 on three-pane (**V** `HomeView.swift:94-98`).
- Card border: 1 px `border`. Selected transcript row / live inspector: 1 px `accent`.
- Shadow: overlays only (dictation overlay black 28% r18 y8, **V** `DictationOverlayView.swift:39`; captions r20 y8, **V** `CaptionsOverlayView.swift:45`). Main-window cards are **flat**.
- Glow: static `accentGlow` on Record / Stop. **No pulse** when Reduce Motion.
- Density: 8 pt grid. Rows ~44–56 pt. No empty hero padding on three-pane screens.

### 2.5 Iconography

SF Symbols. No Slack/Notion/Linear/Jira marks unless that integration is approved (**H**).

| Dest | Symbol |
|---|---|
| Home | `house.fill` (current) |
| Dictation | `mic.fill` |
| Meetings | `calendar` |
| Notes | `note.text` |
| Files | `folder` (library) — recordings use `waveform` |
| Collections | `folder` (current) |
| Record | `record.circle` |
| Live | `record.circle.fill` + `statusListening` dot |

### 2.6 Geometry and breakpoints

**Verified current:**

| Surface | Size | Source |
|---|---|---|
| Main min | 960×600 | `MainWindow.swift:55` |
| Main default | 1120×720 | `GranipaApp.swift:28` |
| Sidebar | 248 | `MainWindow.swift:21` |
| Settings | 640×600 | `SettingsView.swift:24` |
| Onboarding | 540×600 | `OnboardingView.swift:26` |
| Dictation overlay **view** | 440×132 | `DictationOverlayView.swift:30` |
| Dictation overlay **panel** | 472×164 | `DictationOverlayController.swift:6` (view + padding) |
| HUD expanded | width 520 | `RecordingHUD.swift:175` |
| Captions **card** | width 640 | `CaptionsOverlayView.swift:40` |
| Captions **panel** | 656×176 | `CaptionsOverlayController.swift:11` — fixed, no `fittingSize` while captions update |

**Adopt:**

| Window width | Layout |
|---|---|
| `< 960` | Not supported. Keep `minWidth 960`. |
| `960–1279` | Sidebar **248** + content. Inspector **collapsed**. Toolbar button reveals a trailing overlay, min width **280**. Live dictation inspector is the **existing floating overlay** at this width (do not mount a second live surface). |
| `≥ 1280` | Sidebar **248** + content + inspector **300**. |
| Default | **Keep 1120×720.** First launch is two-pane (inspector collapsed). Three-pane appears when the user widens the window. Raising default to 1280 is not required and is not a blocker. |

Inspector is new. Grep: no `NavigationSplitView`, no `.inspector(` (**V** this session). T1 may use `NavigationSplitView`, an `HStack` third column, or SwiftUI `inspector` — pick the smallest that respects collapse. No new framework.

### 2.7 Motion

Keep existing tokens (**V** `Theme.swift:50-51`, `PanelMotion.swift:6-9`, `ThemeTests.swift:7-13`):

| Token | Value | Use |
|---|---|---|
| `Theme.motionFast` | 0.08 s | Hover |
| `Theme.motionNormal` | 0.15 s | Banner, phase crossfade |
| `PanelMotion.show` | 0.34 s, rise 40 | Overlay appear |
| `PanelMotion.hide` | 0.20 s | Overlay disappear |

**Reduce Motion** already read at `MainWindow.swift:7, 32-34, 47-48`; `Theme.swift:88, 97-98`; `DictationOverlayView.swift:5, 43-45, 161-164`; `PanelMotion.swift:19-21, 33-36, 49-53`.

Contract for every new motion:

- No concentric-ring pulse (04). Omit rings, or draw static rings.
- No Record glow pulse; static bloom OK.
- Waveform: last samples as a static `Canvas` when Reduce Motion; **pause** `TimelineView` (overlay already does).
- Inspector/sidebar layout changes: opacity crossfade only, no slide.
- Auto-scroll: jump, do not animate.
- Do not add springy per-bar waveform animation on the meeting player.

**24 fps** is a **proposal** (§6.3). Do not lower the dictation overlay from 30 fps until Instruments shows a benefit. New meeting-stage waveforms, if any, must start at ≤ 24 fps and Reduce Motion static.

### 2.8 Chapter / player chrome (one system)

Images disagree: colored dots (01), named flags on the waveform (05), numbered badges (08), chips under the player (10). Volume appears only on 06.

**Adopt (reversible):**

- **Named markers on the waveform** when a moment has a label (05).
- **Numbered markers** when a moment has no label (08 fallback).
- **No second chip strip** under the player (do not ship 10’s strip on top of 05).
- Jump-to-moment is clicking a marker (and, once search exists, Jump to in the transcript footer).
- `1x` speed control: yes, post-stop player.
- ±15 s: yes (present on 05, **V-img**).
- Volume: omit until T4 profiles a real mixer; 06-only is not enough to add a third hot control. **H** if someone wants it later — reversible, not a door.
- Expand: full-width player / hide inspector. Reversible.

### 2.9 Dictation live surfaces (one system)

- **Floating overlay:** keep for hold-to-talk in any app (current product).
- **Inspector:** when Dictation is selected **and** width ≥ 1280 **and** a session is active, show the live inspector bound to the same `DictationController`.
- **No in-list live card** (reject 02’s duplicate; 07/09 are canonical).
- Narrow window: overlay only.

This is decided. It is not §9.

---

## 3. Screen-state contracts

Every screen: ready / empty / loading / error / live. Controls list action, shortcut, accessible label, compact behavior, proving image. Copy must be honest.

Shared chrome (all non-Settings screens):

| Control | Action | Shortcut | A11y | Compact (960–1279) | Evidence |
|---|---|---|---|---|---|
| Sidebar Search | Filters meetings (+ later Notes/Files). Binds `app.searchQuery` | **⌘K** focuses the field (new; no binding today, **V**) | “Search Grañipa” | Stays in sidebar | **V** `SidebarView.swift:148-175`; **V-img** 01, 02, 07–10; ⌘K **V-img** 05 |
| Home | Inbox | — | “Home” | — | current |
| Dictation | Library | — | “Dictation” | — | current |
| Meetings | Full library | — | “Meetings” | — | **V-img** 01; new dest |
| Notes | Global notes dest | — | “Notes” | — | **V-img** 01–02, 04–10 |
| Files | Recordings + later attachments | — | “Files” | — | same |
| Collections | Existing `Folder` + **counts** from `folderMeetingCounts` | — | folder name | — | **V** SQL `AppDatabase.swift:284-295` API-only today (`APIRouter.swift:129`) |
| Add folder | Current alert | — | “Add folder” | — | **V** `SidebarView.swift:89` |
| Quick note | `createMeeting` | — | “Quick note” | Icon+label may collapse to icon | **V** `HomeView.swift:47-54` |
| Record | `startRecording` if `!recorder.isBusy` | — | “Record” | Pill stays | **V** `HomeView.swift:56-68` |
| Settings | `SettingsLink` | ⌘, (system) | “Settings” | — | **V** `SidebarView.swift:110-120` |
| Detection banner | Record / Dismiss | — | “Meeting detected: {app}” | Full width over content | **V** `MainWindow.swift:87-111` |
| Inspector toggle | Show/hide inspector overlay | — | “Show inspector” / “Hide inspector” | Only control that reveals inspector | new |

Header Record is **disabled** while `recorder.isBusy`. Do not offer Record on a live stage (04 rejected). If §9 picks Pause, Record is replaced by Pause/Resume/Stop on that meeting — not a second Record.

### 3.1 Home

**Role:** Inbox. Not shown as a dedicated ref; inferred from “Back to Home” (01, 08, 10) + current `HomeView`.

**Data:** `app.meetings`, `app.calendar.upcoming`, `app.searchQuery` → `searchMeetings` (200 ms debounce, **V** `HomeView.swift:100-116`). Inspector: **off** on the list (refs never show an inspector on a meeting list).

| State | What the user sees | Copy / behavior |
|---|---|---|
| Ready | Serif title “Coming up” if next EventKit event, else “Notes” (current) or folder name / “Search”. Day-grouped rows. Pipeline phase labels when live. | Real titles, real times. Sparkline: keep seeded fake **only** as `presentation-only` until post-stop peaks exist; then replace per-row when a peaks sidecar exists, else omit (do not keep lying once real peaks exist for other rows). |
| Empty | Calendar-badge icon + “No meetings yet” / “No meetings in this folder” / “No results for …” | **V** `HomeView.swift:119-154`. Quick note + Record. |
| Loading | Search in flight: keep previous rows or empty; do not shimmer fake meetings | Debounce 200 ms; cancel on query change |
| Error | `app.loadError` alert (current) | Permission-looking errors offer Open Settings (**V** `MainWindow.swift:69-78`) |
| Live | A recording meeting shows phase “Recording” in its row; Record button disabled | Selecting it opens the live stage (§3.3) |

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Hero upcoming card | Open / Record into that calendar event | — | event title | Stacks | **V** `HomeView.swift:157+`; real EventKit, not mock participants |
| Meeting row | Open meeting | — | “{title}, {time}” | Sparkline may hide | current |
| Context: folder / export / copy / delete | current | — | match button title | — | **V** `HomeView.swift:274-298` |

Selecting a meeting: Overview if audio or recording exists; Notes editor if quick note (current tab heuristic, **V** `MeetingDetailView.swift:23-27`) — once Overview exists, recorded meetings land on Overview.

### 3.2 Dictation — idle library

**Data:** `fetchDictationEntries` (limit 500 today, **V** `AppDatabase.swift:209`), `dictationStats`. Stats formulas: WPM from words/duration; time saved = words / 40 WPM (**V** `DictationEntry.swift:32-40`, pinned `DictationHistoryTests`).

| State | What |
|---|---|
| Ready | Period picker, search, **four** real stats (WPM, words, apps, saved). Day groups. Load more if n > page size. |
| Empty | “No dictations yet” + hold-shortcut hint; or “No matches” | **V** `DictationHistoryView.swift:149-168` |
| Loading | Period/search reload; keep previous; 140 ms debounce (**V** `:80-86`) |
| Error | DB miss → empty + loadError |
| Live (library) | No in-list live card. Inspector (§3.2b) and/or overlay. A playing row is **H** until dictation audio exists |

**Accuracy tile:** omitted until §9. Do not show 96%. Do not show a blank ring. Stats row is four cells, not five.

**App logos:** count is real; vendor glyphs are `presentation-only` and **off** until that app is a real `sourceApp` string (show the string, not a Slack mark).

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Period | `DictationPeriod` today / week / all | — | “Period” | Menu | **V** `DictationHistoryView.swift:4-26, 92-97`; **V-img** 02 “All time” |
| Search | LIKE on `text` | ⌘F in this pane (new) | “Search history” | Full width | current field; **V-img** 02 |
| Extra filter | Filter by `sourceApp` (real values only) | — | “Filter” | Icon | **V-img** 02; new |
| Stat WPM/words/apps/saved | None (display) | — | “{n} WPM” etc. | 2×2 wrap | current; **V-img** 02, 07, 09 |
| Sparklines on stats | `presentation-only` trend of **real** daily word counts if computed; else omit. Do **not** reuse `MeetingSparkline` fake | — | hidden | Hide | **V-img** 07 |
| Row | Copy / Paste / Delete (current). Title = first line until a title column exists | — | first line + time | Stack meta | current; **V-img** 02, 07, 09 |
| Play / waveform / star / tags | Hidden until audio / favorite / tags exist (**H** / `new-persisted`) | — | — | — | **V** schema `AppDatabase.swift:125-132` has text/createdAt/duration/wordCount/sourceApp only |
| Type tabs All / Dictations / Notes / Imports | Tabs exist as IA; Notes/Imports empty until T7 | — | tab name | Scroll | **V-img** 09 |
| Sort Newest first | Sort (createdAt desc is current) | — | “Sort” | Menu | **V-img** 09 |
| List / grid | Default **list**. Grid is `new-reversible`, default off | — | “List” / “Grid” | List only | **V-img** 09 |
| Load more | Page 25–50; “Showing k of n” | — | “Load more” | Full width | **V-img** 02, 07; replace silent `limit: 500` |
| Auto-save copy | Honest: entries persist locally | — | — | — | **V** `AppState.recordDictation`; **V-img** 09 shield |

### 3.2b Dictation — live (overlay + inspector)

**Data:** `DictationController` phase, preview, waveform (40 bars, **V**), `engineID`. Same session as overlay.

| State | Overlay | Inspector (≥1280, Dictation selected) |
|---|---|---|
| Idle | Hidden | Hidden (or last session summary — **no**, do not fake; hide) |
| Preparing | “Getting the microphone ready…” | Same + disabled pickers |
| Listening | Waveform + preview / “Speak now…” / “Speak — press again to finish” | Waveform, caret in text, timer HH:MM:SS, On-device or Muse, Detected locale if known, Auto-save line |
| Processing | “Finishing your dictation…” | Same; pickers disabled |
| Rewriting | preview; `isRewriting` | Same |
| Done | preview; auto-hide 720/1600 ms (**V** `DictationController.swift:323-336`) | Hide with overlay |
| Failed | message; retry if `lastFailureRetryable` | Same + Retry |
| micBusy | Failure: meeting is recording | Do not start a second capture |

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Hold / tap trigger | start/stop | Right ⌥ default; Right ⌘ and ⌥Space supported | “Dictation” | Overlay only | current |
| Press again to stop | toggle path | same key | “Stop dictation” | — | **V** overlay copy `:132`; **V-img** 02 |
| Esc | cancel (hold mode) | Esc (hotkey id 4) | “Cancel dictation” | — | current |
| Language picker | Settings locale; in-panel is new | — | “Dictation language” | Hide; use Settings | **V-img** 02; Settings `SettingsView.swift:327-336` |
| Mic picker | New CoreAudio device list, event-driven, **no polling loop** | — | “Microphone” | Hide | **V-img** 02; no picker in UI today |
| Close inspector | Hide column; does **not** stop capture | Esc when inspector focused | “Close live dictation” | N/A (overlay) | **V-img** 02 |
| On-device / Muse | Display `engineID` | — | engine name | — | **V** `DictationOverlayView.swift:123-125` |

Waveform budget: keep 40 bars; publish ≤ 12 Hz (`LevelGate` 0.08); render 30 fps until T9 profiles; Reduce Motion pauses. Do not add a second `TimelineView` for the inspector — share samples, one render surface at a time (inspector **or** overlay Canvas, not both at 30 fps). Preferred: inspector reuses the same sample array; if both visible, overlay Canvas is the only `TimelineView`.

### 3.3 Live Recording (meeting state + HUD)

**Not a sidebar app.** HUD always. Full-page stage when the recording meeting is selected.

**Data:** `RecordingEngine` (timer via `startedAt`, `micLevel`/`systemLevel` gated 0.25 s, warnings), `Meeting`, optional `TranscriptionCoordinator` if live ASR on.

| State | Stage | HUD |
|---|---|---|
| Ready (not recording) | N/A — this screen is not selected | Hidden / “Not recording” |
| Starting | Disable Stop until `isRecording`; cancel start is allowed (`recordingStartTask` cancel, **V** `AppState.swift:370-371`) | Compact or expanded |
| Live, ASR off | Giant timer HH:MM:SS (≥1 h) else M:SS, dual meters, Stop, warnings, “Transcript after you stop”. Optional live sparkline from gated RMS only | Expanded card 520 / pill |
| Live, ASR on | Same + live transcript panel (finals only in the list; volatiles stay in HUD/captions — **V** `MeetingDetailView.swift:289-291`) | Snippet |
| Error | Mic/system warning labels (current strings). Stop still works | Same |
| Processing after Stop | Leave stage; HUD “Processing notes…” (**V** `RecordingHUD.swift:32-49`) | Processing card |

**Pause / Resume:** inventory only. No control until §9. Do not paint a Pause button that calls `stop()`.

**AI Assistant live summary:** off unless §9. Inspector may show **live transcript only** (empty summary / “Summary after you stop”). Do not invent Spanish paragraphs.

**Rings:** omit, or static. Reduce Motion: no pulse.

**Record while live:** rejected.

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Timer | none | — | “Recording time {elapsed}” | Smaller type, still tabular | **V** `RecordingTimer`; **V-img** 04 `00:14:37` |
| Mic / System meters | none | — | “Microphone level”, “System level” | Keep | **V** `LevelMeter`; gate 0.25 s `LevelGate.swift:9` |
| Live sparkline | display gated RMS | — | hidden (decorative) or “Input level” | Full width, ≤64 bars, ≤24 fps **P** | **V-img** 04; **not** C2 |
| Stop | `stopRecording` | ⌘. (**V-img** 04) | “Stop recording” | Always visible | current HUD/Bar/MenuBar |
| Mark moment | persist bookmark if table exists; else hide | **⌘B** | “Mark moment” | Icon | **V-img** 04; `new-persisted` |
| Mark action | append a quick action item if we have a place to put it; else hide | **⌘⇧M** | “Mark action” | Icon | **V-img** 04; **not** ⌘M |
| Quick note | focus meeting notes | **⌘N** | “Quick note” | Icon | **V-img** 04; editor exists, shortcut unbound |
| Language chip | display `meeting.language` | — | “Language {id}” | Chip | **V** header chip `MeetingDetailView.swift:83-90` |
| Mic picker | input device; hide until enumerated | — | “Microphone” | Hide | **V-img** 04 |
| Auto-scroll | toggle live transcript | — | “Auto-scroll transcript” | Keep | **V-img** 04, 06; today always on `:297-301` |
| Pause | **H** — hidden | ⌘⇧P when approved | “Pause recording” | — | **V-img** 04; no engine (**V**) |

### 3.4 Meeting Overview

**Data:** `Meeting` (title, summary, enhancedNotesMarkdown, actionItemsJSON, emailDraft, dates, language, folder, calendarEventID, audio paths), segments for talk-time, bookmarks/moments if present, player after Stop.

Tabs (content column): **Overview | AI Notes | Transcript | Action Items | Tasks**.

- AI Notes = current Enhanced (markdown + enhance/re-enhance + email draft).
- Action Items = `ActionItem` list (text, owner, done). Due date / “In progress” are `new-persisted` / **H** (today due is stuffed into `text`, **V** `EnhancementService.swift:84-87`; status is `done` optional JSON).
- Tasks = **separate tab**. Empty until §9. Badge hidden if count is 0. Do not alias Action Items.

| State | Overview body |
|---|---|
| Ready | Summary (`meeting.summary` or empty card “No summary yet”). Action items if any. Email draft kept on AI Notes, not duplicated. Key Decisions / Outcomes / Moments: show when fields exist; otherwise omit the card (do not fake). |
| Empty (quick note) | Notes editor is the useful surface; Overview says “Record or enhance to build this overview.” |
| Loading / processing | Pipeline phase (`MeetingStatus.processing`, `enhancingMeetingIDs`) | **V** `EnhancedNotesView.swift:19-29` |
| Error | Failed transcription copy + Retry (**V** `MeetingDetailView.swift:242-258`). Enhance failure via `loadError`. |
| Playing | Player in header (post-stop). Overview still visible |

Player until playback exists: duration + Record (or Resume **chrome hidden** until §9). Do not paint a play button that no-ops.

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Back | `selectedMeetingID = nil` | — | “Back to Home” or “Back” | Chevron | **V** `:67-77`; **V-img** 01, 08, 10 |
| Title field | save 500 ms debounce | — | “Meeting title” | Full width | current |
| Star | hide until favorite column | — | — | — | **V-img** 05 only; **H** |
| Play / pause / seek / 1x / ±15 s / expand | `AudioPlayerService` | Space play/pause **P** | “Play”, “Seek”, “Playback speed” | Player stacks | **V-img** 01, 05, 06, 08, 10 |
| Chapter markers | seek | — | “{label} at {time}” | Markers may clip; keep | §2.8 |
| Tab bar | switch | — | tab name | Scroll tabs | **V-img** 01, 05, 08, 10 |
| Tab counts | real counts; hide at 0 | — | “Action Items, {n}” | — | **V-img** 01 |
| AI Summary + Regenerate | `enhance` | — | “Regenerate summary” | Full width | **V** Enhance now/Re-enhance; **G4** before any new trigger |
| Generated {time} ago | show if enhance timestamp exists; else omit | — | — | — | **V-img** 10; additive field **P** |
| Key Decisions / Outcomes | omit until additive keys exist | — | — | two-up wraps | **V-img** 05, 08, 10 |
| Action table | toggle done; owner display | — | item text | Stack columns | current rows; 05 table is richer (**H** due/status) |
| Key Moments | seek; omit if none | — | “{label} {time}” | Horizontal scroll | **V-img** 08, 10; faces are `presentation-only` → letter avatars |
| Linked documents | omit until T7 Files objects; do not fake Google Docs | — | — | — | **V-img** 05, 08, 10 |
| Export notes | `exportViaSavePanel` | — | “Export as Markdown” | Menu | current |
| Copy transcript | current | — | “Copy transcript” | Menu | current |
| Delete | current, destructive confirm | — | “Delete meeting” | Menu | **V** Home context + **V-img** 08, 10 |
| Add to collection | folder menu | — | “Move to folder” | Menu | current |
| Copy meeting link | `excluded-fiction` (API is localhost bearer) | — | — | — | **V** `SettingsView.swift:960-991` |
| Share | menu of **real** actions: copy transcript, export, copy email | — | “Share” | Menu | **V-img** 01, 06, 08, 10; no URL |
| Add to calendar | **H** (EventKit is read-upcoming, **V** `CalendarService.swift:5-10`) | — | — | — | **V-img** 08 |
| Inspector: details | createdAt, language, folder, duration from startedAt/endedAt, calendarEventID, joinURL if any | — | “Meeting details” | Overlay | real fields only. ID format `mtg_…` is mock — use `meeting.id`. “HD Video & Audio” excluded unless §9 video |
| Inspector: participants | diarized speakers + Me; **no Invite**, no photos | — | speaker name | Overlay | **H** for Contacts |
| Inspector: tags | hide add until §9 representation | — | — | — | **H** |
| Synced to | excluded | — | — | — | all families |

### 3.5 Transcript

**Honesty bar is image 06:** disfluent ASR, generic `Speaker N` until renamed (`SpeakerMapping` emits `"Speaker \(id)"`, **V** `SpeakerMapping.swift:27`). Image 01’s named photos are rejected.

**Data:** `TranscriptSegment` (`speaker`, `startSeconds`, `endSeconds`, `text`, `channel`, `isFinal`). Pagination is new (today unbounded `fetchSegments`, **V** `AppDatabase.swift:403-413`). Volatile text stays out of this list.

| State | What |
|---|---|
| Ready | Rows: timestamp, letter avatar, speaker, text. Selected = accent stroke. Bookmark/play hidden until those exist. |
| Empty | “No transcript” + “The transcript will appear here once a recording exists.” | **V** `:260-271` |
| Loading | Page fetch; keep previous page |
| Error | Failed + Retry | **V** `:242-258` |
| Live (ASR on) | Finals in list; auto-scroll toggle; volatiles in HUD/captions only |
| Filtered | Footer “{n} results”; do not paint ⌘F chrome until search works |

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Search | SQL text search | **⌘F** (only once wired) | “Search transcript” | Full width | **V-img** 01, 06 |
| All speakers | filter by speaker | — | “Filter speakers” | Menu | **V-img** 06 |
| Filters | extra filters (channel Me/Them) | — | “Filters” | Icon | **V-img** 01 |
| Row play | seek player to `startSeconds` | — | “Play from {time}” | Hide if no player | **V-img** 01, 06 |
| Bookmark | persist if table exists; else hide | — | “Bookmark line” | Icon | **V-img** 01, 06 |
| Overflow | Rename speaker (current) | — | “More” | Keep | **V** context menu |
| Pager | keyset page 50; “Showing 1–50 of N” | — | “Next page” | Keep | **V-img** 01; 582 is mock unless count is real |
| Jump to | time / moment menu | — | “Jump to” | Menu | **V-img** 01 |
| Auto-scroll | toggle | — | “Auto-scroll” | Keep | **V-img** 06 |
| Talk time / stacked bar | derive from `end-start` sums; hide if no system diarization | — | “{speaker} {percent}” | Stack | **V-img** 01, 06; **do not invent %** |
| Highlight reel | **H** / new-persisted; hide until bookmarks exist | — | — | — | **V-img** 01, 06 |

### 3.6 Permissions (Settings pane)

**Layout of 03** on the existing Permissions tab. Settings IA already matches seven destinations (**V** `SettingsView.swift:8-22`). Order in code today: Microphone, System Audio, Calendars, Notifications, Screen Recording, Accessibility (**V** `PermissionsView.swift`). 03 order differs; **adopt 03’s visual grouping**, keep truthful names (Screen Recording is OCR-only, **V** `:57-61`).

`PermissionState`: granted / denied / notDetermined / unchecked (**V** `PermissionCenter.swift:6-10`).

| State | What |
|---|---|
| Ready | Health strip: **k of 6 need attention** where k = count of non-granted (denied + notDetermined + unchecked). Six dots matching rows. List with Granted / Denied / Not asked / Unchecked. |
| Empty | N/A (always six rows) |
| Loading | Rescan in progress on the strip, not a fake “Last scanned 9:41” |
| Error | Probe failed → Denied + Open Settings |
| Probing | System audio Check spinner (`probingSystemAudio`) | **V** `:22, 56-70` |

**Do not** copy “2 of 6” from 03. That PNG contradicts its own list (three Not checked + one Unknown) — **V-img**, flagged by both reviews.

| Control | Action | Shortcut | A11y | Compact | Evidence |
|---|---|---|---|---|---|
| Rescan all | `PermissionCenter.refresh()` only. **Does not** probe system audio in a loop | — | “Rescan permissions” | Keep | **V-img** 03; probe creates a real tap (**V** `PermissionCenter.swift:52-55`) |
| Check (system audio) | `probeSystemAudio` once | — | “Check system audio permission” | Keep | current |
| Request | `requestMicrophone` / calendar / notifications when notDetermined | — | “Request {name}” | Keep | current |
| Open Settings | pane URL | — | “Open System Settings” | Keep | **V** pane URLs `PermissionsView.swift:12, 39, 49, 55, 61, 66` |
| Fix recommended | jump to first non-granted row | — | “Fix recommended” | Keep | **V-img** 03 |
| Languages up to 3 | existing probe-locale toggles | — | “Languages to detect” | Stack | **V** `LanguageDetection.maxProbeLocales = 3` |
| Manage languages / models up to date | installed vs not via `SpeechModels.isInstalled` (**V** `SpeechModels.swift:22-24`). No “9:41 AM” clock | — | “{locale} installed” | Stack | **H** for a freshness feature |
| System & privacy copy | on-device / local storage — display policy, not a fake toggle | — | — | Stack | **V** onboarding |
| Permission monitoring toggle | **H** / new; default off. Today refresh on become-active | — | — | — | **V-img** 03 |
| Camera / video in health icons | Screen Recording row stays OCR. Video is §9 | — | — | — | **V-img** 03 vs 08 |

### 3.7 Notes (global dest + per-meeting editor)

No dedicated PNG of the page. Dest is visible on 01–02, 04–10.

**Data v1 (no new table):** meetings whose `notesMarkdown` is non-empty, plus quick notes (no audio). Per-meeting editor stays (`MeetingDetailView` Notes tab, **V** `:208-226`).

| State | What |
|---|---|
| Ready | List of real notes (meeting title + first lines + date). Open → that meeting’s Notes tab |
| Empty | “No notes yet” + Quick note. **Do not** show dictation snippets as notes without a join table |
| Loading | fetch |
| Error | loadError |
| Live | If recording, notes editor is the in-meeting Quick note surface |

Do not fake a second notes corpus. T7 may add a notes object; until then this dest is a filtered meeting list.

### 3.8 Files

No dedicated PNG. Dest visible on the same images.

**Data v1 (no new table):** meetings with `audioMicPath` / `audioSystemPath`. Label the section **Recordings**. List real filenames/URLs, sizes if cheap (`FileManager`), duration from `startedAt`/`endedAt`. Play uses the same player as Overview (**H** mix).

| State | What |
|---|---|
| Ready | Recording rows (mic / system labeled Me / Them) |
| Empty | “No recordings yet” + Record. No Google Doc/Slides mocks |
| Loading | fetch |
| Error | missing file → “Audio file missing” (player empty state, not a crash) | R6 |
| Live | recording in progress: row “Recording…” without a play button |

Clipboard “Files” filter is a **different** surface (`ClipboardHistoryView.swift:90`). Do not conflate.

Attachments / Linked Documents wait for T7 schema (**H** representation).

### 3.9 Settings (non-Permissions)

Keep the seven tabs. Preserve all current panes: General (language, live ASR default off, captions, Muse system engine, detection, auto-stop, audio retention, AEC toggle as display), Dictation (shortcut including Right Command, engine, rewrite SpaceXAI/custom), Shortcuts, AI (providers + templates), Extras (Clipboard & OCR, Windows, Battery), Integrations (API + Webhooks).

No in-window Settings shell unless §9 (two-way, not blocking T1).

---

## 4. Feature matrix (images 01–10)

Every visible item. Nothing in this table is silently dropped.

Legend: `current` · `presentation-only` · `new-reversible` · `new-persisted` · `external-contract` · `excluded-fiction` · `human-decision`.

### 4.1 Shell and chrome

| Item | Images | Class | Notes |
|---|---|---|---|
| Hidden title bar + traffic lights | 01–10 | current | `GranipaApp.swift:27` |
| Dark UI + orange CTA | 01–10 | current + T1 retint | §2.2 |
| Sidebar search field | A, 01, 02, 07–10 | current | |
| ⌘K affordance | 05 | new-reversible | Focus existing `searchQuery` |
| Search as nav row | 04–06 | rejected | Family A search-in-sidebar wins |
| Home dest | all but 03 | current | Inbox |
| Dictation dest | all but 03 | current | |
| Meetings dest | 01, 04–06, 08, 10 | new-reversible | Library; not a new store |
| Notes dest | 01, 02, 04–10 | new-reversible | §3.7; schema T7 |
| Files dest | 01, 02, 04–10 | new-reversible | §3.8; attachments T7 |
| Live Recording dest | 04 | human-decision rejected as dest | State + HUD instead |
| Collections + add | all but 03 | current | Folders |
| Collection counts | A/B | new-reversible | Existing `folderMeetingCounts` |
| Integrations: Calendar | all but 03 | current | EventKit |
| Integrations: Slack/Notion/Linear/Jira | all but 03 | human-decision + excluded-fiction until approved | No clients (**V**) |
| Usage this week / Upgrade / Pro Plan GB | 01, 02, 04, 05, 07–10 | excluded-fiction | No entitlements |
| Account menu (Alex/Pablo) | 01–10 | excluded-fiction | Onboarding: no accounts |
| IntentX wordmark | 03–06 | excluded-fiction | |
| Settings dest | 03 + current footer | current | Seven tabs match 03 |
| Quick note | 01, 02, 04, 05, 07, 09 | current | |
| Record pill + static glow | 01, 02, 04, 05, 07, 09 | current | Glow new-reversible |
| Record while already live | 04 | rejected | |
| Resume CTA | 08, 10 | human-decision | Coupled with Pause; hide until §9 |
| Share | 01, 06, 08, 10 | new-reversible | Menu of real export/copy only |
| Copy meeting link | 05, 08, 10 | excluded-fiction | No share URL |
| Overflow … | 01, 05, 06, 08, 10 | current | Folder, template, export, copy |
| Detection banner | (code, not refs) | current | Preserve |

### 4.2 Dictation library and live

| Item | Images | Class | Notes |
|---|---|---|---|
| Period picker | 02, 07, 09 | current | |
| Search dictations | 02, 07, 09 | current | |
| Extra filter | 02 | new-reversible | By real `sourceApp` |
| Stats WPM / words / saved / apps | 02, 07, 09 | current | 40-WPM math |
| Stat sparklines | 07 | presentation-only | Real daily counts or omit |
| Apps-used vendor logos | 02 | presentation-only / excluded-fiction as brands | Show names |
| Accuracy 96% ring (orange or green) | 02, 07, 09 | excluded-fiction + human-decision substitute | Not billing (C6) |
| Live session **card** in library | 02 | rejected | Duplicate of inspector |
| Live **inspector** | 02, 07, 09 | new-reversible | Same `DictationController` |
| Floating overlay | (code) | current | Keep |
| On-device / Muse label | 02, 07, 09 | current | |
| Press again to stop | 02 | current | |
| Language + mic pickers | 02, 07, 09 | new-reversible | Mic list new; no poll loop |
| Detected / Auto language / Auto-save | 02, 07, 09 | current behavior + new-reversible chrome | Auto-save is already true |
| Shield “saved automatically” | 09 | current copy | |
| Row play / mini waveform | 02, 09 | new-persisted + human-decision | **No dictation audio file** today |
| Title / tags / star | 02, 07, 09 | new-persisted + human-decision | Additive columns **P**; shape **H** |
| Type tabs Notes / Imports | 09 | new-reversible IA; empty until T7 | |
| Grid toggle | 09 | new-reversible | Default list |
| Load more / 25 of N | 02, 07 | new-reversible | |
| Spanish faded paragraph | 02 | excluded-fiction | Don’t fake bilingual preview |
| Darker 09 paint | 09 | rejected | |

### 4.3 Live recording and player

| Item | Images | Class | Notes |
|---|---|---|---|
| HUD compact/expanded | (code) | current | Keep |
| Timer | 04 | current | Extend to HH:MM:SS at ≥1 h |
| Dual meters | 04 | current | Gate 0.25 s |
| Full-width live waveform | 04 | new-reversible | Gated RMS only; not capture-time peaks |
| Concentric rings | 04 | presentation-only | Omit or static; Reduce Motion off |
| Stop | 04 | current | ⌘. |
| Pause ⌘⇧P | 04 | human-decision | Engine door with Resume |
| Resume | 08, 10 | human-decision | Same door as Pause (C3) |
| Mark moment ⌘B | 04 | new-persisted | Bookmark table **P** |
| Mark action ⌘⇧M | 04 | new-reversible / new-persisted | Not ⌘M (C19) |
| Quick note ⌘N | 04 | current editor; new-reversible shortcut | |
| Language chip | 04 | current | |
| Mic picker | 04 | new-reversible | |
| Live transcript + auto-scroll | 04 | current if live ASR; toggle new-reversible | Default live ASR **false** |
| Captions overlay | (code) | current | Panel 656 / card 640 |
| “Transcript after you stop” | (code) | current | Keep when ASR off |
| AI live summary / topics / live actions | 04 | human-decision | One-way CPU/network; hang history |
| Tip card | 04 | excluded-fiction unless real copy | |
| Playback transport | 01, 05, 06, 08, 10 | new-reversible | No AVPlayer today (**V** grep) |
| Waveform + playhead (post-stop) | 01, 05, 06, 08, 10 | new-persisted peaks **P** | File scan after Stop |
| ±15 s | 05 | new-reversible | |
| Speed 1x | 01, 05, 06, 08, 10 | new-reversible | |
| Expand | 01, 05, 06, 08, 10 | new-reversible | |
| Volume | 06 | new-reversible omitted for T4 | 06-only |
| Named chapter markers | 05 | new-persisted | Canonical (§2.8) |
| Numbered markers | 08 | presentation-only fallback | Unlabeled moments |
| Colored dots | 01 | rejected as a second system | |
| Chapter chips under player | 10 | rejected as a second strip | |
| Channel mix Me/Them | (implied by dual files) | human-decision | C14; tests must not assume system-only |

### 4.4 Meeting workspace (overview / notes / transcript / actions / tasks)

| Item | Images | Class | Notes |
|---|---|---|---|
| Tabs Overview / AI Notes / Transcript / Action Items / Tasks | 01, 05, 08, 10 | new-reversible IA | Current tabs Notes / Enhanced / Transcript |
| Tasks tab as **separate** list | 01, 08, 10 | human-decision persisted shape | Empty until §9; **not** Action Items (C1) |
| Tab badges 4 vs 3 | 01, 08, 10 | new-reversible | Real counts; hide at 0 |
| AI Summary | 05, 08, 10 | current | `meeting.summary` |
| Enhanced markdown | (code) | current | AI Notes |
| Email draft | (code, not refs) | current | **Keep** |
| Enhance now / Re-enhance / Regenerate | 05, 10 | current | G4 before extra triggers |
| Generated 2m ago | 10 | new-persisted | Enhance timestamp **P** |
| Key Decisions / Key Outcomes | 05, 08, 10 | new-persisted | Additive prompt keys **P**, not locked JSON |
| Action items check + owner | 05, 08, 10 | current | `ActionItem` |
| Due date / In progress | 05 | new-persisted + human-decision | Due currently in text |
| Key Moments carousel | 08, 10 | new-persisted | Meeting-scoped; not dictation C11 (C9) |
| Face crops on moments | 08 | presentation-only | Letter avatars |
| Linked documents | 05, 08, 10 | new-persisted T7 | Empty until objects exist |
| Participants + roles + Invite | 05, 08, 10 | human-decision | Speakers + Me now; Contacts **H** |
| Tags + add | 05, 08, 10 | human-decision | Blob vs table **H** (C13) |
| Star on title | 05 | human-decision / new-persisted | |
| Meeting Details ID / organizer / HD video | 08, 10 | mixed | Real dates/language/folder; ID mock format excluded; HD video **H**; location only if `joinURL` |
| Add to calendar | 08 | human-decision | EventKit write |
| Delete meeting | 08, 10 | current | Does **not** delete audio dir today (**V** `AppState.swift:648-659`) — orphan policy **H** |
| Transcript rows + selected stroke | 01, 06 | current + new-reversible selection | |
| Photos of people | 01 | excluded-fiction | `AvatarView` |
| Speaker S1/S2 honesty | 06 | current mapping | Honesty bar |
| Bookmark per line | 01, 06 | new-persisted | |
| In-row play + mini waveform | 01, 06 | new-reversible after player | |
| ⌘F search + filters + pager | 01, 06 | new-reversible + SQL | G2 |
| 78 results / auto-scroll | 06 | new-reversible | |
| Talk time bars / stacked % | 01, 06 | new-reversible | Derived; hide if no data |
| Highlight reel / Create highlight | 01, 06 | human-decision / new-persisted | |
| Export transcript / notes | 01, 06, 08 | current + new-reversible split files | One markdown blob today |
| Synced to | 01, 08, 10 | excluded-fiction | |
| EN/ES pill | 05, 06, 08 | current | `meeting.language` prefix |
| Back to Home vs compact chevron | 01, 05, 06, 08, 10 | new-reversible | Keep chevron; label “Back” |

### 4.5 Permissions / languages

| Item | Images | Class | Notes |
|---|---|---|---|
| Seven settings destinations | 03 | current | Exact label match |
| Six permission rows + Check | 03 | current | |
| Health strip | 03 | new-reversible | Honest math only |
| “2 of 6” copy | 03 | excluded-fiction | Contradicts its list |
| Fix recommended | 03 | new-reversible | Jump to first non-granted |
| Legend Granted / Action needed / Unknown | 03 | new-reversible | Map to `PermissionState` |
| Rescan all | 03 | new-reversible | refresh(); no probe loop |
| Last scanned clock | 03 | excluded-fiction as 9:41; optional real timestamp | |
| Languages up to 3 | 03 | current | |
| Models up to date 9:41 AM | 03 | excluded-fiction | installed vs not allowed |
| System & privacy Enabled rows | 03 | presentation-only of policy | Not a watcher unless **H** |
| Permission monitoring toggle | 03 | human-decision | |
| Open System Settings | 03 | current | |
| Camera icon vs Screen Recording | 03 | human-decision (video) | OCR-only today |
| Pro Plan 78/100 GB | 03 | excluded-fiction | |

### 4.6 Cross-cutting features the refs imply (do not omit)

| Item | Class | Notes |
|---|---|---|
| Tasks | human-decision + new-reversible tab | C1 |
| Notes dest | new-reversible; T7 schema | C2 |
| Files dest | new-reversible; recordings v1; T7 attachments | C2 |
| Pause / Resume | human-decision | C3 |
| Accuracy | excluded-fiction %; human-decision substitute | C6 |
| Playback channel handling | human-decision | C14 |
| Tags / favorites | human-decision persisted shape | C13, C16 |
| Dictation audio | human-decision (new media) | Door with retention |
| Sharing | new-reversible local export/copy; no URL | |
| Participants | current labels; human-decision identity | |
| Integrations | current Calendar/API/webhooks; human-decision OAuth | C7 |
| Rewrite HTTP + Sparkle | current + external-contract | C7 |
| Right Command dictation | current | Preserve |
| Clipboard paste | current | Preserve |
| Battery controls | current | Preserve |
| Local storage | current | Preserve |
| Email draft | current | Preserve |

---

## 5. Reconciled architecture and vertical slices

### 5.1 Freeze / do-not-touch (until a profiled slice)

- Audio writer path, gap padding, `deepCopy` per buffer, coalescing (**V** `RecordingSession.swift:270-319, 291-293`).
- AEC on meeting Record.
- `liveMeetingASR` default.
- Single-start-locale policy (**V** `LanguageDetection.swift:46-55`).
- Volatile ASR out of the transcript list.
- No new process, no new top-level dependency, no entitlements change.

### 5.2 Seams (real), not “everything is composition”

| Seam | What | Not |
|---|---|---|
| **P1 Playback** | MainActor `AudioPlayerService` around `AVAudioPlayer` (or equivalent). Play/pause/seek/rate. Missing file = empty state. | Channel mix (**H**). Tests must not assume system-only (C14). |
| **P2 Peaks (post-stop)** | Pure `WaveformPeaks.extract(from:)` + file scan after Stop + legacy backfill. Sidecar next to m4a or blob **P**. | Capture-time second consumer on the IOProc. T3 does not depend on P2 (C5). |
| **P3 Segment window** | Keyset `fetchSegmentsPage` + `searchSegments`. LIMIT 50. | Loading 582 eager views |
| **P4 Dictation metadata** | Additive columns **P** (title, languageID, favorite, tags, peaks…). Exact set **H**/T2. Language at commit is known from the engine — no AI required for a language chip. | Meeting tags folded into dictation v9 (C13) |
| **P5 Bookmarks / moments** | Table `meetingID, startSeconds, label?, createdAt` **P**. ⌘B during Record is an observer of existing time, not a new restart path. | Mixing this commit with dictation cards (C9) |
| **P6 Enhancement keys** | Optional `decisions` / `outcomes` / `moments` / enhance timestamp **P**. Parser already tolerates absent keys (`EnhancementResult`, **V** `EnhancementService.swift:3-16`). | Locked JSON contract |
| **P7 Shell destinations** | Notes + Files + Meetings nav; inspector column; folder counts | New process |
| **P8 Live stage extras** | Mic picker (event-driven device list), mark moment (P5), live sparkline from **existing** LevelGate, auto-scroll toggle | “Only a new view” (C4); Pause (**H**); live AI (**H**); capture-time peaks |
| **P9 Permissions health** | Composition over `PermissionCenter` | Probe-in-a-loop; fake n-of-6 |
| **P10 Talk time** | SQL GROUP BY speaker on durations | Invented percentages |

**Composition (not seams):** Overview from summary + action items + notes; AI Notes = Enhanced; email draft; HUD; overlay; Settings scene; Calendar row; detection banner.

**Live waveform rule (normative):** Record-path peak **work** (extra RMS, FFT, extra `deepCopy`, extra writer consumer) is forbidden without a Record profile. A live sparkline may **only** reuse levels already published through `LevelGate` (meeting default 0.25 s ≈ 4 Hz/channel; dictation 0.08 s ≈ 12.5 Hz). Publish cap **≤ 12 Hz**. Render cap **≤ 24 fps** (**P**). Reduce Motion = static canvas.

### 5.3 Dictation vs meeting (do not mix)

| | Meeting | Dictation |
|---|---|---|
| Timebase | Meeting-relative seconds | Wall `createdAt` + `durationSeconds` |
| Audio | `audioMicPath` / `audioSystemPath` | None today; storing PCM/m4a is **H** |
| Moments | P5 bookmarks | Not Key Moments |
| Metadata | folder, language, summary, actions | P4 title/lang/favorite/tags **P** |
| Capture | `RecordingEngine` | `DictationController` (blocked when meeting records) |

C11 is split: dictation library slices never take a meeting Key Moments dependency.

### 5.4 Vertical slices (commit-sized, each green)

Order respects freeze, G1–G10, and un-coupling C2/C5/C9.

| Slice | Visible? | Depends | Guard first |
|---|---|---|---|
| **T1** Design system + shell + inspector collapse + dests (Home/Dictation/Meetings/Notes/Files) + folder counts + ⌘K + honest empties | Yes | — | ThemeTests; idle profile |
| **S1** `WaveformPeaks.extract` pure + fixture | No | — | G1 if anyone later touches writer; S1 itself is file-read |
| **S2** `AudioPlayerService` + tests (no channel assumption) | No | — | G9 |
| **S3** `fetchSegmentsPage` / `searchSegments` + 10k fixture | No | — | G2 |
| **T6** Permissions health + Rescan + honest n-of-6 | Yes | — | G8 |
| **T2a** Dictation library chrome (stats, search, load more, inspector+overlay, no Accuracy, no live card) | Yes | T1 | G5 |
| **T2b** Dictation metadata migration | Yes if **H**/T2 adopts P4 | T2a | G3 |
| **T3a** Live stage composition (timer, meters, Stop, warnings, keep HUD) | Yes | T1 | G6, G7 |
| **T3b** Stage extras (sparkline from gated RMS, ⌘N, language chip, mic picker) | Yes | T3a | G6, G7 |
| **T3c** Mark moment | Yes | P5 | G3 |
| **T3d** Pause/Resume | Only if §9 | engine change | Record profile; **not** in T3a–c |
| **T4a** Player bar post-stop | Yes | S1, S2 | G9 |
| **T4b** Overview from existing summary/actions + inspector details | Yes | T1 | — |
| **T4c** Decisions/outcomes/moments cards | Yes when P6 exists | P6 | G4 if regenerate |
| **T5** Transcript search/filter/pager/auto-scroll/talk-time; play-per-row when player exists; bookmarks when P5 exists | Yes | S3, T4a optional | G2 |
| **T7** Notes/Files objects, tags, Tasks shape | Yes | §9 C, G3 | |
| **T8** Approved integrations | Yes | §9 B | secrets in Keychain |
| **T9** Profiles, fps decision, Reduce Motion, VoiceOver | — | measurements | G6, G7 |
| **T10** Close | — | all | xreview other family |

Any slice can stop after its commit; the app stays shippable. T1 does **not** wait on §9.

LLM job owner (serialize per provider, cancel = `terminate()` child) lands **before** any new AI trigger (regenerate-from-new-places, per-dictation titles, live AI). `enhancingMeetingIDs` is per-meeting only today (**V** `AppState.swift:487-494`). `LLMRunner.runSync` wait+watchdog, no cooperative cancel (**V** `LLMRunner.swift:116-132`). API `enhanceTrigger` is a detached MainActor task (**V** `AppState.swift:236-240`).

Webhook `deliverDue` has three callers (**V** `AppState.swift:247, 482, 547`). Out of T1 scope; do not “fix” it inside a visual slice.

---

## 6. Performance, lifecycle, test budgets

No profiling in this T0. Numbers below are targets plus the command. **V-prev** hang: pid 62139 **103% CPU, 0 idle wakeups**, live ASR already off; pid 25501 **134%**, 8 hangs, AEC still in play. Success bar from hang-handoff: Record silence **< 30% CPU**, 0 Recent hangs, UI responds in second 1.

### 6.1 Budgets (repeatable)

| Budget | Target | Measurement |
|---|---|---|
| CPU idle (no record/dictate, panels closed) | ≤ 2% avg / 60 s | `top -pid $(pgrep -x Granipa) -l 13 -s 5 -stats pid,cpu,time`; drop first sample. Instruments Time Profiler 60 s |
| CPU recording (live ASR off, silence) | ≤ 30% avg, 0 hangs / 20 s | Same `top`; Activity Monitor Recent hangs; `sample $(pgrep -x Granipa) 5 -file /tmp/g.sample` |
| CPU dictation (overlay visible) | ≤ 25% | `top` 30 s dictation; Instruments share of 30 fps Canvas |
| CPU post-stop transcription | ≤ 80% single-core-eq; ≤ 1.2× real-time on 45 min | Wall-clock `processing` phase |
| RSS idle | ≤ 100 MiB physical / ≤ 120 MiB RSS after 10 min | `footprint $(pgrep -x Granipa)`; `top -stats rsize` |
| RSS 1 h recording | growth ≤ 50 MiB | Same at t=0/30/60. Guard for unbounded writer queue + per-buffer `deepCopy` |
| Idle wakeups | ≤ 3/s avg idle; 0 sustained busy-spin | `top … -stats pid,idlew`. Signature of hang: 0 idle wakeups + ~100% CPU |
| Animation | 0 hitches while overlay visible; main thread never blocked > 100 ms | Instruments Animation Hitches; Reduce Motion pauses TimelineView |
| Dictation publish / render | ≤ 12 Hz publish; overlay 30 fps until measured; **P** ≤ 24 fps after Instruments | LevelGate interval; TimelineView `minimumInterval` |
| Live stage sparkline | ≤ 12 Hz publish, ≤ 24 fps render, ≤ 64 bars, Reduce Motion static | G6 |
| Meeting level publish | keep ≥ 0.25 s/channel (≈ 4 Hz) to MainActor | G6 |
| DB write rate, live ASR on | ≤ 1 commit/s sustained | `PRAGMA data_version` once/s. Today one commit per final segment (**V** `TranscriptionCoordinator.applyDecided`) |
| DB page query | p95 ≤ 5 ms at 10k rows | in-memory `DatabaseQueue` fixture (existing test pattern) |
| Waveform cost (post-stop extract) | backfill ≤ 10 s per meeting-hour; ≤ 256 KiB peaks per meeting-hour | `du` sidecars; time the scan. **Not** a capture-time CPU budget |
| List / pager | first transcript page ≤ 50 rows; 0 hitches scrolling a long meeting | LazyVStack; G2 |
| Startup | cold launch ≤ 2.0 s to interactive; DB open+migrate ≤ 100 ms on ~2 MiB DB | T1 adds `os_signpost("appReady")` in `applicationDidFinishLaunching` (none today). Instruments App Launch |
| Audio disk | retention = `audioRetentionDays` (default 0 = forever) | `du -sk` audio dir; orphan scan is **H** to delete |

Budget failure stops the slice (Plan & Brief §3). It is not a tuning invitation.

Always-on timers to account for in idle (**V**): Battery 5 s; MeetingDetector 5 s (default on); Clipboard 1 s (2 s when disabled); Calendar 300 s / 900 s if unauthorized; webhook 30 s (no-op if zero webhooks). Dictation `TimelineView` only while active. Recording: channel watch 3+5 s, meeting-end 5 s, volatile flush 80 ms (live ASR only), LLM watchdog 600 s.

**U:** ~1.3 wakeups/s idle from those cadences — arithmetic, not a measurement.

### 6.2 Lifecycle / cancellation / backpressure

**Dictation.** One capture. Meeting wins. `cancel()` bumps `sessionGeneration`, finishes continuation, stops mic, hides overlay. `stop()` finishes stream then `await transcribeTask.value`. Chunk stream is `.unbounded` (**V** `DictationController.swift:162-164`) — no new consumer without a drain. Overlay + inspector observe; they never start a second mic (G5).

**Recording.** Start cancellable at three `Task.checkCancellation` points (**V** `RecordingEngine.swift:67-75`). Stop serializes on `controlQueue` with final `writer.sync` (`RecordingSession.stop`). Mic restarts < 8 (**V** `:121`); system-tap retry ≤ 1; Muse reconnects ≤ 5. Waveform/bookmarks are observers — no new restart paths, no IOProc work.

**Live transcription.** `finishAndWait` cancels volatile flush. Locale adoption irreversible per meeting. Keep single-start-locale.

**AI jobs.** G4 job owner before new triggers. 600 s watchdog stays the floor. Swift task cancel does **not** kill the CLI today.

**Inspectors.** Panels created once, `setVisible`-gated. New UI must not own capture.

**Writer backpressure.** Unbounded session writer + per-buffer `deepCopy` is a 🔴 persisted-media risk (**V-prev** optimize-audit). Measure §6.1 memory during Record **before** touching. Coalescing/padding changes are proposals until a recording profile proves need (R1).

**deleteMeeting** removes DB rows, not the audio directory (**V** `AppState.swift:648-659`). Orphan sweep is **H** (retention).

### 6.3 24 fps

Current overlay: `TimelineView` `1/30` unless Reduce Motion or inactive (**V** `DictationOverlayView.swift:161-164`). Lineage labeled Canvas cost as inference, not Instruments (**V-prev** optimize-audit).

**Normative:** 24 fps is a **proposal**. T9 may adopt it after a before/after Instruments run on the overlay. T1–T8 must not “fix” 30 fps in the dark. New `TimelineView`s (live stage) start at ≤ 24 fps and G7.

### 6.4 Test guards (write before the risky change)

Current suite this tree: **197 `@Test` / 37 `@Suite`** (**V** count this session). GLM runtime 197/37 green at `c7704c3` was **V-prev** for that commit; not re-run here.

| ID | Before | Assertion |
|---|---|---|
| **G1** | Any writer-path or capture-adjacent peaks work | File-time == meeting-time across a synthetic gap via `ingestMicBufferForTesting`. Protects the 🔴 timeline contract. |
| **G2** | S3 / T5 | Pagination + search against a **10k-segment** fixture. Current `fetchSegments` has no LIMIT and no large test. |
| **G3** | Any v9+ migration | Upgrade path from a **v8 database copy**, not only a fresh migrator. Cite v4 `folderID` for nullable columns; cite `ActionItem.done` JSON test separately (C8). |
| **G4** | Any new AI trigger | Second `enhance` for the same meeting is a no-op; cancelled job **terminates** the subprocess (fails first today — watchdog only). |
| **G5** | T2 inspector | Docked panel cannot start a second mic while overlay/session is active (meeting `micBusy` exists; panel-vs-overlay does not). |
| **G6** | T3 sparkline / any new Record observer | Record MainActor level publishes stay ≤ ~4/s/channel (existing 0.25 s gate). Fail if a new observer bypasses `LevelGate`. |
| **G7** | Any new `TimelineView` | Reduce Motion disables/pauses it (same pattern as overlay). |
| **G8** | T6 | Health *n* equals count of non-granted among the six states. Never pins “2 of 6”. |
| **G9** | S2 / T4 player | State machine tests use real m4a from the writer. **Do not** assume system-only or mixed. Missing file → empty. |
| **G10** | T9 fps change | Instruments before/after on dictation overlay; no fps drop without a measured benefit. |

SpeechAnalyzer / FluidAudio stay behind existing `Boundary` fakes. Real-model smoke is a signed-bundle manual step (TCC resets per ad-hoc rebuild).

Player, pagination, migrations: real GRDB / real files. No mocked DB for those ranks.

---

## 7. Migration / external-contract map

Persisted representations below are **proposals**. They do not ship until the owning task adopts them *or* §9 answers. All future migrations **additive**. Never reorder v1…v8.

### 7.1 Current store (V)

| Store | Shape |
|---|---|
| `meeting` | v1 columns + v4 nullable `folderID` |
| `transcriptSegment` | channel, speaker, text, start/end, isFinal |
| `meetingTemplate` | v2 + v6/v7 prompt refresh |
| `webhook` / `webhookDelivery` | v3 |
| `folder` | v4 |
| `clipboardItem` | v5 |
| `dictationEntry` | v8: text, createdAt, durationSeconds, wordCount, sourceApp |
| `actionItemsJSON` | blob; `ActionItem.text/owner/done?` JSON optional `done` |
| Audio | `…/Granipa/audio/{meetingID}/` mic.m4a + system.m4a |
| API | localhost bearer; `FolderDTO.meetingCount`; enhance trigger |
| Webhooks | HMAC; events meetingStarted / meetingCompleted |
| Rewrite | POST chat/completions; Keychain keys |
| Sparkle | feed URL + EdDSA; placeholder key disables updater |
| Muse | WebSocket `wss://api.meta.ai/v1/asr/realtime` opt-in |

### 7.2 Proposed additive migrations (not decided)

| ID | Proposal | Precedent to copy | Do not copy |
|---|---|---|---|
| v9 dictation metadata | nullable columns on `dictationEntry` | v4 `folderID` `alter(table:)` | `ActionItem.done` JSON optionality as a column pattern |
| v10 bookmarks | new table meeting-scoped | v3 webhook tables | Folding into dictation v9 |
| Meeting tags | blob **or** table | — | Silently picking JSON because `actionItemsJSON` exists |
| Tasks | second list **or** derived filter **or** same rows | — | Shipping C7 as Tasks = Action Items |
| Enhance timestamp / decisions / outcomes / moments | nullable meeting columns **or** parsed from report | Absent keys already tolerated | Locking prompt JSON this T0 |
| ActionItem.dueDate / status | JSON fields (like `done`) **or** columns | `done` JSON test | Mixing JSON-field and column precedents |
| Peaks | sidecar file next to m4a **P** (keeps peaks if audio later deleted) | AppPaths audio dir | Writing peaks on the Record IOProc |
| Dictation audio | new media files **H** | meeting m4a | Assuming it ships with T2a |

G3 required on every schema slice. Old app versions must ignore new columns.

### 7.3 External contracts

| Surface | Rule |
|---|---|
| Local REST | Additive routes/fields only. Existing `MeetingDetailDTO` / `SegmentDTO` stay. Pagination is a new query, not an in-place change of unbounded fetch. |
| Webhooks | New event names additive. Do not change HMAC payload fields in place. |
| Enhancement JSON | New keys optional. Old CLIs that omit them still parse. |
| Sparkle / rewrite / Muse | Unchanged unless a dedicated slice says otherwise. |
| Entitlements / bundle id | Untouched. |

---

## 8. Definition of done — T1–T10

Observable proof. Door-gated rows stay in the matrix with “blocked on §9” rather than disappearing.

| Task | Observable proof | Data / risk | Can start before §9? |
|---|---|---|---|
| **T1** Design system + shell | Window ≥1280 shows sidebar 248 + content + inspector 300; 1120 shows inspector collapsed + toolbar toggle; Reduce Motion: no slide, no pulse, overlay TimelineView paused; dark tokens match §2.2; dests Home/Dictation/Meetings/Notes/Files with honest empties; folder counts match SQL; ⌘K focuses search; Settings scene unchanged; HUD/overlay/captions/clipboard/battery/dictation still work; `swift test` green; idle CPU not worse than pre-T1 `top` 60 s | No schema. Visual only | **Yes** |
| **T2** Dictation library + live | Right Command **and** Right Option E2E: hold → partial text → release → paste + history row; inspector+overlay same session (G5); no live card; no Accuracy %; real WPM/words/apps/saved; Load more; waveform publish ≤12 Hz; Reduce Motion static; metrics not invented | T2b columns only if §9/T2 adopts P4; play/star hidden until audio/favorite exist | **T2a yes**; T2b no if columns |
| **T3** Live recording | Selecting the recording meeting shows stage: timer, dual meters, Stop, warnings, HUD still present; file-time == meeting time (G1 if writer touched — it must not be); G6 publish rate; G7; live ASR still default off; “Transcript after you stop” when off | Pause/Resume **blocked on Q1**; live AI **blocked on Q2**; mark moment needs P5 | **T3a/b yes** |
| **T4** Overview + player | Recorded meeting: Overview with real summary or empty card; action items toggle; email draft still on AI Notes; post-stop play/seek/±15s/1x on real m4a (G9); named markers only if bookmarks exist; export Markdown still works; processing/failed/ready states honest | Mix **H**; chapters need P5; decisions/outcomes need P6 | **T4a/b yes** (single transport, no channel UI) |
| **T5** Transcript | ⌘F search returns real hits; speaker filter; page size 50 with “Showing a–b of N” matching DB; lazy; rename still works; talk-time % derived or hidden; 06-style Speaker N until renamed; volatiles not in list; per-row play seeks when player exists | Bookmarks/highlights need P5 | **Search/pager/filter yes** |
| **T6** Permissions | Health *n* = non-granted count (G8); Rescan does not probe tap in a loop; Check probes once; Request/Open Settings hit the same pane URLs as today; languages ≤3; installed vs not from `SpeechModels`; zero “2 of 6” / “9:41 AM” fiction | Monitoring toggle **H**; video **H** | **Yes** |
| **T7** Collections, notes, files, tags, tasks | CRUD on whatever objects §9/C adopts, additive migration + G3, navigation/search, export, real GRDB tests. Until then dests already from T1 remain empty-honest | Tags blob vs table **H**; Tasks shape **H**; attachments **H** | **Nav already in T1**; objects no |
| **T8** Integrations | Only providers the human approved. Connect/disconnect, error/retry, revoke, Keychain, no secrets in git | OAuth **H**. Until then Calendar + local API + webhooks only | **No** (except current API/webhooks polish) |
| **T9** Performance / a11y | Idle/nav/dictation/Record profiles recorded; lists lazy; G6/G7; G10 before any 24 fps change; tasks cancelable; VoiceOver labels from §3; 0 hangs in Record soak matching hang-handoff bar | Writer changes still require G1 + profile | **Yes** (measure); no speculative cuts |
| **T10** Close | `swift test` + build exit 0; signed bundle smoke: Record, Right Command dictation, clipboard paste, export, email copy, battery restore-on-quit; baseline→V2 table; gitleaks; xreview **other family**; no merge | — | After T1–T9 evidence |

T3’s canonical-plan line “Record/Pause/Resume/Stop E2E” is **amended** by this contract: Pause/Resume E2E is Q1-gated. Stop E2E is required in T3a.

---

## 9. Minimal human frontier

Reversible design is decided in §2 (tokens, serif titles, inspector default 1120, chapter markers, overlay+inspector, Live Recording as state, Settings scene, 09 paint rejected, volume deferred). Those are **not** blockers.

One-way or persisted-shape questions only. Coupled doors are grouped. Each names a recommended default, the consequence, and what may start now.

### Q1 — Recording session semantics

**Ask:** For a meeting, is Stop terminal (today), or do we add pause/resume of the **same** capture, or append/re-record into the same meeting after Stop?

**Why one question:** Images 04 (Pause+Stop live) and 08/10 (Resume on recorded chrome) were wrongly split into “defer Pause” + “Resume = re-record” (C3).

**Recommended default:** Keep Stop terminal. Hide Pause and Resume until a profiled engine slice exists. Do not encode re-record as architecture.

**Consequence of answering pause/resume:** engine + file-time contract + G1 + Record profile. One-way for capture semantics.

**Start now:** T1, T3a/b (Stop-only stage), T4 player after Stop.

### Q2 — Live AI during Record (includes local vs cloud for that surface)

**Ask:** Stay post-stop CLI enhancement (today), or run live summaries/actions during Record (on-device vs cloud)?

**Recommended default:** Off. Inspector may show live transcript only when `liveMeetingASR` is on. `liveMeetingASR` stays default false. Muse stays opt-in.

**Consequence:** Hang-class CPU/network; user expectations once shipped; G4 job owner.

**Start now:** Every UI seam, playback, pagination, bookmarks, permissions, talk-time, T3 stage without AI copy.

Status-quo hybrid (Apple ASR default, CLI enhance, opt-in Muse) is **not** reopened for post-stop work.

### Q3 — External identity (OAuth integrations, Contacts, accounts)

**Ask:** Stay local (Calendar EventKit + localhost API + HMAC webhooks), or add vendor OAuth, and/or Contacts for participant photos/Invite, and/or accounts/billing?

**Recommended default:** Local only. Billing/usage caps stay `excluded-fiction` unless a real entitlement appears (then it is a new question). Participants = diarized labels + Me. No Invite.

**Consequence:** Client IDs, vendor review, dead UI if reversed; Contacts TCC; accounts change the product’s nature.

**Start now:** T1 hide Slack/Notion/Linear/Jira; T8 waits.

### Q4 — What audio we keep (meeting retention, orphans, dictation files)

**Ask:** Keep meeting m4a forever (default `audioRetentionDays = 0`), and/or sweep orphans on delete, and/or store dictation audio for row playback?

**Recommended default:** Keep forever; do not auto-delete orphans; do not store dictation audio. Play buttons stay hidden. Peaks sidecars (P2) may exist without dictation audio.

**Consequence:** Dictation playback is a new media surface. Orphan sweep is destructive. “Waveform+transcript only” (delete m4a after process) is irreversible per meeting.

**Start now:** Player on **meeting** files; T2a without play; P2 sidecar design (peaks outside m4a) so Q4(b) remains possible later.

### Q5 — Video / screen as a recording channel

**Ask:** Stay mic+system audio, or add video / continuous screen?

**Recommended default:** No. Screen Recording permission stays OCR-only (`screencapture -i` + Vision). “HD Video & Audio” is excluded copy.

**Consequence:** New TCC, storage, thermal. One-way once users record video.

**Start now:** Everything else.

### Q6 — Library persisted shapes (Tasks, tags, dictation title/star)

**Ask:** (a) Tasks vs Action Items: same rows / second list / derived filter? (b) Tags: JSON blob vs table, meeting vs dictation vs both? (c) Dictation title/favorite columns?

**Recommended default:** Empty Tasks tab; hide tag-add that persists; dictation title = first line of `text`; hide star. Adopt P4/P5/P6 only as explicit T2/T4/T7 commits with G3.

**Consequence:** Persisted shape is expensive to reverse; blob vs table is a contract.

**Start now:** T1 dests; T2a; T4b Overview without tag persistence; T5 without requiring tags.

### Q7 — Playback channels

**Ask:** Mix mic+system, play one file, or A/B toggle?

**Recommended default:** Ship a **single transport** with no channel control. Implementation may play one file as an internal detail **only if tests do not freeze that choice** (G9). Do not label it “system” in UI.

**Consequence:** Mixing is a product decision about Me vs Them on seek-to-line.

**Start now:** T4a player chrome; per-row play seeks on the same transport.

### Q8 — Accuracy tile

**Ask:** Omit (this contract’s UI), or show a real substitute (e.g. not probe-confidence disguised as “96%”)?

**Recommended default:** Omit. Probe confidence is not accuracy (**V** `LanguageDetection.swift:9-21`).

**Consequence:** A fake % is a lie. A real metric needs a definition and a test.

**Start now:** T2a four-stat row.

### Q9 — Chrome localization

**Ask:** English chrome (today) vs String Catalog now vs later?

**Recommended default:** English chrome. Meeting/dictation **content** already follows source language. Catalog later re-touches every view (monotonically expensive) but is not a functional blocker.

**Consequence:** Deciding “later” costs more; deciding now is cheap at dozens of strings.

**Start now:** T1 in English. Do not fake ES inspector copy (04) unless the locale is actually es.

---

## 10. Traceability appendix

### 10.1 Images → contract

| Image | Resolves in |
|---|---|
| 01 meeting-transcript | §2 shell A; §3.4–3.5; §4.1, §4.3, §4.4; Tasks C1; Share local-only; photos rejected; pager budget |
| 02 dictation-live-card | §2.9 overlay+inspector, **no card**; §3.2–3.2b; Accuracy C6/Q8; stats current |
| 03 permissions | §3.6; health math C11; Settings scene §2.1; models clock rejected |
| 04 live-recording | §3.3 state not dest; C4/C5; Pause Q1; ⌘⇧M C19; live AI Q2; rings presentation-only; Record-while-live rejected |
| 05 meeting-overview-a | §3.4; named markers §2.8; ±15 s; Home-selected compatible; star **H**; integrations **H** |
| 06 meeting-transcript-b | Honesty bar §3.5; volume deferred §2.8; stacked speakers derived; inspector tools |
| 07 dictation-list | Canonical library+inspector C12; green Accuracy still omitted |
| 08 meeting-overview-b | Resume Q1; numbered fallback §2.8; Key Moments C9; HD video Q5; Delete current; Invite Q3 |
| 09 dictation-list-rich | Type tabs empty-honest; grid default off; 09 paint rejected; shield copy kept |
| 10 meeting-overview-c | Chip strip rejected §2.8; Generated-ago P6; tags Q6; Synced-to excluded |

### 10.2 GLM-on-Grok issues → contract

| Issue | Section |
|---|---|
| I1 overlay vs inspector decided and unresolved | §1.3 C15, §2.9, not in §9 |
| I2 additive GRDB under-claimed | §1.3 C16, §7.2 |
| I3 30 fps as fact | §1.3 C17, §2.7, §6.3, G10 |
| I4 wrong files/lines | §1.3 C18, citations throughout use verified paths |
| I5 Mark action ⌘M | §1.3 C19, §3.3 ⌘⇧M |
| I6 missing memory/DB/startup/writer/LLM cancel | §6.1–6.4, G1–G10 |
| I7 captions 640 only | §1.3 C21, §2.6 656 panel / 640 card |

### 10.3 Grok-on-GLM issues → contract

| Issue | Section |
|---|---|
| I1 Tasks = Action Items | §1.3 C1, §3.4, §4.4, Q6 |
| I2 Notes/Files dropped | §1.3 C2, §2.1, §3.7–3.8, T1 DoD |
| I3 Resume = re-record; Pause unrelated | §1.3 C3, Q1, T3 DoD amendment |
| I4 live stage “just a view” | §1.3 C4, §5.2 P8, T3a vs T3b |
| I5 capture-time peaks → C14 | §1.3 C5, §5.2 P2/live rule, T3 ↛ S1 |
| I6 Accuracy folded into billing | §1.3 C6, Q8, §4.2 |
| I7 no HTTP except Muse/webhooks | §1.3 C7, §1.4 rewrite+Sparkle, §7.1 |
| I8 `done` as column precedent | §1.3 C8, G3, §7.2 |
| I9 C11 mixes dictation + moments | §1.3 C9, §5.3, §5.4 |
| I10 two sidebar families | §1.3 C10, §2.1 |
| I11 03 health copy | §1.3 C11, §3.6, G8 |
| I12 07 still has inspector | §1.3 C12, §2.9, §3.2 |
| I13 tags JSON on meeting in C10 | §1.3 C13, Q6, §7.2 |
| I14 playback channel chosen | §1.3 C14, Q7, G9 |
| I15 tests beyond G1–G5 | §6.4 G6–G10 |

### 10.3b Agreements preserved

Capture pipeline freeze; 06 Speaker N honesty; keep HUD + email draft + “Transcript after you stop”; single capture; light pending; Rescan must not probe in a loop; ±15 s in player inventory; G1–G5 kept; no new dependency; append-only migrations; no `main` commits.

### 10.4 T1 start gate

Under this contract **T1 can start**. It needs no §9 answer: tokens, geometry, breakpoints, dests with empty states, inspector collapse, Reduce Motion, and preservation of current capture/dictation/clipboard/battery/export/email behavior are specified. It must not paint Pause, Accuracy %, Synced-to, fake n-of-6, ⌘F-without-search, play-without-files, or live AI copy.

---

*End of contract. Next code change is T1 in a different lane; this file stays the source of product truth until a later dated `docs/wip/` supersedes it.*
