# Grañipa V2 — T1a cross-review (GLM)

- **Lane:** `v2-shell-review-glm` · **Branch:** `review/v2-shell-glm` · **Base:** `feat/granipa-v2@5fe7509`
- **Review target:** `feat/v2-shell-grok@4ab925e` (3 commits: ec7f841 tokens/geometry, 0554368
  destinations, 4ab925e inspector/shell). Diff: 17 files, +1243/−111.
- **Date:** 2026-09-04 · **Reviewer model family:** GLM (xhigh). Independent re-review; commit
  messages and prior test claims were not trusted — every claim below was re-verified in this
  worktree this session.
- **Inputs read in full:** `AGENTS.md`, lane `PLAN.md`,
  `docs/wip/2026-09-04-v2-product-contract.md`,
  `git show 629a1b4:docs/wip/2026-09-04-v2-shell-map-glm.md` (the GLM T1 implementation map),
  and the full `git diff 5fe7509...4ab925e`.

Labels: **V** = verified this session in source (`file:line` at 4ab925e). **U** = unverified,
check named. **P** = proposal. Nothing below was assumed from the implementing commits.

---

## VERDICT: ISSUES

Gates pass, all §1.4 preserved behaviors are intact by diff scope and re-inspection, and the
breakpoint/toggle state machine is single-sourced and tested. But there are three medium
findings — one slice-scope pull-forward of T4b inspector content (with an unbounded segment
fetch and a third live timer), and two main-thread hot-path patterns on the new Notes/Files
destinations (synchronous FileManager I/O in a row body; undebounced full-library filtering
per keystroke) — plus four low findings. No blocker: no correctness defect, no schema/engine/
capture change, no dishonest UI was found in the changed code.

---

## 1. Gates (exact output)

| Gate | Result |
|---|---|
| `git diff --check 5fe7509...4ab925e` | clean (no whitespace/conflict markers) |
| `swift build` | `Build complete! (59.55s)` — exit 0 |
| `swift test` | `Test run with 215 tests in 39 suites passed after 0.607 seconds.` — exit 0 |

Test count at base vs head (**V** `git grep -c` both revs): 197 `@Test`/37 `@Suite` at
`5fe7509` → 215/39 at `4ab925e` (+18/+2: `ShellLayoutTests` 5, `ShellNavigationTests` 12,
`ThemeTests` +1). No existing test was weakened or deleted (**V** diff touches
`ThemeTests.swift` additively only).

---

## 2. Verified findings

### F1 — Medium (slice scope + unbounded load + duplicate live surface): meeting inspector ships T4b content inside T1a

**Where:** `Sources/Granipa/UI/InspectorViews.swift:43-145` (`MeetingInspectorView`),
`:102-118` (`durationBlock`), `:133-145` (`loadSpeakers`); mounted via
`AppNavigation.swift:75-90` (`inspectorKind` returns `.meeting` whenever
`hasSelectedMeeting`, at any width).

**Verified evidence:**
- The contract assigns inspector *details* content to **T4b** (§5.4: "T4b Overview from
  existing summary/actions + inspector details"); T1's DoD only requires column/collapse
  mechanics and destinations. The GLM T1 map resolved exactly this tension (§4.6): the T1
  inspector occupant is the *dictation* session panel, read-only, and "Alternative: ship the
  mechanism hidden everywhere". The implementation silently shipped the meeting occupant
  instead — no PR/commit records the director decision the map flagged as required.
- `loadSpeakers()` calls `db.fetchSegments(meetingID:)` (`InspectorViews.swift:137`) —
  **V** `AppDatabase.swift:403-413`: no LIMIT, all columns. Every meeting selection
  materializes the *entire* transcript (G2's 10k-segment fixture = 10k rows with full text)
  off-main, transiently, only to compute distinct speaker names. Off the main thread
  (detached, `.task(id:)` cancels correctly — **V** `:133-145`), once per selection — so not
  a loop, but it is the "segment fetch … loads unbounded data" pattern, built on the exact
  fetch (P3) the contract says pagination must replace.
- `durationBlock` mounts a live `RecordingTimer` while `status == .recording`
  (**V** `InspectorViews.swift:103-112`). During a recording with the meeting selected at
  ≥1280 there are now **three** ticking 1 Hz `TimelineView` clocks: HUD
  (`RecordingHUD.swift:69` compact / `:118` expanded), detail header (`RecordingBar.swift:18`),
  and the inspector. Contract §3.3 allows the inspector to show *live transcript only* during
  Record — not another timer.

**Impact:** review surface for T4b lands unreviewed in T1a; worst-case transient memory and
query time grow with transcript length; one more always-ticking surface while recording.

**Smallest repair:** make `AppNavigation.inspectorKind` return `.none` when
`hasSelectedMeeting` (delete the `.meeting` case, `MeetingInspectorView`, and `loadSpeakers`
from this slice) — the column mechanics, breakpoints and toggle stay fully exercised by the
dictation occupant, exactly as the map scoped T1. If the director wants to keep it: replace
the segment fetch with a `SELECT DISTINCT speaker` query and delete the live `RecordingTimer`
from `durationBlock` (static duration only), and record the decision in the PR.

### F2 — Medium (hot path): synchronous FileManager I/O inside a SwiftUI row body

**Where:** `Sources/Granipa/UI/FilesLibraryView.swift:95,98` →
`AppNavigation.swift:162-171` (`fileLabel`) → `:148-160` (`fileStatus`:
`FileManager.default.fileExists` + `attributesOfItem`).

**Verified evidence:** `FilesLibraryRow.body` renders `Text(MeetingLibrary.fileLabel(...))`
per audio path (up to 2 per row). `shown` (`FilesLibraryView.swift:6-11`) recomputes on every
`app.searchQuery` keystroke, so each keystroke re-diffs the `ForEach`, re-rendering visible
rows and re-stat-ing their files on the **main thread**; each newly materialized row during
scroll does the same. This is repeated synchronous file-metadata lookup from a SwiftUI body —
the exact pattern this review was asked to hunt.

**Impact:** main-thread disk I/O per keystroke/scroll proportional to visible rows (≈2 stat
calls × rows). Individually microseconds; on slow disks/first-stats after unmount it is
visible jank, and it is new T1 work on the typing path (contract §6.1 budgets; T1 DoD "idle
CPU not worse"). Contract §3.8 *allows* listing sizes "if cheap" — the defect is doing it in
`body`, not doing it.

**Smallest repair:** resolve status once per path instead of per render — e.g. a
`[String: RecordingFileStatus]` dictionary built in a `.task`/`onChange(of: app.meetings)`
step (or `@State` per row filled in `.task`) and read by the row body. `fileStatus` already
returns an enum, so the cache is a trivial wrapper.

### F3 — Medium (hot path): Notes/Files search filters the full library synchronously per keystroke, with no debounce

**Where:** `Sources/Granipa/UI/NotesLibraryView.swift:6-11` and
`FilesLibraryView.swift:6-11` (`shown` → `MeetingLibrary.matching` + `dayGroups` in body);
`AppNavigation.swift:120-136` (contains over `title` + `notesMarkdown`; grouping + sort).

**Verified evidence:** both destinations observe `app.searchQuery`, so `body` re-evaluates on
every keystroke and re-runs, on the main thread: the notes/recordings predicate,
`localizedCaseInsensitiveContains` over every meeting's title **and full
`notesMarkdown`**, plus `dayGroups` (dictionary grouping + two sorts). The source list is
`app.meetings`, and **V** `AppDatabase.swift:362-366`: `fetchMeetings()` has **no LIMIT** —
the in-memory library is unbounded. Contrast the preserved path: Home/Meetings search is
200 ms debounced, cancelled on change, and executed as detached SQL
(**V** `HomeView.swift:79-95`).

**Impact:** per-keystroke main-thread cost that scales with total meetings × notes size;
typing latency on the two new destinations; diverges from the established search pattern and
from contract §3.1's debounce rule for search-in-flight.

**Smallest repair:** route Notes/Files through the same debounce + detached pattern HomeView
uses (extract the existing `HomeView.swift:79-95` logic into a small shared helper or
replicate it in the two views), filtering `app.meetings` off-main and storing results in
`@State`.

### F4 — Low-medium (slice scope): dictation inspector pulls T2a chrome forward (waveform, engine chip, shield line)

**Where:** `Sources/Granipa/UI/InspectorViews.swift:147-224` (`DictationInspectorView`),
`:168` + `:226-245` (`InspectorWaveform`), `:203-205` ("Entries persist locally" shield).

**Verified evidence:** the GLM map's T1 inspector spec says "No waveform, no mic/language
pickers, no second capture" (§4.6) and lists "live waveform" under T2a exclusions (§9).
The implementation adds a live waveform. Mitigations verified in source, so the contract's
resource rules are *not* broken: it is a plain `Canvas`, not a `TimelineView` (G7 does not
trigger), it reuses the same `dictation.waveform` sample array (republished by the existing
`LevelGate(0.08)` ≈ 12.5 Hz — no new capture, no new observer), and the overlay remains the
only 30 fps `TimelineView`. The Retry action and status strings ("Needs attention",
"Pasted", "Speak — press again to finish", engine label) are reused verbatim from
`DictationOverlayView.swift:90-125` — nothing invented. Phases `idle`/`done` correctly keep
the inspector hidden (`AppNavigation.swift:68-74`).

**Impact:** scope drift into T2a without a recorded decision; a second live dictation render
surface (overlay Canvas + inspector Canvas) that T2a will need to re-review; trivial CPU.

**Smallest repair:** drop `InspectorWaveform` (and optionally the shield line) from this
slice, or record the director's acceptance of the waveform in the PR description before
merge.

### F5 — Low (fidelity): Dictation is the only destination without a serif page title

**Where:** `Dictation/DictationHistoryView.swift` — untouched by the diff (stats bar remains
the first element); every other destination renders `DestinationHeader(title:)`
(`DestinationHeader.swift:3`, mounted in `HomeView.swift:48`, `NotesLibraryView.swift:16`,
`FilesLibraryView.swift:14`).

**Impact:** inconsistent shell chrome; contract §2.3 keeps serif titles for "Home /
Dictation / Permissions / Onboarding"; the map planned the Dictation page title. Cosmetic,
no behavior risk.

**Smallest repair:** one-line follow-up in T2a (which owns `DictationHistoryView`): mount
`DestinationHeader(title: "Dictation")` above the stats bar.

### F6 — Low (DoD evidence): no runtime/visual proof, and the inspector toggle's visibility is unverified

**Where:** `MainWindow.swift:79-91` — the app's first and only `.toolbar` usage, inside a
`.hiddenTitleBar` window (`GranipaApp.swift:32`).

**Verified evidence:** none of the map's proof artifacts exist in the diff: no fixture mode
(`--v2-fixture` — **V** zero hits in Sources), no screenshot matrix, no idle-CPU
before/after. The toolbar button is the *only* way to reveal the overlay inspector at
960–1279 and to hide the column at ≥1280 (`inspectorOverride` has one writer,
`MainWindow.swift:82`). Whether `.toolbar` content renders in a `.hiddenTitleBar` window on
this OS build is **U** — I did not launch the app (it opens the real
`granipa.sqlite`, registers global hotkeys, and triggers TCC; that is the implementer's
fixture-mode job, not a read-only review's). If it does not render, the T1 DoD line
"1120 shows inspector collapsed + toolbar toggle" fails outright.

**Impact:** T1's DoD is only partially evidenced (code + unit tests yes; interactive/visual
and CPU-parity no).

**Smallest repair:** in the implementing lane, produce the map §5 matrix (at 1120, 1280,
1440) plus the 60 s `top` idle comparison; if the toolbar button is invisible under
`.hiddenTitleBar`, render the toggle as an in-content trailing button (as
`DestinationHeader` does) instead of `.toolbar`.

### F7 — Low (consistency): the same search field has different semantics per destination

**Where:** Home/Meetings search = SQL over title, notesMarkdown, enhancedNotesMarkdown,
summary, **and transcript text** (`AppDatabase.swift:372-393`); Notes/Files search =
in-memory title + notesMarkdown only (`AppNavigation.swift:120-127`).

**Impact:** a phrase that appears only in the transcript finds the meeting from Home/Meetings
but not from Notes/Files. Not dishonest (both return real matches), but surprising.

**Smallest repair:** reuse the SQL `searchMeetings` path for Notes/Files (fold F3's repair
and this into one change), or document the per-destination scope in the PR until T5.

---

## 3. Proposals (not defects)

- **P1** `NotesLibraryRow` (`NotesLibraryView.swift:64-101`) and `FilesLibraryRow`
  (`FilesLibraryView.swift:71-112`) each duplicate ~50 lines of `HomeMeetingRow`'s card
  anatomy (avatar/HStack/paddings/card/border/hover). Three similar rows is under the
  abstraction bar; if T2/T7 add a fourth, extract a row-shell then.
- **P2** `MainWindow.swift:151-152`: the `.dictation` case of the content switch is
  unreachable (the `:133` branch already catches it). Harmless symmetry; drop or keep.
- **P3** The inspector waveform paints `Theme.accent` orange (`InspectorViews.swift:243`);
  contract §2.2 scopes `brandPurple`/`brandPink` to the dictation waveform. Decide the
  inspector waveform's color with T2a, not implicitly here.
- **P4** `AppNavigation.inspectorKind` gates dictation on `windowWidth` while
  `ShellLayout.presentation` gates it again (`AppNavigation.swift:80` /
  `ShellLayout.swift:35-39`). Same constant, no divergence — but the width decision could
  live only in `presentation`.
- **P5** The narrow-width overlay inspector has no click-outside-to-dismiss (the map §4.2
  mentioned it; the contract does not require it). UX nicety for a later slice.

**Pre-existing, unchanged by this diff (recorded, not charged to T1a):**
`MenuBarView.swift:59-62` "New Meeting" and recording starts set `selectedMeetingID` while a
Dictation destination is active — the router prioritizes `DictationHistoryView`
(`MainWindow.swift:133`), so the new meeting is not shown. The old `showsDictationHistory`
router had the identical priority; the enum migration did not regress it.
`createFolder` now also clears `searchQuery` (`AppState.swift:574` via `revealFolder`) — a
benign delta from the old code (which kept the query); arguably a fix.

---

## 4. Explicit investigation checklist (as tasked)

| Question | Answer (V unless noted) |
|---|---|
| Folder count / date grouping / search / file metadata / segment fetch repeated synchronously from a body, or unbounded loads? | **Yes — three instances.** Folder counts + day groups recompute per render (SidebarView.swift:18-20; cheap in-memory, matches SQL semantics, acceptable). File stats in row body (F2, medium). Undebounced in-memory search per keystroke (F3, medium). Unbounded segment fetch per selection, off-main (F1, medium). `fetchMeetings` itself has no LIMIT — pre-existing, now reachable from two more surfaces. |
| Inspector state, breakpoints, toolbar control at 1120/1279/1280/1440; duplicate state or duplicate live surfaces? | Breakpoint logic single-sourced in `ShellLayout.presentation` + `inspectorKind` and covered at all four widths by `ShellLayoutTests`/`ShellNavigationTests`; `inspectorOverride` is the only user state; `windowWidth` the only width state — no duplicate state. 1120/1279 → hidden + toggle (meeting content) → overlay 300 pt; 1280/1440 → column 300 pt; dictation docks only wide + live (contract §2.6). **Duplicate live surfaces: yes** — third `RecordingTimer` while recording (F1); inspector waveform alongside overlay is contract-decided (§2.9) and sample-shared. Toolbar button rendering itself is U (F6). |
| Meeting/dictation inspector content belongs in T1a or silently pulls T2/T4 forward (waveform, retry)? | **Both occupants exceed the map's T1 scope.** Meeting details/participants/duration = T4b (F1). Waveform/engine chip/shield = T2a (F4). Retry is *not* a violation — the map explicitly allowed it reusing overlay strings, which it does (`InspectorViews.swift:196-200` ≡ `DictationOverlayView.swift:90-98`). |
| Hidden `keyboardShortcut` button reliably focuses search; did the enum migration cover every prior bool caller? | ⌘K implemented as a zero-frame, opacity-0, a11y-hidden button behind the search field (SidebarView.swift:184-190) setting the `FocusState` bound at `:159` — the standard working pattern; runtime firing is **U** (needs the interactive proof of F6; no conflicting ⌘K exists — only ⌥⇧ menu items, `MenuBarView.swift:65-80`). Migration complete: zero `showsDictationHistory` remain (grep, Sources+Tests); all nine map §1.2 sites have enum equivalents (`reveal`/`revealFolder`/router/highlight); `deleteFolder` falls back to Meetings sensibly. |
| Notes/Files classifications honest for current model states; sync disk I/O or invented semantics? | Predicates honest and contract-shaped (§3.7/§3.8): Notes = non-empty `notesMarkdown` ∪ quick-notes (no audio, not recording — `AppNavigation.swift:93-100`, with the `status != .recording` guard exactly protecting in-flight meetings whose paths aren't set yet); Files = audio-path meetings ∪ live sessions (`:102-108`); "Empty note"/"Audio file missing" previews are truthful. No invented semantics. Disk I/O: yes, sync in body (F2). |
| Glow/animation paths respect Reduce Motion and stay lightweight? | `recordGlow()` is a *static* shadow (Theme.swift:118-120) on five Record buttons — no pulse anywhere in the diff. Inspector transitions are `.opacity` only; both new `.animation` sites nil under Reduce Motion (MainWindow.swift:66-68, 157-159), mirroring the preserved banner pattern. No new `TimelineView` exists except the reused 1 Hz `RecordingTimer` (F1) — G7's pause rule is not violated by any new animated surface. |
| New tests protect observable behavior or merely freeze implementation? | Mostly genuine: `ShellNavigationTests` exercises the highlight/folder-priority/inspector-gating/predicate/duration/file-status contracts (including a real FS round-trip); `ThemeTests.darkTokensMatchTheV2Contract` pins contract-normative hex values. `ShellLayoutTests` pins the six geometry constants — that is freezing *contract* numbers, which is their purpose (T1 DoD cites them). Not covered (acceptably, per map: no UI-test infra, AppState opens the real DB): ⌘K focus at runtime, `reveal` state-clearing, folder-count wiring. |
| New components/helpers duplicate existing source or single-use abstractions heavier than T1 needs? | `EmptyStateView` (3 consumers), `DestinationHeader` (3), `InspectorSection` (2), `AppNavigation`/`ShellLayout`/`MeetingLibrary` (pure, tested) — all multi-use or pure seams. `InspectorWaveform` is single-use but 20 lines private. Row duplication vs `HomeMeetingRow` is P1. Net: no heavyweight single-use abstraction. |

---

## 5. T1a acceptance table (contract §8 T1 DoD, restricted to T1a)

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | ≥1280: sidebar 248 + content + inspector 300 | Pass (code) | MainWindow.swift:35-53, ShellLayout.swift:14-21; ShellLayoutTests |
| 2 | 1120 (and 1279): inspector collapsed + toolbar toggle | Pass (code) / **U** toggle rendering | ShellLayoutTests (1120, 1279); toggle MainWindow.swift:79-91 — see F6; toggle appears only when inspector content exists |
| 3 | Breakpoints 1280/1440 column; dictation docks wide+live only | Pass | ShellNavigationTests (1280/1440, dictation width gates) |
| 4 | Reduce Motion: no slide, no pulse; overlay TimelineView paused | Pass | MainWindow.swift:66-68/157-159; `.opacity` transitions; no pulse added; overlay untouched (DictationOverlayView.swift:161-164) |
| 5 | Dark tokens match §2.2 | Pass | Theme.swift:14-27; ThemeTests.darkTokensMatchTheV2Contract |
| 6 | Dests Home/Dictation/Meetings/Notes/Files with honest empties | Pass | AppNavigation.swift:4-29; MainWindow.swift:132-154; empty states re-use honest copy; F5 notes Dictation's missing title |
| 7 | Folder counts match SQL | Pass | In-memory derivation over the same universe as `fetchMeetings` (AppNavigation.swift:110-118 vs AppDatabase.swift:284-295); FolderTests still covers the SQL |
| 8 | ⌘K focuses search | Pass (code) / **U** runtime | SidebarView.swift:184-190 + FocusState :159 |
| 9 | Settings scene unchanged | Pass | Diff touches no Settings code |
| 10 | HUD/overlay/captions/clipboard/battery/dictation still work | Pass | Diff scope excludes Audio/, Dictation/ engine, System/, RecordingHUD, CaptionsOverlay*, PasteService, BatteryService; Right Command/Right Option path intact (SettingsView.swift:293-320, HotkeyBindingTests green) |
| 11 | `swift test` green | Pass | 215/39, exit 0 |
| 12 | Idle CPU not worse than pre-T1 (`top` 60 s) | **Not evidenced** | No measurement exists — see F6 |

---

## 6. Behavior-preservation spot checks (§1.4, re-verified in current source)

Right Option default + Right Command binding intact (`SettingsView.swift:293-316`,
`AppState.swift:97-115`); clipboard paste path untouched (`PasteService`, no diff);
Recording/Stop-only engine untouched (`RecordingEngine` — no diff); HUD window + captions
mount unchanged (`GranipaApp.swift:50-58`, `MainWindow.swift:92-104`); battery
stop-on-quit unchanged (`GranipaApp.swift:13-15`); export/copy transcript context menu
intact (`HomeView.swift:263-273`); email draft untouched (`EnhancedNotesView` — no diff);
folder navigation including rename/delete/create flows intact
(`SidebarView.swift:65-92,125-146`, `AppState.swift:568-603`); meeting selection + back
button preserved, now with the contract's "Back to Home"/"Back" a11y label
(`MeetingDetailView.swift:69-81`); detection banner + Record-from-detection intact
(`MainWindow.swift:125-131,164-189`). `os_signpost("appReady")` added per contract §6.1
(`GranipaApp.swift:8-11`).

---

## 7. Verdict rationale

- **Not OK:** F1–F3 are concrete: T4b content merged into T1a against the reviewed plan, an
  unbounded fetch reachable from the new shell, main-thread disk I/O in row bodies, and
  per-keystroke undebounced filtering — each with a one-file smallest repair. F6 leaves two
  DoD rows (toggle visibility, CPU parity) without evidence.
- **Not BLOCK:** all three gates exit 0; no changed line breaks preserved behavior; the
  breakpoint state machine is correct, single-sourced and tested; no dishonest/fictional UI
  was painted; no schema, engine, capture, dependency, or external-contract change is present
  in the diff.

**Recommended merge condition (for the director):** fix F2 + F3 (hot paths) and decide F1/F4
(scope: drop or record sign-off) in the implementing lane; attach the F6 proof artifacts
before calling T1 done.

---

*End of review. Deliverable of this lane: this file only. No Swift, test, schema, or durable
doc was modified.*
