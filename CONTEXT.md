# CONTEXT — Grañipa

Product state. Rules live in `AGENTS.md` (`CLAUDE.md` is a symlink to it).

## What it is

Native macOS 26+ (Apple Silicon) meeting recorder and notes app. No bot joins
the call. Mic + system audio, on-device live transcription, speaker diarization,
AI-enhanced notes via the user's existing CLI subscriptions (claude / codex /
gemini / grok — no API keys). Also: hold-to-talk dictation, clipboard history,
OCR, window snapping and app-window grid tiling.

Local by default. Optional cloud: Muse (system-channel ASR only), dictation
text rewrite (SpaceXAI or a custom OpenAI-compatible URL).

Bundle id `com.zertyn.granipa`. Data:
`~/Library/Application Support/Granipa/`.

## Stack

Swift 6 · SwiftUI · SwiftPM (no Xcode project) · GRDB · FluidAudio 0.15.2 ·
Sparkle 2.7+ · executable `Granipa` plus the no-op stub `GranipaBatteryHelper`.
Bundled by `Scripts/bundle.sh` into `build/Grañipa.app`.

## Where it lives

- Checkout: `~/Dev/02_hq/granipa` (default branch `main`).
- V2 worktree: `.claude/worktrees/granipa-v2` on `feat/granipa-v2`.
- GitHub: `Zertyn-Enterprises/granipa` (public).
- Sparkle feed: `https://github.com/Zertyn-Enterprises/granipa/releases/latest/download/appcast.xml`.

## Current state (2026-09-19)

Verified this session against git, GitHub, `Info.plist`, and source.

| Surface | What is actually there |
|---|---|
| `main` / `origin/main` | `bd05f9d` — v1.0.4 (2026-06-19). This is what `git clone` and the GitHub homepage show. |
| `feat/granipa-v2` | `5505ee3`, **already pushed**. 145 commits ahead of `main`. Source version **2.0.1**, Sparkle build **8**. |
| GitHub Release Latest | **v2.0.0** (build 6), published 2026-09-06. Zip + `appcast.xml`. Tag `v2.0.0` = `337d0f4`, not the branch tip. |
| PR V2 → `main` | [#27](https://github.com/Zertyn-Enterprises/granipa/pull/27) open (hold). Do not merge from an agent. |
| PR #25 | `chore/optimize-2026-09-04` → `main`. Open. That commit **is** an ancestor of `feat/granipa-v2`. |
| PR #26 | `perf/post-recording-cpu` → `feat/granipa-v2`. Open, **not** in the V2 tip. |

V2 UI that ships on `feat/granipa-v2`: sidebar is Home + Dictation. Home
filters All / Notes / Recordings. Settings sections: General, Dictation,
Shortcuts, Permissions, AI, Extras, Integrations. In-app Settings (not a
separate window). FluidAudio is linked. Dictation history is migration `v8`.

`docs/home.png` is still the 2026-06-11 v1 screenshot.

### Why GitHub looks like nothing landed

The updates **were pushed**. They were not merged to the default branch.

- Lane merge policy was `hold` (human merges). T10 said open one PR, do not merge.
- The 2.0.0 GitHub Release was published from the tag without merging that tag into `main`. Sparkle users can already get 2.0.0; a fresh clone cannot.
- Later 2.0.1 work (helper approval/repair, stable signing, build 8 notarization) is on `feat/granipa-v2` only. No 2.0.1 GitHub Release.

Do not treat "no commits on `main` since June" as "V2 never left this Mac".

### Battery control removed (2026-10-05)

The root helper never launched (`EX_CONFIG` 78 / `needs LWCR update`), and on
macOS 27 the SMC charge keys are gone (`CHTE`/`CH0B`/`CH0C` not found on a
Mac16,12) while their replacements (`bfD0`/`bfE0`/`bfF0`) return
`kIOReturnNotPrivileged`. macOS has a native charge limit (80–100%,
System Settings → Battery). The user chose to drop battery control from
Grañipa. `LegacyBatteryHelper` unregisters a daemon left by 2.0.0/2.0.1
builds; the plist and stub must keep shipping until no such installs remain.

### Meeting audio, notes and shortcuts (2026-10-16, stacked hold PRs)

Stack on `feat/granipa-v2`: #28 windows → #29 battery → `fix/v2-dictation-mic`
→ `fix/v2-macro-hold` → `fix/v2-meeting-mic-file` → `feat/v2-meeting-voice`
(this branch also carries #26's two commits).

- Meetings since 2026-09-28 had a 557-byte `mic.m4a` (a late tap buffer
  reopened the file after stop); fixed, so "Me" is transcribed again.
- Meetings record the mic without echo cancellation. After a meeting,
  `EchoBleedFilter` removes "Me" words the system channel said at the same
  time, using recognizer word timings (migration `v9`,
  `transcriptSegment.words`). Each rewrite is backed up to
  `transcript-backups/` and deleted with its meeting. Live-ASR finals carry no
  word timings yet, so the automatic pass skips them.
- Playback plays mic + system together by default (Both / Mic / System).
- AI notes address the user ("Me") in the second person; the email draft is
  first person. Re-enhance cleans bleed first.
- Grok runs `grok-4.7-build-fast --reasoning-effort low` (~2 min on a 50-min
  meeting; the CLI default hit the 600 s timeout).
- Caps Lock macro works while held (HID remap to F18, owned and removed by
  Grañipa); the dictation failure overlay can be dismissed.

Open: AirPods single-tap dictation ends ~120 ms after start ("Didn't catch
that"); logging is in, cause not found. Live transcription on one mixed
stream is not started (CPU to be measured first).

Last recorded suite (2026-09-06, not re-run this session): 465 tests /
77 suites, `swift test --no-parallel`. 49 test files are in
`Tests/GranipaTests/` on this branch.

## Open decisions

Still human one-way doors (plan + T0 contract). Not implemented as if decided:

- Integrations / OAuth (none).
- Audio retention policy.
- Live AI on the recording stage.
- Localization of chrome (English only).
- Video / screen capture.
- Participants / contacts.
- Accuracy substitute (omit vs real metric). Light appearance (app forces dark).
- Tags, standalone tasks, collections tables (T7 postponed 2026-09-05).
- Merge `feat/granipa-v2` to `main`.
- Publish 2.0.1 (the helper blocker went away with battery control).

## Next

1. Human merges [#27](https://github.com/Zertyn-Enterprises/granipa/pull/27) (or sets the default branch). Until then clones stay on 1.0.4.
2. Decide PR #26 (post-recording CPU) into `feat/granipa-v2` before or after that merge.
3. Remove the legacy helper plist and stub once no 2.0.0/2.0.1 installs can hold a registration.
4. Replace `docs/home.png` with a V2 shot when one exists.
5. Panel xreview 2026-09-19 vs `main`: Claude ISSUES + GLM ISSUES (listed on #27). Codex/Kimi did not run. Not fixed in the docs commit.
