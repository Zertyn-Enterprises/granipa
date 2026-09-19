# CONTEXT — Grañipa

Product state. Rules live in `AGENTS.md` (`CLAUDE.md` is a symlink to it).

## What it is

Native macOS 26+ (Apple Silicon) meeting recorder and notes app. No bot joins
the call. Mic + system audio, on-device live transcription, speaker diarization,
AI-enhanced notes via the user's existing CLI subscriptions (claude / codex /
gemini / grok — no API keys). Also: hold-to-talk dictation, clipboard history,
OCR, window snapping, optional battery charge limit.

Local by default. Optional cloud: Muse (system-channel ASR only), dictation
text rewrite (SpaceXAI or a custom OpenAI-compatible URL).

Bundle id `com.zertyn.granipa`. Data:
`~/Library/Application Support/Granipa/`.

## Stack

Swift 6 · SwiftUI · SwiftPM (no Xcode project) · GRDB · FluidAudio 0.15.2 ·
Sparkle 2.7+ · two executables: `Granipa` and `GranipaBatteryHelper`.
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
| PR V2 → `main` | None at the start of this session. Agents open one hold-PR and do not merge it. |
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

### Helper / battery (not done)

Build 8 was notarized after explicit approval (submission
`89606c75-71ac-4f9a-81bf-85d30b9c31aa`) and was **not** installed over
build 7. Helper launch on the development Mac was still `EX_CONFIG` (78) /
`needs LWCR update`. That is an OS launch-constraint failure, not a
verified app-logic miss. Do not publish 2.0.1 as a helper fix.

Last recorded suite (2026-09-06, not re-run this session): 465 tests /
77 suites, `swift test --no-parallel`. 53 test files are in
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
- Publish 2.0.1 (blocked on helper + safe install of build 8).

## Next

1. Human merges the V2 → `main` PR (or sets the default branch). Until then clones stay on 1.0.4.
2. Decide PR #26 (post-recording CPU) into `feat/granipa-v2` before or after that merge.
3. Helper LWCR / build-8 install remains a machine-local gate, not a docs gate.
4. Replace `docs/home.png` with a V2 shot when one exists.
