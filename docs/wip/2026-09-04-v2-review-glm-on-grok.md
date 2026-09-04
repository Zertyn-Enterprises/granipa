VERDICT: ISSUES

# GLM review of Grok's V2 T0 audit — 2026-09-04

- Reviewed file: `docs/wip/2026-09-04-v2-audit-grok.md` at `3789b96` (branch
  `docs/v2-audit-grok`, base `feat/granipa-v2@c7704c3`).
- Reviewer lane: `v2-audit-glm` (prior audit:
  `docs/wip/2026-09-04-v2-audit-glm.md` at `8cb7ac1`).
- Method: read Grok's report in full via `git show`; re-verified every
  checkable code claim against the worktree at `c7704c3` and re-inspected
  the four disputed image details (06, 08, 09, plus 03's health math)
  with the image tool this session.
- Labels: **V** = verified this session against source/image;
  **V-prev** = verified in lineage docs; **U** = inference.

## Verification summary

Grok's report is overwhelmingly accurate. Checked and confirmed (V):

- **Absence greps**: no `NavigationSplitView`/`inspector`, no
  `AVPlayer`/`AVAudioPlayer`, no engine `pause`, no ⌘K binding — all
  reproduce exactly.
- **Theme tokens** (`Theme.swift:14-32`): every hex and opacity Grok lists
  is exact (`bg 0x161412`, `accent 0xF05423`, `channelMe 0x6FA8DC`, all
  five status colors, text 92/55/34%, border 7%, strokeStrong 12%,
  fillSubtle 8%, fillHover 4%, brandPurple/brandPink).
- **Geometry**: main min 960×600 (`MainWindow.swift:55`), sidebar 248
  (`MainWindow.swift:21`), Settings 640×600 (`SettingsView.swift:24`),
  dictation overlay 440×132 (`DictationOverlayView.swift:30`), HUD 520
  (`RecordingHUD.swift:175`), captions card 640
  (`CaptionsOverlayView.swift:40`).
- **Settings claim**: the seven top-level tabs at `SettingsView.swift:8-22`
  (General, Dictation, Shortcuts, Permissions, AI, Extras, Integrations)
  do match 03's sidebar exactly.
- **Behavior claims**: `RecordingTimer` is 1 Hz periodic and `m:ss`
  (`RecordingSharedViews.swift:48,54-56`); action items render in Enhanced
  (`EnhancedNotesView.swift:72-81`); email draft `:84-109`; "Enhance
  now"/"Re-enhance" already exist (`:43`, `:131-141`); the prompt stuffs
  due dates into action-item text (`EnhancementService.swift:84-87` —
  "with the due date in the text when one was mentioned");
  `FolderDTO.meetingCount` exists for the API only
  (`APIRouter.swift:70-75`, used at `:129`; sidebar shows no counts);
  menu-bar shortcuts are ⌥⇧ (`MenuBarView.swift:68-83`); onboarding serif
  title and "no accounts, no telemetry" (`OnboardingView.swift:40,47`);
  time-saved is 40-WPM typing math with a test pinning it
  (`DictationEntry.swift:38-40`, `DictationHistoryTests.swift:18-22`);
  `ThemeTests` locks motion `7-13`, scale incl. `waveformBars == 40` at
  `:23`, sparkline 52 samples; exporter/copy-transcript
  (`MeetingExporter.swift:54-76`); API/webhook settings ranges
  (`SettingsView.swift:955-1030`); permissions rows and the
  probe-creates-a-real-tap warning (`PermissionCenter.swift:52-70`);
  `PanelMotion` 0.34/0.20/40 (`PanelMotion.swift:6-9`).
- **Image claims re-verified this session**: all ten PNGs are 1448×1086;
  06 has pause icon `07:42`/`32:17`, a volume icon (only transcript frame
  with one), and right panel Meeting insights / Highlights / Tools
  (Search in transcript, Create highlight reel, Export transcript) /
  Speakers stacked bar S1 68% · S2 22% · S3 10%; 08 shows **three**
  numbered waveform markers 1/2/3 (third near the right edge — my own
  first pass undercounted at two; Grok is right); 09 shows type tabs
  All/Dictations/Notes/Imports, "Newest first ▾", list↔grid toggle, an
  in-row mini waveform, and an orange accuracy ring (vs 07's green);
  03's health copy says "2 of 6 need attention" while its own list shows
  three Not-checked + one Unknown — the internal contradiction is real.
- **"T7"/"T9" references** are valid: the director's plan
  `.claude/plans/granipa-v2.md` defines numbered tasks 0–10 (T7 =
  collections/notes/files/tags, T9 = performance/polish). Not fabricated.

Given that base accuracy, the issues below are corrections, not
rejections.

## Issues

### I1 — Decides and defers the same dictation-live question (§2 contradiction 6, §6 Dictation, §7 Unresolved #9)

- **Evidence (V, Grok's own text)**: §2 canonical rule: "Pick inspector +
  overlay; drop the duplicate card". §6 Dictation: "keep **overlay** …
  **also** show the inspector transcript (02/07/09) bound to
  `DictationController` — same session, not a second mic." §7 Unresolved
  #9: "Whether the floating dictation overlay remains once an inspector
  exists."
- **Consequence**: T2 (dictation library/session) receives both a settled
  contract (ship both surfaces) and an open question for the identical
  surface. Whichever choice an implementer makes can be argued wrong from
  the same document.
- **Correction**: remove #9 from Unresolved and keep the §2/§6 decision
  (overlay + inspector on one `DictationController` session — it is sound
  and matches the code's single-capture invariant), or downgrade §2/§6 to
  "proposed pending #9". One of the two, stated once.

### I2 — "Additive GRDB only if any of 3, 5, 8, 9, 10 ship" contradicts the report's own inventory (§ One-way doors, closing line)

- **Evidence (V)**: Grok's own tables mark as **new with schema needs**:
  bookmarks/highlights ("no columns on `transcriptSegment`", §4.4),
  chapter model ("no chapter model", §4.4), dictation title/tags/star
  ("would need additive columns; tags/favorites are one-way-ish persisted
  shape", §4.2), Key Moments, and the "Generated 2m ago" timestamp
  ("not stored today — would be additive", §7-10 table). None of these
  map to doors 3/5/8/9/10 (retention-audio, participants, pause,
  tasks-vs-actions, accounts).
- **Consequence**: a T1–T7 planner reading only the one-way section
  concludes the bookmark/chapter/tag/moment work is schema-free. It is
  not; each needs an append-only migration plus tests, and tags/star are
  persisted-shape decisions that deserve door status.
- **Correction**: rewrite the line as: additive GRDB is also required for
  bookmarks/highlights, chapters, dictation metadata (title/tags/star/
  peaks), key moments, and the summary timestamp — each its own
  append-only migration; add tags/favorites to the door list.

### I3 — Unmeasured state phrased as fact: "30 fps already over budget" (§5.3)

- **Evidence (V-prev)**: the lineage audit explicitly labels the 30 fps
  Canvas cost as inference: "CPU cost is Inferencia, confirmar with
  Instruments" (`docs/wip/2026-09-04-optimize-audit.md`, DictationOverlay
  entry). No Instruments profile exists. Grok's own §5.5 then *defines*
  the dictation budget as "one 24 fps canvas" — i.e., 24 fps is the new
  proposal, not evidence against 30.
- **Consequence**: T9 may "fix" a regression that was never measured, or
  lower frame rate without the profile the audit trail requires — the
  exact pattern (confident cuts that didn't move CPU) the hang-handoff
  warns about.
- **Correction**: restate as "proposal: cap render at ≤ 24 fps; the 30 fps
  cost is unmeasured — profile with Instruments before changing; Reduce
  Motion already pauses the TimelineView
  (`DictationOverlayView.swift:163-164`)."

### I4 — Cited files that do not exist / lines that do not hold the token (§3.1, §3.2, §5.1)

- **Evidence (V)**:
  - §3.1 cites `SegmentRow.swift:335` — there is no `SegmentRow.swift`;
    `SegmentRow` is declared in `MeetingDetailView.swift` (channelMe read
    at `:334-335`).
  - §3.1 cites `AvatarView.swift:109-131` — there is no `AvatarView.swift`;
    `AvatarView` is defined in `Theme.swift:109-132`.
  - §5.1 cites `Theme.motionFast … Theme.swift:41` and `motionNormal …
    Theme.swift:42` — those lines hold `radiusS`/`radiusM`; the motion
    tokens are at `Theme.swift:50-51` (values 0.08/0.15 are correct).
  - §3.2 cites `titleFont` at `Theme.swift:35` and `meetingTitleFont` at
    `:36` — actual lines are `:34` and `:35` (34 semibold serif / 28 bold
    are correct).
- **Consequence**: small, but this document's entire value proposition is
  precise traceability; filename-greps fail and line-anchored diffs
  mis-land. (Note: `ThemeTests.swift:7-13` motion citations in the same
  table are correct.)
- **Correction**: `MeetingDetailView.swift:334-335`, `Theme.swift:109-132`,
  `Theme.swift:50-51`, `Theme.swift:34-35`.

### I5 — Wrong shortcut in the component table (§4.3)

- **Evidence (V, image 04)**: the transport cluster shows Mark action
  **⌘⇧M**; Grok's own §1-04 component list says `⌘⇧M`, but the §4.3 table
  row reads "Mark moment `⌘B` / Mark action `⌘M`".
- **Consequence**: a shortcuts slice binding ⌘M collides with nothing
  today but diverges from the reference and from Grok's own inventory.
- **Correction**: `⌘⇧M` in §4.3.

### I6 — "Ultra-lightweight budgets" omit memory, DB-write rate, and startup; lifecycle section omits the two verified 🔴 runtime risks (§5)

- **Evidence (V / V-prev)**: §5 covers motion, FPS, level gating, and list
  hygiene only. Missing, all established in the lineage and in the GLM
  audit: (a) the unbounded session writer queue with per-buffer
  `deepCopy` (`RecordingSession.swift:270-294`; optimize-audit 🔴
  persisted-media), (b) Swift task cancellation does not terminate LLM
  CLI subprocesses — only the 600 s watchdog does (`LLMRunner.swift:116-121`),
  while the report itself adds Regenerate/Re-enhance surfaces and
  contemplates live AI, (c) one GRDB commit per final segment during live
  ASR (`TranscriptionCoordinator.applyDecided`), which matters the day
  T2/T3 ship, (d) no memory or startup budget at all.
- **Consequence**: T1–T9 inherit visual guardrails but none for the
  failure class that actually produced the Record hang and the XPC trap —
  the risks migrate into V2 silently.
- **Correction**: import (or reference) the GLM audit's budget table and
  guards G1–G5 into §5/§6, minimally items (a)–(c) with their source
  lines, and require the job-owner guard before any new AI trigger.

### I7 — Captions geometry states the card, not the resident panel (§3.5)

- **Evidence (V)**: `CaptionsOverlayView.swift:40` is the content card's
  `.frame(width: 640)`; the always-resident `NSPanel` bounding box is
  656×176 (`CaptionsOverlayController.swift:11`, deliberately fixed to
  avoid fittingSize passes).
- **Consequence**: minor — screen-space reasoning and any resize work
  targets the wrong number.
- **Correction**: "captions panel 656 (fixed bounding box), card 640."

## Agreements worth preserving (V unless noted)

1. **03's health-math contradiction** ("2 of 6" vs four non-granted rows)
   — real, and treating mock copy as non-normative is the right call.
2. **The honest-mock posture**: no Accuracy tile, no usage/upgrade,
   no fake participants, "do not paint ⌘F chrome that no-ops", empty
   states must be real. This is the strongest part of the report.
3. **06 as the transcript honesty bar** (disfluent ASR text, generic
   Speaker S1/S2 until renamed) — matches `SpeakerMapping` output shapes.
4. **Keep the floating HUD and "Transcript after you stop"** even if a
   live stage ships; keep the Email draft (in code, absent from refs).
5. **Single capture invariant**: an inspector must bind to the same
   `DictationController`, never a second mic — matches
   `beginCapture`'s `micBusy` guard.
6. **Absence greps as the preflight** (no player, no pause, no inspector
   column, no ⌘K) — all reproduced.
7. **Light tokens labeled unverified inference**; dark-only until a light
   frame exists.
8. **The A/R/P/H/E verdict appendix** — auditable and consistent with the
   one-way list (subject to I2).
9. **Convergence with the GLM audit's seams**: playback layer, waveform
   peaks (post-stop precompute + gated live RMS — compatible with GLM's
   capture-time peaks as a second consumer of the same RMS values),
   transcript pagination/search, bookmarks/moments, additive enhancement
   keys, permissions as composition. The two audits do not conflict on
   architecture.
10. **Rescan must not probe in a loop** (system-audio probe creates a real
    tap, `PermissionCenter.swift:52-55`).

## Verdict rationale

No fabricated data, no invented platform APIs, no wrong architecture
facts, and no silent one-way product choice beyond the flagged I1/I2
consistency gaps. But I1 (contradictory decision state), I2 (false
schema-free claim), I3 (unmeasured claim as fact), and I6 (missing the
known 🔴 runtime guardrails) are real defects that would mislead T1 if
consumed uncritically — hence **ISSUES**, with all corrections local and
cheap to apply.
