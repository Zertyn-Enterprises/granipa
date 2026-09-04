# Grañipa V2 T0 — visual and interaction audit (Grok)

- **Lane:** `docs/v2-audit-grok`
- **Base:** `feat/granipa-v2@c7704c3`
- **Date:** 2026-09-04
- **Scope:** Read-only. This file is the deliverable. No Swift, schema, settings, or durable-doc edits.
- **Refs:** `/private/tmp/granipa-v2-refs.V0xiDo/01`…`10` (all 1448×1086 PNG).
- **Product name in this contract:** Grañipa. The **IntentX** wordmark, **mindtale.ai**, **Alex Morgan**, **Pablo Vega**, **Pro Plan**, usage meters, **96% Accuracy**, and named third-party “Synced to” rows are reference chrome only. They are not product claims.

## How to read this file

- **Verified (image):** named PNG, inspected as pixels this session.
- **Verified (code):** `path:line` from this worktree.
- **Unverified inference:** labelled. Not a fact.
- **Human-decision / one-way:** not chosen here.

Searched before proposing primitives (this session): `NavigationSplitView`/`inspector` (none), `preferredColorScheme` (dark only), `AVPlayer`/`AVAudioPlayer` (none), recording `pause`/`resume` (none), `bookmark`/`highlight`/`favorite`/`tag` as data (none in Swift models), `Slack`/`Notion`/`Linear`/`Jira` as code (none), sidebar destinations (`SidebarView.swift` has Home + Dictation only), `LazyVStack`, `TimelineView`, `accessibilityReduceMotion`, `waveformBars`, `LevelGate`.

Existing token/motion tests: `Tests/GranipaTests/ThemeTests.swift`.

---

## 1. Image-by-image inventory

All ten frames are a **hidden-title-bar macOS window** with traffic lights over the left chrome. None is a light-appearance frame. None is a narrow/compact layout. Motion is inferred from stills (glow, rings, playheads, carets) — a PNG cannot prove animation.

### 01 — `01-meeting-transcript.png`

- **IA:** Three columns. Sidebar (Search ⌘K, Home, Dictation, **Meetings** selected, Notes, Files, Collections with counts, Integrations, usage card, account). Main: meeting chrome + player + tab bar + transcript. Inspector: AI Insights / Highlight Reel / Speaker Breakdown / Export & Share.
- **Hierarchy:** Title “Solver Operational Controls” dominates. Player is the second band. Tabs sit under the player. Transcript is the working surface. Inspector is secondary cards.
- **Components:** Back to Home; Share (outline); Record (filled orange pill + glow); overflow `…`; date/time/duration; “Meeting” + “Recorded” pills; avatar stack `+2`; transport (pause, elapsed `12:46`, orange waveform with green/purple/blue markers, `47:36`, `1x`, expand); tabs Overview / AI Notes / **Transcript** (orange underline) / Action Items `4` / Tasks `3`; search transcript `⌘F`; Filters; left time-rail with playhead; rows (timestamp, avatar or letter, name, text, bookmark); selected row (orange stroke, in-row play, mini waveform, filled bookmark); pager “Showing 1–50 of 582 lines”, Jump to, prev/next.
- **Interactions (visible, not proven):** row play seeks; bookmark toggles; Filters opens a menu; Jump to is a menu; Share/Record/overflow; tab switch; inspector “View full summary”, highlight play, Talk time dropdown, export actions, copy link.
- **States visible:** recorded meeting, playing (pause icon), one active utterance, bookmarks empty vs filled, export idle, “Synced to” logos.
- **Motion (still):** Record glow; orange playhead/selection; waveform is a frozen bars plot.
- **Responsive:** single wide frame. Inspector present.
- **Ambiguity:** `47:36` vs `12:46` (duration vs remaining — unverified). Highlight Reel vs bookmarks. Action Items vs Tasks. Usage/billing. Named people and photos. 582-line pager vs current `LazyVStack` of all finals (`MeetingDetailView.swift:276`).

### 02 — `02-dictation-live-card.png`

- **IA:** Three columns. Sidebar same family as 01, **Dictation** selected. Main: dictation library. Inspector: live session (waveform + transcript + device).
- **Hierarchy:** “Dictation” title + subtitle. Primary actions Quick note + Record. Filter/search band. Five stat cards. Live session card. Day-grouped list.
- **Components:** period “All time”; search; filter; stats 106 WPM / 12,540 words / 24h 18m saved / 8 apps (Notion, Slack, Calendar glyphs) / **96% Accuracy** ring; live card (Recording, timer `00:00:48`, title, Open, `…`, tags, English, Mac, Live); rows with play, title, snippet, tags, language, app, duration, words, star, menu; “Showing 25 of 342”; Load more; inspector “Listening — press again to stop”, On-device, close, waveform, caret in text, language + mic pickers, Detected / Source / Auto-save with green dots.
- **Interactions:** period menu, search, filter, Open live session, play row, star, overflow, Load more, language/mic menus, close inspector.
- **States:** library + **live listening** at once; starred vs unstarred; one Spanish row among English.
- **Motion (still):** inspector waveform; live card orange glow; blinking caret (inferred).
- **Responsive:** inspector occupies a full third.
- **Ambiguity:** Accuracy has **no code counterpart**. Time-saved in code is typing at 40 WPM (`DictationEntry.swift:38-40`, test `DictationHistoryTests.swift:18-22`) — the 24h 18m figure is mock data, not a measured product metric. Dictation rows have titles/tags/language/audio play; stored row is `text/createdAt/durationSeconds/wordCount/sourceApp` only (`AppDatabase.swift:125-132`). Overlay today is a floating panel (`DictationOverlayView.swift`), not this inspector.

### 03 — `03-permissions.png`

- **IA:** Two-pane **Settings**. Left: IntentX wordmark + SETTINGS nav (General, Dictation, Shortcuts, **Permissions**, AI, Extras, Integrations) + Pro Plan + account + gear. Main: Permissions page. No meeting inspector.
- **Hierarchy:** Title + Rescan all + Learn more. Health summary card. Required permissions list. Languages + System & privacy. Footer to System Settings.
- **Components:** health “Action needed”, 6 status dots, “Fix recommended”, last scanned; rows Microphone / System Audio Recording / Screen Recording / Accessibility / Notifications / Calendar with Granted / Not checked / Unknown badges, Check / Check again, disclosure chevrons; legend Granted / Action needed / Unknown; Languages “up to 3” with English+Spanish selected, Add language, Manage languages; System & privacy: on-device processing, local data storage, permission monitoring — all Enabled; lock footer.
- **Interactions:** Rescan all; Check / Check again; row disclosure; Fix recommended; Add/Manage languages; Open System Settings.
- **States:** mix of granted, not checked, unknown. Probing implied by “Last scanned just now” spinner.
- **Motion (still):** orange focus ring on System Audio “Check”; scan spinner.
- **Responsive:** settings content is two stacked cards under the list (Languages | System & privacy).
- **Ambiguity (internal to the PNG):** header says **“2 of 6 permissions need attention”** while the list shows **three** “Not checked” plus **one** “Unknown”. Health dots do not match that copy. Treat copy as mock, not a state machine.
- **Code overlap:** the seven SETTINGS items match `SettingsView.swift:8-22` tab labels exactly. The six permissions match `PermissionsView.swift` (Microphone, System Audio, Calendars, Notifications, Screen Recording, Accessibility) with **different order**. System Audio already uses an explicit Check/probe (`PermissionsView.swift:28-40`, `PermissionCenter.swift:56-70`). “Select up to 3 languages” matches `LanguageDetection.maxProbeLocales = 3` (`LanguageDetection.swift:33`). Camera icon in the health strip vs “Screen Recording” in the list — unverified whether video capture is intended.

### 04 — `04-live-recording.png`

- **IA:** Three columns. Sidebar **without** the 01 search field: IntentX wordmark, Home, **Live Recording** (selected, red live dot), Meetings, Notes, Files, Search as a **nav item**, Collections (different icons + “New collection”), Integrations (Calendar/Slack/Notion/**Jira**), Pro Plan, Pablo Vega. Main: live capture stage. Inspector: AI Assistant.
- **Hierarchy:** Huge timer `00:14:37` + concentric rings + waveform. Four property chips. Pause / Stop / Mark action. Live transcription under. Inspector summary/actions/notes.
- **Components:** On-device + info; Quick note + Record (Record still offered while live — odd); mic picker MacBook Pro Mic; language Spanish (ES); Mark moment `⌘B`; Quick note `⌘N`; Pause `⌘⇧P`; Stop (orange ring, square); Mark action `⌘⇧M`; live transcript with timestamps, auto-scroll, one emphasized orange line; footer “Transcribiendo en español…”; inspector Summary / Action items `6` / Notes; live summary in Spanish; key topic chips; action list with due labels Today/Tomorrow/dates; View all; Tip card.
- **Interactions:** pause/stop/mark; language/mic; auto-scroll; inspector tabs; add action; Learn more.
- **States:** recording live; auto-scroll on; six open actions; Spanish UI copy in the inspector while the shell is English.
- **Motion (still):** radiating rings around the timer; live waveform; Stop glow.
- **Responsive:** inspector present. Stage is a large hero — will collapse badly if copied 1:1 to `minWidth 960` (`MainWindow.swift:55`).
- **Ambiguity:** Live Recording as a **sidebar destination** vs current HUD window (`GranipaApp.swift:45-53`, `RecordingHUD.swift`). Pause does not exist in `RecordingEngine.swift` (start/stop/`isBusy` only). AI live summary while recording is a **one-way** (cloud, CPU, `liveMeetingASR` default false — `MeetingASRPolicy.swift:13-17`). Video rings are decoration, not a camera preview.

### 05 — `05-meeting-overview-a.png`

- **IA:** Same shell family as 04 (IntentX, Search-as-nav, Jira, Pro Plan). **Home** selected while a meeting is open. Main: overview. Inspector: Participants, Tags, Integrations, Quick actions.
- **Hierarchy:** Title + star. Player with **named chapter markers**. Tabs. Four content cards (AI Summary, Key Decisions, Key Outcomes, Action Items table + Linked docs).
- **Components:** global Search anything `⌘K`; Quick note; Record; back chevron + “Friday, Jun 26 at 5:01 PM” + EN; overflow; date/duration/Product collection; avatar stack; play `12:48` / remaining `45:12` / `1x` / expand; chapters Intro / Testing agent / Deployment / Next steps; tabs Overview (active) / AI Notes / Transcript / Action Items / Tasks; AI Summary + Regenerate; Key Decisions / Key Outcomes with View all; action table Task / Owner / Due date / Status (`In progress`, `To do`); linked docs with mention timestamps; inspector Participants (5) Host + View all; tag chips + add; Notion/Jira/Slack rows; Share / Export notes / Add to collection / Create follow-up task / Copy meeting link.
- **Interactions:** seek via chapter markers and slider; regenerate; view-all; tag add; participant view-all; quick actions.
- **States:** recorded, playing (play icon — stopped/paused vs 01’s pause), starred title, in-progress vs to-do.
- **Motion (still):** playhead on the slider; orange waveform filled to playhead.
- **Ambiguity:** Home selected on a meeting (see contradictions). Status “In progress” is not `ActionItem.done` (`ActionItem.swift:3-6` is `text`/`owner`/`done` only). Linked docs / mention timestamps have no table. Participants have no EventKit attendee fetch (`CalendarMeeting` is `id/title/start/end/joinURL` — `CalendarService.swift:5-10`).

### 06 — `06-meeting-transcript-b.png`

- **IA:** Same shell as 04/05. **Home** selected. Transcript tab. Inspector: Meeting insights / Highlights / Tools / Speakers.
- **Hierarchy:** Same title. Player. Transcript list is the work surface. Inspector is tools, not AI Insights (01).
- **Components:** Share + overflow + Record (no Back to Home); EN pill; collection Product; pause `07:42` / remaining `32:17` / `1x` / **volume** / expand; search `⌘F`; **All speakers** dropdown; filter icon; rows: play, timestamp, **Speaker S1/S2** color names, text, bookmark, `…`; selected row orange stroke + filled bookmark; footer **78 results** + Auto-scroll; inspector summary; Highlights with timestamps (one with play triangle); Tools: Search in transcript, Create highlight reel, Export transcript; Speakers S1 68% / S2 22% / S3 10% stacked bar.
- **Interactions:** speaker filter; per-row play and overflow; auto-scroll; highlight click-to-seek.
- **States:** playing; filtered result count; one bookmarked line; unlabeled diarization names.
- **Motion (still):** playhead; auto-scroll toggle.
- **Ambiguity:** This transcript reads like **real ASR** (disfluency, “fireflies”). 01 reads like a polished mock. Treat 06 as the honesty bar for transcript content; treat 01 as the richer chrome bar. Volume control appears only here among transcript frames.

### 07 — `07-dictation-list.png`

- **IA:** Same family as 01/02 (search-in-sidebar, Linear not Jira, usage week, Alex Morgan). Dictation selected. **No live-session card** in the main column. Inspector still live.
- **Hierarchy:** Same as 02 minus the live card. Stats use **icons + sparklines**; Accuracy is a **green** ring.
- **Components:** Today / Yesterday groups; rows as 02; Load more; inspector same listening chrome; Detected row shows **Auto language** + green; Auto-save is a single bottom line (not a three-row checklist as in 02).
- **Interactions:** same library + live inspector.
- **States:** idle library + live inspector (no in-list live card).
- **Motion (still):** inspector waveform.
- **Ambiguity vs 02:** live session represented twice (card+inspector) vs inspector-only. Accuracy ring color green vs 02 orange. Stats iconography vs 02 sparkline-only.

### 08 — `08-meeting-overview-b.png`

- **IA:** Family of 01 (search-in-sidebar, Linear, usage week, Alex Morgan). **Home** selected. **Back to Home**. Header **Resume** (not Record). Overview.
- **Hierarchy:** Title without star. Player. Overview sections. Inspector: Participants (roles), Meeting Details, Tags, Quick Actions, Synced to.
- **Components:** Share + **Resume** + `…`; date 5:01–5:48 PM + 47m + Meeting + Recorded; play `5:01` / `47:36` / `1x` / expand; numbered waveform markers 1–3; tabs with counts Action Items `4` Tasks `3`; AI Summary; Decisions + Key Outcomes two-up; action rows with owner avatars + dates (no status chips); Key Moments `6` face-cards carousel; Linked Documents `3` (Notion, Google Doc, Google Slides); inspector Participants `6` with roles (You / SDET / Engineer / …) + Invite; Meeting Details ID `mtg_2025_06_26_1701`, Organizer, Location **Google Meet**, Recording **HD Video & Audio**, Created/Updated; Add to calendar; tags; Copy link / Edit details / Export transcript / **Delete meeting**; Synced to logos.
- **Interactions:** Resume recording; Invite; Add to calendar; delete (destructive).
- **States:** **paused recording** implied by Resume; recorded pill still shown (tension).
- **Motion (still):** none beyond chrome glow.
- **Ambiguity:** “HD Video & Audio” — Grañipa captures mic + system audio (`AGENTS.md`, `RecordingSession`), not video. Meeting ID format is mock. Resume is not in `RecordingEngine`.

### 09 — `09-dictation-list-rich.png`

- **IA:** Family of 01/02/07. Dictation selected. Richer list. Live inspector.
- **Hierarchy:** Same header. Stats. **Type tabs** All / Dictations / Notes / Imports. Sort “Newest first” + list/grid toggle. Rows with app glyphs and right-aligned times.
- **Components:** Accuracy ring **orange** again; second row shows **mini waveform** (playing); starred first row; tabs imply Notes and Imports as sibling corpora; inspector waveform is smoother/more continuous than 02/07; Detected + Auto language; shield “Transcripts are saved automatically”.
- **Interactions:** type tabs; sort; density toggle; in-row play.
- **States:** one row playing; Dictations tab active.
- **Motion (still):** in-row waveform + inspector waveform.
- **Ambiguity:** Notes/Imports tabs have no dictation schema. Grid toggle is unique to 09. Darker chrome (`#0C0F12` sampled) vs siblings.

### 10 — `10-meeting-overview-c.png`

- **IA:** Family of 01/08. Home selected. Back to Home. **Resume**. Overview with **chapter chips under the player**.
- **Hierarchy:** Player then chapter strip then icon+label tabs. Summary + two-up decisions/outcomes. Actions + Key Moments + Linked Documents. Inspector: Participants, Meeting Details, Tags, **Synced to above Quick Actions**.
- **Components:** chapter chips `00:03 Intro & Overview` … `43:22 Next Steps`; tabs with icons; AI Summary “Generated 2m ago” + refresh; action table with calendar-due icons; Key Moments `6` (four cards visible); Linked Documents `3`.
- **Interactions:** chapter chip seek; regenerate/refresh summary; same inspector as 08 with Synced-to relocated.
- **States:** paused (Resume); generated-ago freshness.
- **Motion (still):** none.
- **Ambiguity vs 08/05:** chapter UI is chips (10), named markers on waveform (05), numbered markers (08). Pick one in the screen contract; do not ship all three.

---

## 2. Cross-image convergence and contradictions

### Convergence (seen in a majority of relevant frames)

| Topic | What converges | Images |
|---|---|---|
| Shell | Hidden title bar, traffic lights on left, dark UI, orange primary CTA | 01–10 |
| Primary actions | **Record** filled orange pill (Resume on paused) + **Quick note** outline | 01,02,04,05,07,09 (Quick note+Record); 08,10 Resume |
| Sidebar destinations | Home, Dictation, Meetings, Notes, Files | 01,02,04,05,06,07,08,09,10 (04–06 add Live Recording, drop search-in-sidebar) |
| Collections | Product / Engineering / … with counts, add control | all except 03 |
| Integrations row | Calendar + Slack + Notion + (Linear **or** Jira) | all except 03 |
| Meeting workspace | Player + tabs Overview / AI Notes / Transcript / Action Items / Tasks + right inspector | 01,05,06,08,10 |
| Transcript row | timestamp + speaker + text + bookmark; selected = orange stroke | 01,06 |
| Dictation library | period, search, stats, day groups, Load more, live inspector | 02,07,09 |
| Dictation stats | WPM, words, time saved, apps used, Accuracy | 02,07,09 |
| Permissions set | Mic, system audio, screen, accessibility, notifications, calendar | 03 |
| Language cap | up to 3 | 03; code `LanguageDetection.swift:33` |
| Account chrome | avatar + name + email/menu | 01–10 |

### Contradictions (do not paper over)

1. **Two shells.** Family A (01,02,07,08,09,10): search **in** the sidebar, Meetings as dest, Linear, “Usage this week”, Alex Morgan. Family B (04,05,06): IntentX wordmark, **Live Recording** dest, Search as nav item, Jira, Pro Plan GB, Pablo Vega. Family C (03): Settings nav that matches current Settings tabs.
2. **Home vs Meetings vs Live Recording.** 05/06 highlight Home on a meeting. 01 highlights Meetings on a meeting. 04 makes Live Recording a place. Current code: Home stays active when `selectedFolderID == nil` even with a meeting open (`SidebarView.swift:11-13, 23-28`).
3. **Record vs Resume vs Pause.** 04 has Pause+Stop while recording. 08/10 show Resume. Current engine cannot pause (`RecordingEngine.swift:15-30`).
4. **Inspector content for the same tab.** Transcript: 01 AI Insights + Highlight Reel + talk-time bars + export; 06 Meeting insights + Highlights + Tools + stacked speaker bar. Overview: 05 Participants/Tags/Integrations/Quick actions (no Meeting Details); 08/10 add Meeting Details, Invite, Delete, Synced to.
5. **Player chrome.** 01 markers colored dots; 05 named chapter flags; 06 volume; 08 numbered badges; 10 chapter chips under the player. `1x` is common; volume is not.
6. **Dictation live UI.** 02 = live card **and** inspector. 07/09 = inspector only. Current product = **floating overlay** (`DictationOverlayView.swift:11-46`) + history in the main pane (`DictationHistoryView.swift`).
7. **Accuracy ring.** 02/09 orange, 07 green. No accuracy field in `DictationStats`.
8. **Permissions health math** inside 03 (see inventory).
9. **Star on title.** 05 has it; 01/08/10 do not.
10. **Share.** Present on 01/06/08/10; absent on 05 (Quick note+Record only).
11. **Back to Home.** 01/08/10 yes; 05/06 use a compact chevron+date instead.
12. **Synced-to placement.** 01 footer of inspector; 08 bottom of inspector; 10 above Quick Actions.
13. **Base paint.** 09 is crushed darker (`#0C0F12` chrome sample) than 01/08 (`#191C1D` / `#17191A`). 04 is true gray `#161616`. Current Theme is **warm** `#161412` (`Theme.swift:14`).
14. **Bilingual UI.** 04 inspector and live transcript in Spanish; shell in English. 02 inspector mixes English body + a faded Spanish paragraph.

**Canonical resolution rule used below:** Family A geometry + Family B’s live-recording **stage** (as a meeting state, not a fourth IA) + 03’s Settings IA (already in code) + 06’s transcript honesty. IntentX/Pablo/Alex/Pro Plan/Usage/Accuracy are not adopted.

---

## 3. Canonical Grañipa visual contract

Light tokens are **unverified inference**: every ref is dark, and the app forces `.dark` (`MainWindow.swift:53`, `SettingsView.swift:26`, overlays). Do not ship light until a light frame exists. Tokens below are the dark contract plus a derived light map so T1 is not blocked.

### 3.1 Semantic color

| Token | Role | Dark (adopt) | Light (inferred only) | Evidence |
|---|---|---|---|---|
| `bg` | Window/content | `#141617` | `#F4F5F6` | sampled content ~`#131312`–`#191B1D`; cooler than current `#161412` |
| `bgSidebar` | Sidebar | `#17191A` | `#ECEEEF` | sampled sidebar ~`#17191A`–`#191C1D` |
| `card` | Surfaces | `#1E2123` | `#FFFFFF` | sampled cards ~`#1B1B1B`–`#242526` |
| `border` | Hairline | white 7% | black 8% | matches `Theme.border` 0.07 (`Theme.swift:17`) |
| `strokeStrong` | Overlay edge, selected | white 12% | black 12% | `Theme.swift:27` |
| `fillSubtle` | Active nav, chips | white 8% | black 6% | `Theme.swift:25`; SideItem active fill |
| `fillHover` | Hover wash | white 4% | black 4% | `Theme.swift:26`; `HoverHighlight` |
| `accent` | Primary CTA, tab ink, playhead | `#F05423` | `#F05423` | current `Theme.swift:18`; sampled Record/waveform clusters `#E05020`–`#F86018` |
| `accentGlow` | Record bloom | accent @ 35–45% | accent @ 25% | 01,04 Record pills |
| `textPrimary` | Titles, body | white 92% | `#1A1C1E` | `Theme.swift:21` |
| `textSecondary` | Meta, tabs idle | white 55% | `#5C6166` | `Theme.swift:22` |
| `textTertiary` | Timestamps, hints | white 34% | `#8B9096` | `Theme.swift:23` |
| `statusListening` | Live/rec | `#E24B4A` | same | `Theme.swift:28`; 04 live dot |
| `statusProcessing` | Transcribe/enhance | `#5B8DEF` | same | `Theme.swift:29` |
| `statusDone` | Granted, saved | `#4CD981` | same | `Theme.swift:30`; 03 Granted |
| `statusLoading` | Unknown / not asked | `#E6C35C` | same | `Theme.swift:31`; 03 Unknown |
| `statusFailed` | Denied / error | `#E08A3C` | same | `Theme.swift:32` |
| `statusAction` | Not checked (03 orange badge) | `#E24B4A` or accent | same | 03 “Not checked” — **do not invent a 7th status**; map to listening/action |
| `channelMe` | Mic / Me | `#6FA8DC` | same | `Theme.swift:24`; `SegmentRow.swift:335` |
| `brandPurple` / `brandPink` | Dictation overlay waveform only | `#7C5CFF` / `#E879A8` | same | `Theme.swift:19-20`; `DictationOverlayView.swift:170-174`. **Do not** use on meeting waveforms (refs are orange-only). |

**Rejected as product color:** IntentX wordmark orange-bar logo as an app mark. Grañipa keeps its own icon (`Resources/icon-512.png`).

**Avatar palette:** keep `Theme.avatarColor` (`Theme.swift:52-60`, `AvatarView.swift:109-131`). Do not use photographic faces from the refs.

### 3.2 Typography

| Role | Spec | Notes |
|---|---|---|
| Page title | 28–32 semibold; **serif vs sans is human-decision** | Refs: sans (“Solver Operational Controls”, “Dictation”, “Permissions”). Current Home/Onboarding: serif `Theme.titleFont` 34 (`Theme.swift:35`, `HomeView.swift:44`, `OnboardingView.swift:40`). One-way **brand** choice — not picked here. |
| Meeting title | 28 bold | current `Theme.meetingTitleFont` (`Theme.swift:36`) matches 01/05/08/10 scale |
| Section | 15–17 semibold | inspector card titles |
| Body | 14–15 regular, line spacing ~4–7 | `SegmentRow` 15 + lineSpacing 7 (`MeetingDetailView.swift:355-357`) |
| Meta | 11–13 | timestamps, chips |
| Numeric / timer | tabular figures; live timer **HH:MM:SS** (04, 02 inspector); transcript stamps **MM:SS** (01, 06) | current `RecordingTimer` is `m:ss` (`RecordingSharedViews.swift:54-56`) — extend when ≥1 h |
| Tab | 13 semibold active / regular idle | `MeetingDetailView.swift:184-186` |

Do not copy IntentX marketing subtitle voice into Grañipa chrome. Keep existing dictation subtitle only if it stays honest (“Hold Right ⌥…”), not “We’ll handle the rest.”

### 3.3 Spacing, radius, border, shadow/glow

Keep the tested scale (`ThemeTests.swift:16-22`):

- Space: `M=12` `L=16` `XL=24`. Content horizontal inset ~28 (current meeting header `MeetingDetailView.swift:116`) not Home’s 32/`maxWidth 780` (`HomeView.swift:94-98`) on three-pane screens.
- Radius: `S=8` chips/badges; `M=12` cards/rows; `L=16` large cards; `Overlay=24` HUD/settings health; nav/active = 10 continuous (`SidebarView.swift:216`).
- Border: 1 px `border` on cards; selected transcript/live card: 1 px **accent**.
- Shadow: overlays only (`DictationOverlayView.swift:39` black 28% r18 y8; captions r20 y8). Main window cards are **flat** (no drop shadow in refs).
- Glow: static accent bloom on Record/Stop. **No pulse** when Reduce Motion.

### 3.4 Iconography and density

- SF Symbols. No Slack/Notion/Linear/Jira marks unless that integration is approved (one-way).
- Record = `record.circle`. Dictation = `mic`. Meetings = `calendar` (or current Home list). Notes = `note.text`. Files = `folder` (or `doc`).
- Density: Linear-like, 8 pt grid, compact rows (~44–56 pt dictation/meeting rows). Do not add empty hero padding on three-pane screens.

### 3.5 Geometry and breakpoints

**Verified existing:**

- Main min 960×600 (`MainWindow.swift:55`); default 1120×720 (`GranipaApp.swift:28`); hidden title bar (`GranipaApp.swift:27`).
- Sidebar width **248** (`MainWindow.swift:21`).
- Settings scene 640×600 (`SettingsView.swift:24`).
- Onboarding 540×600 (`OnboardingView.swift:26`).
- Dictation overlay 440×132 (`DictationOverlayView.swift:30`).
- HUD expanded width 520 (`RecordingHUD.swift:175`).
- Captions overlay width 640 (`CaptionsOverlayView.swift:40`).

**Verified from images (visual, not the failed luminance scan):** three-pane on 01,02,04,05,06,07,08,09,10; two-pane Settings on 03. Sidebar occupies ~230–250 px (scan 235–275; adopt **248**). Inspector visually ~280–320 px (automated divider was unreliable: 18–361 — do not use those numbers).

**Adopt:**

| Width | Layout |
|---|---|
| `< 960` | Not supported (keep minWidth). |
| `960–1279` | Sidebar 248 + content. Inspector **collapsed** (button in toolbar to show as a trailing overlay ≥280). Live dictation inspector becomes the existing overlay if the window is this narrow. |
| `≥ 1280` | Sidebar 248 + content + inspector 300. |
| Default | **Human-decision:** keep 1120 (inspector collapsed) vs raise default to 1280 so three-pane is the first launch. Not chosen here. |

Inspector is **new** (`NavigationSplitView` / inspector column: **grep found none**).

---

## 4. Component and state inventory

Classes: **verified-existing** · **new** · **presentation-only** · **excluded** · **human-decision**.

### 4.1 Shell

| Control | Class | Evidence |
|---|---|---|
| Hidden title bar + traffic lights | verified-existing | images 01–10; `GranipaApp.swift:27` |
| Sidebar Home | verified-existing | `SidebarView.swift:23-28` |
| Sidebar Dictation | verified-existing | `SidebarView.swift:30-38` |
| Sidebar Meetings | new | not in `SidebarView`; Home currently *is* the meeting list (`HomeView.swift`) |
| Sidebar Notes | new | meeting Notes tab exists (`MeetingDetailView.swift:16`); no global Notes dest |
| Sidebar Files | new | clipboard type “Files” is unrelated (`ClipboardHistoryView.swift:90`) |
| Sidebar Live Recording | human-decision | 04 only as dest; current HUD window |
| Sidebar Search field | verified-existing | `SidebarView.swift:148-175`; binds `app.searchQuery`; Home searches meetings (`HomeView.swift:100-116`, `AppDatabase.swift:372-392`) |
| ⌘K affordance | new | no `keyboardShortcut` for K; menu bar uses ⌥⇧ (`MenuBarView.swift:68-80`) |
| Collections / folders + add | verified-existing | `Folder.swift`; `SidebarView.swift:41-92`; **counts are new** (API DTO has `meetingCount` `APIRouter.swift:70-75`, sidebar UI does not) |
| Integrations: Calendar | verified-existing as EventKit | `CalendarService.swift`; detection/upcoming on Home |
| Integrations: Slack/Notion/Linear/Jira | human-decision (one-way auth) | no Swift clients; webhooks are generic URL (`SettingsView.swift:998-1028`) |
| Usage / Upgrade / Pro Plan GB | excluded | billing fiction; no entitlements in repo |
| Account menu (Alex/Pablo) | excluded | no accounts (`OnboardingView.swift:47` “no accounts, no telemetry”) |
| IntentX wordmark | excluded | brand reference only |
| Quick note | verified-existing | `HomeView.swift:47-54` → `AppState.createMeeting` (`AppState.swift:277`) |
| Record | verified-existing | `HomeView.swift:56-68`; `MenuBarView.swift:49`; `RecordingBar.swift:29-37` |
| Resume / Pause | new + human-decision | no pause in `RecordingEngine` |
| Share / Copy meeting link | excluded unless local-only | no share URL; API is localhost bearer (`SettingsView.swift:960-991`) |
| Overflow `…` | verified-existing as menu | `MeetingDetailView.swift:151-174` (folder, template, export, copy transcript) |

### 4.2 Dictation

| Control | Class | Evidence |
|---|---|---|
| Period picker All time / week / today | verified-existing | `DictationPeriod` `DictationHistoryView.swift:4-26, 92-97` |
| Search dictations | verified-existing | `DictationHistoryView.swift:129-137, 217-221`; SQL LIKE `AppDatabase.swift:209-227` |
| Extra filter button | new | not in history view |
| Stats WPM / words / apps / saved | verified-existing | `DictationStats` `DictationEntry.swift:26-59`; UI `DictationHistoryView.swift:100-109`; tests `DictationHistoryTests.swift` |
| Sparklines on stats | presentation-only | `MeetingSparkline` is a **seeded fake** for meeting rows (`MeetingSparkline.swift:3-19`, `ThemeTests.swift:26-32`) — do not reuse as “real” dictation trend |
| Apps-used logos | presentation-only | count is real; glyphs of Notion/Slack are not |
| Accuracy % | excluded | no metric; human-decision if a **substitute** is shown (probe confidence exists in `LanguageDetection.swift:9-21` but is not accuracy) |
| Live session card | new | overlay is the live UI today |
| Row play / waveform | new + human-decision | **no dictation audio file** in schema (`AppDatabase.swift:125-132`) |
| Title, tags, language, star, type tabs, grid | new | would need additive columns; tags/favorites are one-way-ish persisted shape |
| Load more / “25 of 342” | new | fetch `limit: 500` (`AppDatabase.swift:209`) |
| Inspector live transcript | new as column; overlay verified-existing | `DictationOverlayView.swift`; `DictationController.swift:14-15, 312-320` |
| On-device / Muse label | verified-existing | `DictationOverlayView.swift:123-125`; Settings engine picker `SettingsView.swift:338-341` |
| Language + mic pickers in live panel | new (partial) | dictation locale picker in Settings (`SettingsView.swift:327-336`); no in-panel mic device picker found |
| Press again to stop | verified-existing | toggle path `DictationController.swift:49-50`; overlay copy `DictationOverlayView.swift:132` |
| Auto-save copy | verified-existing behavior | `AppState.recordDictation` `AppState.swift:117` |

### 4.3 Live recording / player

| Control | Class | Evidence |
|---|---|---|
| Timer | verified-existing | `RecordingTimer` `RecordingSharedViews.swift:44-57`; HUD `RecordingHUD.swift:117-120` |
| Dual level meters Mic/System | verified-existing | `LevelMeter` `RecordingBar.swift:65-82`; HUD `RecordingHUD.swift:133-134`; gated 0.25s `LevelGate.swift:9`, `RecordingEngine.swift:25,46-49` |
| Full-width live waveform | new | dictation overlay waveform is 40 bars @ 30 fps (`DictationController.swift:14`, `DictationOverlayView.swift:161-164`) — meeting HUD does not draw a waveform |
| Pause / Resume | new + human-decision | |
| Stop | verified-existing | HUD/Bar/MenuBar |
| Mark moment `⌘B` / Mark action `⌘M` | new | no bookmark table |
| In-meeting Quick note `⌘N` | verified-existing as Notes tab editor | `MeetingDetailView.swift:208-226`; shortcut not bound |
| Language picker live | verified-existing as meeting.language / Settings defaultLocale | `SettingsView.swift:131-136`; header chip `MeetingDetailView.swift:83-90` |
| Mic picker | new | no input-device menu in UI |
| Auto-scroll | new | live transcript auto-scrolls always (`MeetingDetailView.swift:297-301`) with no toggle |
| AI live summary / action extraction | human-decision (one-way: AI live) | enhancement is **post-stop** (`EnhancedNotesView.swift:40`, `AppState` pipeline). `liveMeetingASR` default false (`MeetingASRPolicy.swift:13-17`, hang-handoff) |
| Concentric timer rings | presentation-only | decorative; skip or Reduce Motion off |
| Playback transport (play/pause, 1x, expand, seek, volume) | new | **no AVPlayer** in repo |
| Chapter markers / chips | new | no chapter model |
| HUD compact pill / expanded card | verified-existing | `RecordingHUD.swift:66-183` — **keep** even if a live stage is added; do not delete the floating HUD |
| Captions overlay | verified-existing | `CaptionsOverlayView.swift`; gated on live ASR |
| “Transcript after you stop” | verified-existing | `RecordingHUD.swift:167-170` when live ASR off |

### 4.4 Meeting overview / transcript / notes

| Control | Class | Evidence |
|---|---|---|
| Tabs Notes / Enhanced / Transcript | verified-existing | `MeetingDetailView.swift:16-19, 176-204` |
| Rename to Overview / AI Notes / Transcript / Action Items / Tasks | new (Tasks split is human-decision) | Action items already render in Enhanced (`EnhancedNotesView.swift:72-81`) |
| Tab counts | new | |
| AI Summary | verified-existing | `Meeting.summary` `Meeting.swift:20`; `EnhancedNotesView.swift:56-61`; prompt `EnhancementService.swift:80-81` |
| Enhanced notes markdown | verified-existing | `enhancedNotesMarkdown`; `MarkdownView.swift` parser |
| Action items check + owner | verified-existing | `ActionItem.swift`; toggle `AppState.swift:599`; **due date / In progress status / separate Tasks** = new (due currently stuffed into `text` by prompt `EnhancementService.swift:84-87`) |
| Email draft | verified-existing | `EnhancedNotesView.swift:84-109` — **not in refs**; keep, do not delete |
| Key Decisions / Key Outcomes / Key Moments | new | not in `EnhancementResult` keys (`EnhancementService.swift:3-16`) — additive JSON keys or sections inside `enhanced_notes` |
| Participants list / Invite | human-decision | no attendees on `CalendarMeeting`; speaker names via optional LLM map `SpeakerMapping.swift:32-39` |
| Tags / star / collections on meeting | new | folder is the only grouping (`Meeting.folderID`, v4 `AppDatabase.swift:88-97`) |
| Linked documents | new | no files table |
| Highlight reel / bookmarks / highlights | new | no columns on `transcriptSegment` (`AppDatabase.swift:46-56`) |
| Speaker rename | verified-existing | alert `MeetingDetailView.swift:44-58`; `AppDatabase.renameSpeaker` `AppDatabase.swift:419` |
| Speaker breakdown % | new (derivable) | durations exist (`startSeconds`/`endSeconds`); do not invent % |
| Transcript search / speaker filter | new | global meeting search exists; not in-transcript |
| Pagination 50/582 | new | list is lazy but fully loaded |
| Export Markdown / copy transcript | verified-existing | `MeetingExporter.swift:54-75` |
| Export summary / transcript as separate files | new | one markdown blob today |
| Delete meeting | verified-existing | `HomeView.swift:296-298` context menu; 08/10 inspector |
| Add to calendar | new | EventKit is read-upcoming, not write |
| Regenerate / Enhance now / Re-enhance | verified-existing | `EnhancedNotesView.swift:43, 131-141` |
| RecordingBar on meeting | verified-existing | `MeetingDetailView.swift:112` |

### 4.5 Permissions / settings

| Control | Class | Evidence |
|---|---|---|
| Seven settings destinations | verified-existing | `SettingsView.swift:8-22` ≡ 03 sidebar |
| Permission rows + Request/Open Settings | verified-existing | `PermissionsView.swift` |
| System audio Check/probe | verified-existing | `PermissionCenter.probeSystemAudio` `PermissionCenter.swift:56-70` |
| Rescan all | new (refresh exists) | `.task` + `didBecomeActive` `PermissionsView.swift:68-74` |
| Health summary / Fix recommended | new (presentation of existing states) | |
| Deep link System Settings | verified-existing | pane URLs `PermissionsView.swift:12, 39, 49, 55, 61, 66` |
| Languages up to 3 | verified-existing | `LanguageDetection.maxProbeLocales`; Settings toggles `SettingsView.swift:138-154` |
| Manage languages / model freshness “up to date” | human-decision | Speech installs exist (`SpeechModels` in tree); “last update 9:41 AM” is mock |
| On-device / local storage copy | verified-existing product policy | onboarding `OnboardingView.swift:47`; Settings captions |
| Permission monitoring toggle | new | no watcher beyond become-active refresh |
| Video capture permission | human-decision (one-way) | Screen Recording is OCR-only (`PermissionsView.swift:57-61`). 08 “HD Video & Audio” is excluded as capability unless video is approved |

### 4.6 Notes and Files screens (no dedicated ref)

| Screen | Class | Notes |
|---|---|---|
| Notes as global library | new | refs show the dest; no image of the page; do not fake content |
| Files as meeting attachments | new | same |
| Files as clipboard history | verified-existing elsewhere | overlay `ClipboardHistoryView.swift`; do not conflate |

---

## 5. Motion and ultra-lightweight budgets

Context: hang-handoff (`docs/wip/2026-09-04-hang-handoff.md`) measured **~100–135% CPU during Record** with 0 idle wakeups after live ASR off. UI was **not** the proven core hog; still, V2 must not add a second hot path. `liveMeetingASR` stays default **false** unless the human opens that door.

### 5.1 Motion tokens (existing)

| Token | Value | Where |
|---|---|---|
| `Theme.motionFast` | 0.08 s | `Theme.swift:41`; hover `Theme.swift:97-98` |
| `Theme.motionNormal` | 0.15 s | `Theme.swift:42`; detection banner `MainWindow.swift:47-49` |
| `PanelMotion.show/hide` | 0.34 / 0.20 s, rise 40 | `PanelMotion.swift:6-9`; Reduce Motion snaps `PanelMotion.swift:33-36, 49-53` |
| Tests | lock the above | `ThemeTests.swift:7-13` |

**Adopt:** keep these. Do not add springy per-bar waveform animation on the meeting player (old redesign notes mentioned it; hang risk).

### 5.2 Reduce Motion

Already read at: `MainWindow.swift:7, 32-34, 47-48`; `Theme.swift:88, 97-98`; `DictationOverlayView.swift:5, 43-45, 161-164`; `PanelMotion.swift:19-21`.

**Contract:**

- No concentric-ring pulse (04).
- No Record glow pulse; static bloom OK.
- Waveform: show last samples as a static `Canvas`; **pause** `TimelineView` (`DictationOverlayView.swift:163-164` already pauses when `reduceMotion \|\| !isActive`).
- Inspector/sidebar layout changes: opacity crossfade only, no move.
- Auto-scroll: jump, do not animate.

### 5.3 Waveform sampling / FPS

| Path | Today | V2 budget |
|---|---|---|
| Dictation bars | 40 (`DictationController.waveformBars`, `ThemeTests.swift:23`) | **keep 40**; do not raise |
| Dictation push | `LevelGate(minInterval: 0.08)` (`DictationController.swift:32`) ≈ 12.5 Hz | **≤ 12 Hz** |
| Dictation render | `TimelineView` `1/30` (`DictationOverlayView.swift:161-164`) | **≤ 24 fps** (V2 T9). 30 fps already over budget — lower, do not add a second TimelineView |
| Gain/envelope | `WaveformGain.display`, `WaveformEnvelope.next` | keep; do not run extra sine “life” when Reduce Motion (`DictationOverlayView.swift:204-206` adds motion from `phase`) |
| Meeting levels | `LevelGate()` default **0.25 s** (`LevelGate.swift:9`, `RecordingEngine.swift:25`) | keep ≥ 0.25 s to MainActor; never publish from IOProc |
| Meeting player waveform | does not exist | **precompute** peaks off-main after Stop (file read once); live Record must **not** FFT every buffer. If a live sparkline is required, reuse gated RMS, **≤ 12 Hz**, **≤ 24 fps**, cap bar count ≤ 64 |
| Fake Home sparkline | `MeetingSparkline` 52 stable samples | presentation-only; do not drive it from audio on the list |

Hang-handoff remains binding: no extra `deepCopy`/RMS on the system tap for prettier bars.

### 5.4 Lists, search, cancellation

Already:

- Home `LazyVStack` + 200 ms search debounce + `Task.detached` + cancel (`HomeView.swift:41, 81, 100-115`).
- Transcript `LazyVStack` + `scrollTo` (`MeetingDetailView.swift:276, 297-301`).
- Dictation `LazyVStack` + 140 ms debounce (`DictationHistoryView.swift:80-86, 172`).
- Meeting title/notes save 500 ms debounce (`MeetingDetailView.swift:317-324`).

**Adopt:**

- Keep lazy stacks. Do not wrap every card in `ScrollView` of eager `VStack`.
- Transcript: if 582-line pager is adopted, page in **chunks of 50** from GRDB (`LIMIT/OFFSET` or keyset on `startSeconds`) — do not load 582 eager views.
- Dictation “25 of N”: replace silent `limit: 500` with explicit page size 25–50; cancel in-flight search on period change (already cancels debounce task).
- Recording start task already cancelled on stop (`AppState.swift:19, 370-371` pattern) — any live-AI or peak-extract `Task` must use the same cancel.
- Do not observe volatile ASR in the transcript list (comment at `MeetingDetailView.swift:289-291` — keep that constraint).
- Player seek: decode on a background queue; cancel prior seek.

### 5.5 CPU / hang budget (product, not a new number)

- Idle: no `TimelineView` running.
- Dictation listening: one 24 fps canvas + 12 Hz RMS, overlay only.
- Record with live ASR **off** (default): HUD timer 1 Hz (`RecordingSharedViews.swift:48`) + two gated meters. **No** meeting-page waveform TimelineView.
- Record with live ASR **on** (opt-in): still no extra waveform FFT; captions/HUD snippet only.

---

## 6. Screen contracts

Empty / error / processing / ready must be real. Do not populate with Solver Operational Controls, 96%, 4h 32m, or named coworkers.

### Shared shell

- Columns: sidebar 248 | content | inspector 300 (≥1280).
- Sidebar: Search, Home, Dictation, then **human-decision** Meetings vs keep Home as the meeting inbox. Notes and Files: destinations exist in refs → include as nav **only** with empty states until T7 data exists. Collections = `Folder`. Integrations: Calendar row can deep-link Settings or show EventKit status; Slack/Notion/Linear/Jira **hidden** until approved.
- Footer: **Settings** link (`SidebarView.swift:110-120`) instead of fake account/plan.
- Header (non-settings): Quick note + Record. Record disabled when `recorder.isBusy` (`HomeView.swift:68`). If pause is approved, Record becomes Pause/Resume/Stop per state.
- Detection banner stays (`MainWindow.swift:29-34, 87-111`).
- Color scheme: dark until a light ref exists.
- No IntentX mark. App name Grañipa.

### Home

- **No Home list appears in the 10 refs.** Contract from current `HomeView.swift` + “Back to Home” on 01/08/10.
- Title: serif-or-sans per brand decision. Hero upcoming calendar card stays (`HomeView.swift:71-73, 157-214`) — real EventKit, not mock participants.
- Body: day-grouped meetings, pipeline phase labels (`RecordingSharedViews.swift:11-20`), real sparkline **or** drop the fake one (human-decision: seeded sparkline is presentation-only).
- Empty: existing copy (`HomeView.swift:119-154`).
- Selecting a meeting opens Overview if audio exists, Notes if quick note (`MeetingDetailView.swift:23-27` already centers transcript vs notes).
- Inspector on Home list: **off** (refs never show an inspector on a list of meetings).

### Dictation

- Main: period, search, **real** stats (WPM/words/apps/saved). **No Accuracy tile.**
- List: time, text (or first line as title until a title column exists), `sourceApp`, duration, word count. Play/star/tags **hidden** until audio/tags exist.
- Live: keep **overlay** for hold-to-talk (product already ships). If the window is ≥1280 and Dictation is selected, **also** show the inspector transcript (02/07/09) bound to `DictationController` — same session, not a second mic.
- Empty: existing (`DictationHistoryView.swift:149-168`).
- Pagination: “Showing k of n” + Load more if n > page size; else omit.
- Do not show a live-session **library card** and the inspector at once (contradiction 02 vs 07). Pick inspector + overlay; drop the duplicate card.

### Live Recording

- Not a fake sidebar app. **State of a meeting:** either the HUD (current, always) or a full-page stage when the recording’s meeting is selected (04).
- Required real controls: timer, mic+system meters, Stop, warnings (`RecordingBar.swift:41-46`).
- Optional (human-decision): Pause/Resume, language chip, bookmarks, live transcript (only if `liveMeetingASR`), auto-scroll toggle.
- AI Assistant live summary: **off** unless AI-live is approved. Show processing/empty, not invented Spanish paragraphs.
- When live ASR is off, keep “Transcript after you stop” (`RecordingHUD.swift:168`).
- Rings: omit, or static.

### Meeting Overview

- Player: **after Stop** (file playback) — new. Until playback exists, show duration + Record/Resume only (current `RecordingBar`).
- Tabs: Overview | AI Notes (= Enhanced) | Transcript | Action Items. **Tasks** as a separate tab is human-decision (duplicate of action items otherwise).
- Overview body: Summary (real `meeting.summary` or empty), enhanced sections if present, action items. Do not split “Key Decisions/Outcomes” until the prompt/schema adds them (additive).
- Inspector: details we actually have (createdAt, language, folder, duration from startedAt/endedAt, calendarEventID if any). Participants = diarized speakers + Me, not Invite. Tags = folders/chips only if T7 ships. Quick actions: Export notes, Copy transcript, Delete. No Copy link, no Synced to.
- States: processing (`MeetingStatus.processing`, pipeline phases), failed transcription (`MeetingDetailView.swift:242-258`), empty enhanced (`EnhancedNotesView.swift:33-47`).

### Transcript

- Honest segments: `speaker`, `startSeconds`, `text` (`TranscriptSegment.swift:9-17`). Prefer 06’s unlabeled **Speaker N** until `SpeakerMapping` names them; letter avatars not stock photos.
- Selected row: accent stroke; play **only** when playback exists.
- Bookmark/highlight: hide until persisted.
- Search/filter: in-pane search is new; until then, do not paint ⌘F chrome that no-ops.
- Speaker %: derive from `end-start` sums; hide if no system-channel diarization.
- Rename: keep context menu (`MeetingDetailView.swift:280-286`).
- Live volatile text stays out of this list (`MeetingDetailView.swift:289-291`).

### Permissions

- Use 03’s **layout** on the existing Permissions pane: health strip derived from the six `PermissionState`s, then the list, then languages, then privacy copy.
- Status vocabulary: Granted / Denied / Not asked / Unchecked (system audio). Map 03 “Not checked” → Unchecked, “Unknown” → Unchecked or Not asked. Do not show “2 of 6” unless it equals the count of non-granted.
- Actions: Request when notDetermined; Open Settings when denied; Check when system-audio unchecked (`PermissionsView.swift` already).
- Rescan all = `PermissionCenter.refresh()` + probe system audio only on explicit Check (probe **creates a real tap** — `PermissionCenter.swift:52-55` comment). Do not probe in a loop.
- Languages: existing up-to-3 toggles, not a fake “models up to date” clock.
- Keep Settings as the **Settings scene** (macOS) unless the human wants 03’s in-window settings shell (two-way). Labels already match.

### Notes

- Per-meeting editor stays (`MeetingDetailView.swift:208-226`).
- Global Notes dest: empty state “No notes yet” until T7 defines the object. Do not show dictation snippets as notes without a join table.

### Files

- Empty state until T7. Do not reuse clipboard Files filter as this screen.
- Meeting `audioMicPath` / `audioSystemPath` are recordings, not a document library — if shown, label them “Recordings” and list real m4a URLs, no Google Doc/Slides mocks.

---

## 7. Traceability appendix

Legend: **A** adopted into the contract · **R** rejected · **P** presentation-only · **H** human-decision · **E** excluded (fiction / other brand).

### 01

| Detail | Verdict |
|---|---|
| Three-pane meeting + transcript | A |
| Meetings dest highlighted | H (vs Home-as-inbox) |
| Record pill + glow | A (static glow) |
| Share, copy link, Synced to | E |
| Player + 1x + expand | A as post-stop playback (new) |
| Colored waveform markers | H (vs 05 names / 10 chips — pick one later) |
| Tabs including Tasks | H |
| Transcript search/filters/pager | A as new, honest |
| Photos of people | R (use `AvatarView`) |
| Highlight Reel 6 | H/new |
| Talk time bars | A derived |
| Usage 4h32m / Upgrade | E |
| Alex Morgan / mindtale.ai | E |
| 582 lines / 50-page | A as budgeted paging if counts are real |

### 02

| Detail | Verdict |
|---|---|
| Dictation dest + library | A |
| Real stats WPM/words/apps/saved | A (existing formulas) |
| Accuracy 96% | E |
| App logos in stats | P |
| Live card + inspector duplicate | R duplicate; A inspector or overlay, not both |
| Titles/tags/star/play | H (schema) |
| Load more | A |
| On-device + press again | A |
| Spanish faded paragraph | P (don’t fake bilingual preview) |
| Auto-save | A |

### 03

| Detail | Verdict |
|---|---|
| Settings IA 7 items | A (already `SettingsView`) |
| Six permissions + Check | A |
| Health strip | A if math is honest |
| “2 of 6” copy | R (contradicts its own list) |
| Fix recommended | A as jump to first non-granted |
| Up to 3 languages | A |
| Models up to date 9:41 AM | R mock |
| Pro Plan 78/100 GB | E |
| IntentX wordmark | E |
| Permission monitoring toggle | H |
| Camera/video in health icons | H (video one-way) |
| In-window settings vs Settings scene | H (two-way) |

### 04

| Detail | Verdict |
|---|---|
| Live stage timer/waveform/Stop | A as meeting state + HUD |
| Live Recording sidebar dest | H |
| Pause ⌘⇧P | H (engine) |
| Mark moment/action | H |
| AI live summary / topics | H (AI live one-way) |
| Action items due while recording | H |
| Concentric rings | P/R |
| Spanish live copy | A only if locale is es (real) |
| Jira / Pro Plan / Pablo | E |
| Record button while already live | R (confusing) |

### 05

| Detail | Verdict |
|---|---|
| Overview cards | A summary + actions; Decisions/Outcomes H |
| Named chapters on waveform | H (conflict with 08/10) |
| Participants 5 Host | H |
| Tags | H/T7 |
| Notion/Jira/Slack integrations | H/E until approved |
| Quick actions Share/link | E |
| Export notes | A |
| Add to collection | A as folder |
| Create follow-up task | H vs action items |
| Status In progress | H (schema) |
| Star on title | H |
| Search anything ⌘K | A as new shortcut on existing `searchQuery` |
| Home selected on meeting | A compatible with current `isHomeActive` |

### 06

| Detail | Verdict |
|---|---|
| Speaker S1/S2 honesty | A |
| Volume on player | H (only this frame) |
| All speakers filter | A new |
| 78 results + auto-scroll | A |
| Highlights list | H/new |
| Create highlight reel | H |
| Stacked speaker bar | A derived |
| Disfluent text | A (do not rewrite live) |

### 07

| Detail | Verdict |
|---|---|
| Library without live card | A (canonical vs 02) |
| Green accuracy ring | E (accuracy itself excluded) |
| Auto language on Detected | A if locale is auto |

### 08

| Detail | Verdict |
|---|---|
| Resume CTA | H with pause |
| Meeting Details ID/Google Meet/HD Video | E video; location only if calendar has it (joinURL exists `CalendarService.swift:10`) |
| Invite | E/H |
| Key Moments faces | P (no face crop pipeline) |
| Linked Google Doc/Slides | E until Files T7 |
| Delete meeting | A |
| Add to calendar | H (write EventKit) |
| Numbered waveform markers | H |

### 09

| Detail | Verdict |
|---|---|
| Type tabs Notes/Imports | H/T7 |
| Grid toggle | H (default list) |
| In-row playing waveform | H (needs audio file) |
| Darker paint | R (don’t special-case 09) |
| Shield auto-save | A copy |

### 10

| Detail | Verdict |
|---|---|
| Chapter chips under player | H (preferred over stacking 05+08+10) |
| Generated 2m ago | A if timestamp is real enhance time (not stored today — would be additive) |
| Synced to above Quick Actions | E |
| Icon tabs | A optional; text tabs already exist |

---

## One-way doors (not chosen)

From the V2 plan and this audit. Implementation must not pick these silently:

1. **Local vs cloud ASR / AI live** — `liveMeetingASR` default false; Muse opt-in; live inspector summaries.
2. **Integrations + auth** — Slack/Notion/Linear/Jira/Google Docs vs keep local API + HMAC webhooks.
3. **Audio retention for dictation playback** — storing dictation PCM/m4a.
4. **Video / screen as a recording channel** — 08 “HD Video”; camera icon on 03.
5. **Participants/contacts identity** — photos, Invite, roles.
6. **Accuracy substitute** — what, if anything, replaces the 96% tile.
7. **Brand type** — keep Grañipa serif titles vs sans from the refs.
8. **Pause/resume recording** — new session semantics vs start/stop only.
9. **Tasks vs Action items** — two persisted lists or one.
10. **Accounts / billing / usage caps** — excluded unless a real entitlement exists.
11. **Raising default window size** so three-pane is first-run.
12. **Localization** of chrome (04 mixes EN shell / ES content).

Additive GRDB only if any of 3, 5, 8, 9, 10 ship (`AppDatabase.swift` v1…v8 append-only; `AGENTS.md`).

---

## Code map (current UI, not a redesign)

| Surface | File |
|---|---|
| Shell | `Sources/Granipa/UI/MainWindow.swift`, `SidebarView.swift` |
| Home | `HomeView.swift` |
| Meeting | `MeetingDetailView.swift`, `EnhancedNotesView.swift`, `RecordingBar.swift` |
| Dictation main | `Dictation/DictationHistoryView.swift` |
| Dictation live | `DictationOverlayView.swift`, `DictationController.swift` |
| Record HUD | `RecordingHUD.swift`, `RecordingSharedViews.swift` |
| Permissions | `PermissionsView.swift`, `System/PermissionCenter.swift` |
| Settings | `SettingsView.swift` |
| Theme | `Theme.swift` + `ThemeTests.swift` |
| Persistence | `Storage/AppDatabase.swift` v1–v8 |

---

## Unresolved (for the director / human)

1. Family A vs B sidebar (Meetings dest + search-in-sidebar vs Live Recording dest + Search nav).
2. Pause/Resume vs Stop-only.
3. Inspector default-on (raise window default) vs collapsed at 1120.
4. Serif vs sans page titles.
5. Accuracy tile substitute or omit (this audit omits).
6. Which chapter UI: chips (10), named flags (05), or numbered (08).
7. Global Notes/Files information architecture before T7 schema.
8. Settings scene vs in-window Settings (03).
9. Whether the floating dictation overlay remains once an inspector exists.
10. AI live during Record (blocked by hang history until proven otherwise).
