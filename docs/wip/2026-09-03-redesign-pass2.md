# Rediseño pass 2 — premium craft (ahora)

Grok orquesta. Checkout `feat/dictation-overlay`. No commits. No main. No loop de 20.

Norte: `docs/wip/2026-09-03-redesign.md` sección **NORTE PREMIUM**. Si no se siente Raycast/Superwhisper/Linear, no es este pase.

Grok ya cableó `PanelMotion` (dictado, clipboard, historial, captions, toast) y va a cablear `DictationController.retry()` + `lastFailureRetryable`. No pises esos.

## Kimi — `UI/*`, Toast, ClipboardHistory, DictationHistory, DictationOverlayView

1. **Home rows** pintan `app.pipelinePhase(for: meeting)` (Grok lo añade en AppState): Recording / Finishing / Transcribing / Enhancing / Failed, no solo "Processing". Tokens + Theme.spring.
2. **Menu bar** (`MenuBarView.swift`): 3 bloques — Capture (dictate/record) · Tools (clipboard/OCR/emoji) · App (open/settings/quit). Battery compacta. El "Processing notes…" usa pipeline phase, no un botón muerto. Menos de 12 ítems visibles en idle.
3. **DictationOverlayView**: si `phase == .failed` y `lastFailureRetryable`, botón **Retry** (hit 28) que llama `dictation.retry()`. Waveform spring ya está; no lo rompas.
4. **Onboarding**: misma familia (radiusOverlay, space tokens, una acción primary). 3 pasos, cero muro.
5. **Sidebar**: folders un peso más quieto que Home/Dictation (opacity o type).

`swift build`. Append `docs/wip/2026-09-03-redesign-log.md`. `landed:` en el log, no chat.

## GLM — Transcription + dictation engines

1. `MeetingPipeline.phase` debe distinguir finishing vs transcribing vs enhancing con los datos que AppState ya tiene. Si el mapping actual miente (p.ej. processing+nil coordinator = transcribing siempre), corrígelo y cubre con test. No toques UI.
2. HUD/RecordingBar ya tienen retry de transcripción. Asegura que `retryIfFailed` es el único camino y que `Phase` que pinta Kimi coincide con el enum.
3. Nada de restyle. Nada de Theme.

`swift test --filter MeetingPipelineTests`. Append log.

## Grok

- `AppState.pipelinePhase(for:)`
- `DictationController.retry()` + `lastFailureRetryable`; overlay no se auto-esconde si retryable
- Bundle cuando aterrice un slice usable
