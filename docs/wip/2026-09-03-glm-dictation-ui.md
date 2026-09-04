# Dictation overlay — adversarial UI/UX review (GLM, 2026-09-03)

Scope: `DictationOverlayView`, `DictationOverlayController`, `DictationController`,
`CaptionsOverlayView/Controller`, `Theme`, `MenuBarView`, `ToastController`, `RecordingHUD`.
Judged against the Superwhisper benchmark: hold key → overlay instantly → waveform →
partials → release → processing → paste, without focus theft.

## P0

1. **Fixed panel height clips the content.**
   `DictationOverlayController.swift:13` hardcodes `456×128`, but the view
   (`DictationOverlayView.swift:45-48`: 16pt horizontal + 14pt vertical padding, header row
   ~18pt, spacing 10, waveform 28, spacing 10, up to 3 lines of 15pt text ≈ 54pt) needs
   ~145-160pt. With a 3-line partial or a long failed message the bottom of the text is
   clipped, and the panel never re-sizes later (frame is set once at attach). Superwhisper
   grows/shrinks with content. Fix: size via `host.fittingSize` on each `setVisible(true)`
   (and on preview growth), or use an auto-sizing `NSHostingView`.

2. **Dictation overlay collides with the captions overlay.**
   Captions sit at bottom+28 with height 96 (`CaptionsOverlayController.swift:45-49`);
   dictation sits at bottom+72 with height 128 (`DictationOverlayController.swift:41-47`).
   Overlap band: 72–124pt from the screen bottom. Dictating during a recorded meeting
   (the core use case) stacks two dark rounded rectangles on top of each other. Fix:
   position dictation above captions when captions are visible, or anchor at bottom+150.

## P1

1. **No enter/exit animation — overlay pops in and out.**
   `DictationOverlayController.swift:31-38` uses `orderFrontRegardless`/`orderOut` with no
   opacity transition. Every show/hide is a hard pop, which reads as "glitch" next to the
   0.12s micro-animations inside the view. Superwhisper fades+scales in ~150ms.

2. **Panel is not click-through when it has nothing interactive.**
   Captions panel sets `ignoresMouseEvents = true` (`CaptionsOverlayController.swift:25`);
   dictation does not (`DictationOverlayController.swift:19-28`). During `processing`,
   `done`, and `failed` there is no cancel button (`DictationOverlayView.swift:19` shows it
   only for listening/preparing), yet the 456pt-wide panel still swallows clicks meant for
   the app beneath. Toggle `panel.ignoresMouseEvents` per phase.

3. **Global Esc hijack while overlay is open.**
   `DictationController.swift:247-258` registers Esc with `modifiers: 0` via
   `HotkeyManager` — while dictating, pressing Esc in the *front* app (closing a dialog,
   canceling a cell edit) cancels the dictation instead. Superwhisper scopes Esc to the
   overlay surface. At minimum document the tradeoff; better: also require the overlay
   to be the visible surface.

4. **No Reduce Motion support anywhere.**
   The waveform animates every level push (`DictationOverlayView.swift:61`), the status
   dot pulses a glow shadow (`DictationOverlayView.swift:71`), and `RecordingHUD.swift:88`
   uses `.symbolEffect(.pulse)` — none check `accessibilityReduceMotion`. Reduce Motion
   users get continuous 20Hz animation. Gate the glow and waveform animation on the
   environment value; fall back to a static level meter.

5. **Processing gives no progress affordance beyond a word.**
   `statusTitle` switches to "Processing" (`DictationOverlayView.swift:79`) and the
   waveform dims to 0.35 opacity — but for Muse (network) the wait can be seconds with a
   frozen dimmed waveform. Superwhisper shows a spinner/progress bar. A small
   `ProgressView` or animated ellipsis in the processing phase closes the perceived-latency gap.

## P2

1. **Contrast: placeholder text at 34% white on ultraThinMaterial is below comfortable
   legibility** (`DictationOverlayView.swift:97` with `Theme.textTertiary` 0.34 opacity,
   `Theme.swift:19`). Over a light desktop the material lightens and "Speak — I'll type
   it." nearly disappears. Bump placeholder to `textSecondary` (0.55).

2. **`statusTitle` uses `.contentTransition(.opacity)` but no `.animation(value: phase)`**
   (`DictationOverlayView.swift:16-17`) — the transition never fires; the title swaps
   instantly while the dot next to it animates. Inconsistent micro-motion.

3. **Failed color is hardcoded `.orange`** (`DictationOverlayView.swift:104,112`) while
   everything else uses `Theme.status*`. `Theme` has no `statusFailed`; add one so
   failed state is tunable and consistent with RecordingHUD's orange warnings.

4. **Positioning uses `NSScreen.main`** (`DictationOverlayController.swift:41`), which is
   the screen with the focused window — but on hold-to-talk the *front* app is the target;
   if the user's cursor is on a secondary display the overlay appears on the wrong screen.
   Prefer the screen with the mouse location (`NSEvent.mouseLocation`).

5. **Cancel button hit target is 18×18** (`DictationOverlayView.swift:25-26`), below the
   ~28pt comfortable minimum; also unhoverable feedback is absent (no `HoverHighlight`,
   which exists in `Theme.swift:66-82` and is unused here).

6. **`done` phase hides after only 520ms** (`DictationController.swift:237`) — "Pasted"
   flashes too briefly to register on long dictations; failed gets 1600ms. Consider
   min(700ms, proportional) or until the user types.

7. **Done/failed leave `preview` visible after hide but the panel is reused verbatim next
   attach** — `start()` resets it (`DictationController.swift:76`), fine, but between
   `scheduleHide` firing and the next press the reset happens after `setVisible(true)`
   in the same runloop tick; harmless today, fragile if attach ever gains async work.

## What's already right

- `nonactivatingPanel` + paste via `PasteService` — no focus steal, verified path.
- Overlay shown in `preparing` before mic start (`DictationController.swift:86-88`) —
  instant feedback on press.
- `truncationMode(.head)` + `lineLimit(3)` for partials is the correct Superwhisper-style
  tail behavior (assuming the height bug is fixed).
- Status dot color mapping (`Theme.statusListening/Processing/Done/Loading`) is coherent
  with the rest of the app.

## Three concrete polish patches (no redesign)

1. **Fade in/out + auto-fit height.** In `DictationOverlayController.setVisible`, compute
   `host.fittingSize` (fall back to 456×156), set frame, and animate with
   `NSAnimationContext` (opacity 0→1, ~0.15s) on show; fade out before `orderOut` on hide.
   Touches only `DictationOverlayController.swift`.

2. **Click-through per phase.** Expose `DictationOverlayController.setClickThrough(_:)`
   called from `DictationController` phase transitions: `true` for
   processing/done/failed/idle, `false` for preparing/listening (cancel button needs
   hits). Two small additions in each file.

3. **Reduce Motion + processing affordance in the view.** Read
   `@Environment(\.accessibilityReduceMotion)` in `DictationOverlayView`; when set, drop
   the dot glow and waveform `animation`, showing a 3-bar static level. In `processing`,
   replace the dimmed waveform with a compact `ProgressView().controlSize(.small)` next to
   the "Processing" title. Single-file change.
