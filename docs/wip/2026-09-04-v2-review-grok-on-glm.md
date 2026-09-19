VERDICT: ISSUES

Review of GLM T0 architecture audit `8cb7ac1:docs/wip/2026-09-04-v2-audit-glm.md`.
Reviewer: Grok lane `docs/v2-audit-grok` @ `3789b96`. Audited tree: `c7704c3`.
This file does not rewrite GLM's report. It does not pick one-way product doors.

**How this was checked.** GLM's text was read in full via `git show 8cb7ac1:…`.
Disputed claims were checked against current Swift in this worktree. Images
were already inspected for Grok's own T0 (`docs/wip/2026-09-04-v2-audit-grok.md`);
image statements below name the PNG. Not re-run: `swift test` wall-clock,
`top`, disk `du` of `~/Library/Application Support/Granipa`. Test **count**
was re-counted from source (`@Test` / `@Suite`).

Labels: **V** = verified this session in source or a named PNG. **U** =
inference.

---

## Issues

Each item: GLM section → evidence → consequence → correction.

### I1. Silent collapse of Tasks into Action Items

- **Section:** Appendix A ref 01 (“Tasks tab has no data model today — treat
  Action Items as the single tasks source (no new table)”); §3 C7.
- **Evidence:** Images **01, 08, 10** show **both** tabs with **different
  counts** (Action Items `4`, Tasks `3`). Current model is one list
  (`ActionItem.swift:3-6`, `actionItemsJSON` in `AppDatabase.swift:39`).
- **Consequence:** Implements a different IA than the refs. Conflicts with
  the request to deliver everything shown. Locks a persisted shape without
  a human door.
- **Correction:** Keep both tabs in the inventory. Empty Tasks is allowed
  until a human picks “same rows / second list / derived filter”. Do not
  ship C7 as “Tasks = Action Items”.

### I2. Notes and Files destinations dropped from “smallest V2”

- **Section:** Appendix A cross-cutting (“Files/Notes nav items have no data
  models and are out of the smallest V2”).
- **Evidence:** Images **01, 02, 04, 05, 06, 07, 08, 09, 10** all show
  sidebar **Notes** and **Files**. No Swift destination exists
  (`SidebarView.swift:23-38` is Home + Dictation only) — **V**.
- **Consequence:** The shown shell is not delivered. Empty-state nav is not
  a one-way door; omitting the dest is a silent scope cut.
- **Correction:** Inventory Notes and Files as shown destinations with empty
  / error states. Schema for their objects stays a human/T7 door. Do not
  treat “no table today” as “out of V2”.

### I3. Resume read as re-record; Pause deferred as if they were unrelated

- **Section:** Appendix A 04 (Pause “explicitly deferred”); Appendix A 08
  (“Resume = continue recording of a stopped meeting … treat as re-record
  into same meeting folder, a product decision, not in C1–C15”).
- **Evidence:** Image **04** has Pause + Stop on a live session. Images
  **08** and **10** show **Resume** (not Record) on the same meeting chrome.
  `RecordingEngine` is start/stop/`isBusy` only (`RecordingEngine.swift:15-30`)
  — **V**. Stop today is terminal per meeting — **V**.
- **Consequence:** GLM both defers Pause and **picks** a Resume meaning
  (append/re-record after stop). 04+08/10 also read as pause/resume of one
  session. That is a one-way engine door, already listed, then decided in
  the appendix.
- **Correction:** One human door: pause/resume vs stop-only vs re-record
  into the same meeting. Until then, keep Resume/Pause **visible in the
  inventory** and **out of C1–C15**. Do not encode “re-record” as the
  architecture.

### I4. Live recording stage is not “view composition over existing state”

- **Section:** §2 “Explicitly not seams” (“live recording stage (timer,
  rings, levels, Stop, mark-moment, quick note — all existing state; only
  the view is new)”); contradicts §3 C14 (depends C2 waveform, C9 mark
  moment) and Appendix A 04.
- **Evidence:** No meeting waveform, no bookmarks table, no pause, no
  in-window mic device picker — **V** (Grok T0 greps; GLM §1.7 agrees).
  Timer/levels/Stop exist (`RecordingHUD.swift`, `RecordingBar.swift`).
- **Consequence:** Implementers will treat C14 as a SwiftUI restyle of the
  HUD and miss new capture/UI seams. Rings + live waveform during Record
  are the hang window (`docs/wip/2026-09-04-hang-handoff.md`).
- **Correction:** Strike “only the view is new”. Split: HUD restyle
  (existing state) vs live stage extras (peaks, marks, pause, pickers,
  rings) each with an explicit seam or a human door.

### I5. Capture-time peaks coupled to the live Record stage (hang-class)

- **Section:** §2 seam 2; §3 C2 → C14; §4 “Animation frames … 30 fps”;
  §4 waveform “≤ 1 % CPU during capture”; §5 “waveform peaks … must not add
  work to the IOProc”.
- **Evidence:** Hang-handoff last failure: pid 62139, **103 % CPU, 0 idle
  wakeups**, live ASR already off. Suspects include per-buffer RMS /
  `deepCopy` / writer (`hang-handoff.md`). Today UI levels are
  `LevelGate` **0.25 s** (`LevelGate.swift:9`, `RecordingEngine.swift:25`).
  Dictation overlay is already **30 fps** `TimelineView`
  (`DictationOverlayView.swift:161-164`) on **12.5 Hz** samples
  (`DictationController.swift:32`) — **V**. V2 T9 asked waveform **≤ 24 fps**.
- **Consequence:** C14 “depends C2” makes a full live waveform a Record-path
  feature. Even “off the writer path”, a second consumer of per-buffer RMS
  plus a 30 fps stage repeats the hang lesson. 30 fps during Record is
  over the overlay’s already-hot pattern and over T9.
- **Correction:** Peaks for **post-stop playback** = file scan after Stop
  (legacy backfill path GLM already names). Live Record UI keeps gated
  meters + 1 Hz timer. If a live sparkline is required, cap **≤ 12 Hz
  publish, ≤ 24 fps render, Reduce Motion = static**, and add a test that
  Record does not raise MainActor level-publish rate (missing today). Do
  not make C14 depend on C2.

### I6. Accuracy ring folded into billing/metering and dropped

- **Section:** §7.8 “Blocks: usage quota card, upgrade CTA, **accuracy
  ring**”; Appendix A 02 “accuracy ring §7.8”.
- **Evidence:** Images **02, 07, 09** show a **96% Accuracy** tile. No
  accuracy field in `DictationStats` (`DictationEntry.swift:26-59`) — **V**.
  Usage/Upgrade/Pro Plan GB are separate chrome (sidebar/settings), not the
  dictation stat row.
- **Consequence:** A shown control is excluded by bundling it with accounts
  / telemetry (a real one-way door). The ring is not itself billing.
- **Correction:** Keep 7.8 for quota/upgrade/accounts. Accuracy stays an
  **undecided substitute** (omit vs probe-confidence vs other). Do not
  treat “no metric today” as “blocked by billing”.

### I7. “No external HTTP except Muse/webhooks” is false

- **Section:** §7.2 (“No OAuth client, no token flow, **no external HTTP
  except Muse/webhooks** exists today (V)”).
- **Evidence:** `RewriteClient` POSTs to `https://api.x.ai/v1` or a custom
  OpenAI-compatible URL (`RewriteClient.swift:21-22, 99-107`). Sparkle is a
  dependency (`Package.swift:11, 19`). Webhook three-caller race
  (`AppState.swift:247, 482, 547`) is real — **V**.
- **Consequence:** Integration discussion undercounts existing network
  surfaces. “V” is wrong.
- **Correction:** Restate: no OAuth; HTTP today = Muse WebSocket, webhooks,
  optional rewrite, Sparkle. Integrations remain a human door.

### I8. `ActionItem.done` is not a GRDB column precedent

- **Section:** §2 seam 4 (“nullable columns decode old rows unchanged,
  mirroring the `ActionItem.done` precedent”).
- **Evidence:** `done` is an optional JSON field on a blob
  (`ActionItem.swift:5`, `LLMTests.swift:49-59`). Column adds use
  `alter(table:)` (`AppDatabase.swift:95-97` v4 `folderID`) — **V**.
- **Consequence:** A v9 author may treat JSON optionality as a migration
  pattern and skip an upgrade-path test (GLM’s own G3).
- **Correction:** Cite v4 `folderID` (nullable column) and the `done` JSON
  test separately. Keep G3.

### I9. C11 mixes dictation cards with meeting Key Moments

- **Section:** §3 graph “C9 ──► C11 key moments”; commit list item 10
  “dictation dashboard cards + Load-more + favorite + **key moments**”.
- **Evidence:** Key Moments are meeting-overview chrome (images **08, 10**).
  Dictation cards are **02, 07, 09**. Bookmark table in C9 is meeting-scoped
  (`meetingID, startSeconds, …`).
- **Consequence:** Unjustified slice: one commit would wire two products.
  Easy to ship dictation favorites without a player, or moments without C4.
- **Correction:** Split: C11 = dictation library only. Meeting Key Moments
  stay on C9+C4 (or a dedicated meeting-overview slice).

### I10. Two sidebar families not inventoried

- **Section:** §2 shell as one “three-column” composition; Appendix A treats
  01–10 as one dest set plus 04 Live Recording.
- **Evidence:** Family A (**01, 02, 07, 08, 09, 10**): search **in**
  sidebar, Meetings dest, Linear, usage-week. Family B (**04, 05, 06**):
  wordmark, **Live Recording** dest, Search as a **nav row**, Jira, Pro
  Plan GB. Family C (**03**): Settings tabs matching
  `SettingsView.swift:8-22` — **V**.
- **Consequence:** T1 will pick one shell without recording the conflict.
  Live Recording as a **place** vs HUD-as-state is a human door (I3/I4).
- **Correction:** Add the A/B/C contradiction. Canonical shell is a human
  pick. Do not silently default to “sidebar 248 + trailing panel”.

### I11. Permissions health copy vs list (image 03) not flagged

- **Section:** Appendix A 03; §2 “PermissionCenter already exposes every
  state the reference shows”.
- **Evidence:** Image **03** header “**2 of 6** permissions need attention”
  vs three “Not checked” + one “Unknown”. `PermissionState` is
  granted/denied/notDetermined/unchecked (`PermissionCenter.swift:6-10`).
  No `lastScanned` — **V**. `SpeechTranscriber.installedLocales` exists
  (`SpeechModels.swift:22-24`) but is **not** a “models up to date 9:41 AM”
  feature.
- **Consequence:** C13 could paint “2 of 6” as a mock, or claim
  installedLocales as that clock. Health math would be a lie.
- **Correction:** Derive n-of-6 from real states. Do not copy 03’s
  contradictory caption. “Models up to date” stays undecided; at most
  “installed vs not” from `isInstalled`.

### I12. Image 07 still has the live inspector

- **Section:** Appendix A 07 “Same dashboard as 02 **minus live panel
  emphasis**”.
- **Evidence:** Image **07** still shows the right-hand listening inspector
  (waveform, On-device, language/mic, Detected). The delta vs **02** is the
  **main-column live session card**, not the inspector.
- **Consequence:** C12 could be scoped as optional chrome. 07 confirms the
  docked panel while a library is visible.
- **Correction:** 07 = library + inspector, no in-list live card. Prefer
  that over 02’s duplicate card+panel (same conflict Grok T0 recorded).

### I13. Tags JSON-on-meeting chosen in the appendix

- **Section:** Appendix A 10 (“tags: JSON column on meeting (matches
  `actionItemsJSON` precedent) — fold into C10-family migration decision”).
- **Evidence:** No tags today — **V**. JSON blob vs table is a persisted
  contract (Code Quality: one-way-ish). C10 is the **dictation** migration.
- **Consequence:** Silent representation pick, on the wrong slice family.
- **Correction:** Leave tags as an additive-migration door (blob vs table).
  Do not fold meeting tags into dictation v9.

### I14. Playback channel mixing decided in seam 1

- **Section:** §2 seam 1 (“mixing mic+system playback is out of the
  smallest slice — refs' single waveform maps to the system channel or a
  chosen channel per session”).
- **Evidence:** Dual files `audioMicPath` / `audioSystemPath`
  (`Meeting.swift:25-26`). Refs show **one** waveform. No player today.
- **Consequence:** Drops Me or Them from seek-to-line without a human pick.
  “System or chosen” is already a product choice.
- **Correction:** Inventory a single transport. Mixing vs one channel vs
  A/B toggle stays undecided. Player tests should not assume system-only.

### I15. Missing tests beyond G1–G5 (Record publish rate, Reduce Motion, health)

- **Section:** §6 G1–G5 are necessary and should be kept. Gaps:
- **Evidence:** No test that a new peaks/live-stage observer keeps
  `LevelGate` cadence (`LevelGateTests.swift` only tests the gate itself).
  No Reduce Motion assertion except overlay pause wiring
  (`DictationOverlayView.swift:163`). No permission-count honesty test.
  Theme motion/scale already locked (`ThemeTests.swift:7-22`) — GLM never
  cites it for new tokens/fps.
- **Consequence:** C2/C14 can land “green” and still hang Record. New 30
  fps views can ignore Reduce Motion.
- **Correction:** Before C2/C14: a test or profile probe that Record
  MainActor level publishes stay ≤ ~4/s/channel. Before any new
  `TimelineView`: Reduce Motion disables it (same pattern as overlay).
  C13: health n equals non-granted count. Keep G1–G5.

---

## Agreements worth preserving

Do not drop these when reconciling reports.

1. **Capture pipeline freeze.** No writer/coalescing/padding change without
   a Record profile; keep `usesLiveASR` default false
   (`MeetingASRPolicy.swift:13-17`); keep AEC hard-off
   (`RecordingEngine.swift:65-69`). Hang pids 25501 / 62139 stay binding.
2. **Architecture map §1** is largely accurate: scenes, timers, file-ASR
   after Stop, `startLocales` returns one locale
   (`LanguageDetection.swift:46-55`, `LanguageDetectionTests.swift:96`),
   unbounded `fetchSegments` (`AppDatabase.swift:403-413`),
   `folderMeetingCounts` API-only (`APIRouter.swift:129`),
   `deleteMeeting` does not delete audio (`AppState.swift:648-659`),
   prune-2000 (`AppDatabase.swift:258`), overlay panel **472×164**
   (`DictationOverlayController.swift:6`) vs view 440×132 + padding,
   captions panel **656×176** (`CaptionsOverlayController.swift:11`),
   197 `@Test` / 37 `@Suite` in tree (V count; GLM runtime not re-measured).
3. **Six-seam framing** (player, peaks-after-stop, segment windowing,
   dictation metadata, bookmarks, additive enhancement keys) is the right
   *kind* of split — once I1–I5 and I9 are un-decided/un-coupled.
4. **G1–G5** (gap timeline, 10k-segment pagination, v8→v9 upgrade path,
   enhance job-owner/cancel, panel-vs-overlay single mic). Especially G4:
   `enhancingMeetingIDs` is per-meeting only (`AppState.swift:487-494`);
   `LLMRunner.runSync` wait+watchdog, no cooperative cancel
   (`LLMRunner.swift:116-132`) — **V**.
5. **§7 doors listed, not chosen** (local/cloud, OAuth, retention, live AI,
   localization, video, contacts, metering) — keep that discipline. I3, I6,
   I13, I14 are places GLM then chose anyway; put those back on the list.
6. **Do-not-do §8:** no AEC/live-ASR default flip; append-only migrations;
   no new top-level dependency; no `main` commits.
7. **Image 06 as unlabeled Speaker S1/S2** mapped to existing diarization
   names — correct honesty bar vs 01’s named photos.
8. **±15 s** on image **05** (GLM Appendix A 05) — present on that PNG;
   keep in the player inventory.

---

## Silent decisions (do not adopt; do not replace with another pick)

| GLM choice | Where | Why it is a decision |
|---|---|---|
| Tasks = Action Items, no table | App A 01, §3 C7 | Shown as two tabs, two counts |
| Notes/Files out of V2 | App A cross-cut | Shown dests; empty is enough |
| Resume = re-record same folder | App A 08 | Conflicts with 04 Pause |
| Live waveform during Record via C2 | §3 C14 | Hang-class; post-stop peaks suffice |
| 30 fps live stage | §4 | Overlay already 30 fps; T9 ≤24 |
| Accuracy blocked by billing | §7.8 | Different door |
| System-or-chosen playback, no mix | §2.1 | Channel mix is a product door |
| Tags as meeting JSON column | App A 10 | Persisted shape |
| Enhancement `decisions`/`outcomes`/`moments` keys | §2.6 | Additive prompt contract; OK as *proposal*, not as locked JSON |
| Dictation v9 column set (title, languageID, favorite, tagsJSON, waveformPeaksJSON) | §2.4 | Schema; needs human/T2 |

---

## Not issues

- V-prev hang numbers and optimize docs: labelled; not re-measured here.
- Machine `du` of this Mac’s Granipa support dir: session fact, not a
  product metric — fine if not copied into UI.
- `AppIcon.icns` ~1,628 KiB: file size 1,666,207 bytes — **V**.
- Webhook triple `deliverDue` — **V** at `AppState.swift:247, 482, 547`.
- Mic restart cap `< 8` — **V** `RecordingEngine.swift:121`.
- Per-final `database.save(segment)` in file ASR — **V**
  `FileMeetingTranscriber.swift:227`.

---

## Bottom line

GLM’s **current-state map and freeze-the-pipeline stance are keepers**.
The **smallest-V2 graph cannot be executed as written**: it silently
collapses shown IA (Tasks, Notes, Files, Resume), couples **Record-path
waveform** to the live stage at **30 fps**, and overclaims “existing
state” for C14. Fix those before T1; leave one-way doors listed, not
chosen.
