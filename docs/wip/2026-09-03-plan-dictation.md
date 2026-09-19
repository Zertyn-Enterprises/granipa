# Plan — dictation overlay + Muse opt-in — 2026-09-03

Branch: `feat/dictation-overlay`. Grok implements. Kimi/GLM adversarial UI on the new overlay after it compiles.

## Product thesis (human, this session)

Local/privacy is the default. Cloud engines and APIs are opt-in when they make the experience clearly better.

## This slice

1. Resource: clipboard monitor doesn't start if off; API default off; webhook loop skips empty; detector CoreAudio off main; level throttle; speech models prewarm on launch; window hotkeys unregistered when snapping is off.
2. Dictation: hold-to-talk overlay (Superwhisper-shaped). Apple SpeechAnalyzer default. Muse Voice Transcribe opt-in (Keychain, ZDR).
3. Meeting captions overlay (local, from existing live transcript).
4. Full-app UI redesign is NOT this slice — adversarial review of the new overlay first.

## Not this slice

Ask-your-notes, command palette, light mode, extra engines besides Muse.
