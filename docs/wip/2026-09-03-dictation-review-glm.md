# GLM — review adversarial del overlay de dictado (fase implementación)

Eres GLM (`granipa-glm`). No escribas código. No commits. No ramas.

El humano corrigió a Grok: las reviews van a **estas sesiones** (k3[1m] / glm-5.3), no a modelos del catálogo de Grok TUI.

## Qué cambió (mandato humano, no lo re-litigues)

- Tesis: local/privacy por defecto; cloud opt-in si mejora la experiencia.
- SÍ queremos overlay de dictado tipo Superwhisper.
- Muse Voice Transcribe opt-in, apagado por defecto.
- Captions de reunión: overlay local.
- Código en `feat/dictation-overlay`, working tree sucio.

Tu hallazgo de esta mañana (“no copiar overlay de dictado”) quedó anulado. Revisa el código nuevo. Además ataca **correctness / Swift 6 / audio / hotkeys / Muse client**, no solo UI.

## Scope (leer)

- `Sources/Granipa/Dictation/` (todo)
- `Sources/Granipa/UI/CaptionsOverlay*.swift`
- `Sources/Granipa/System/HotkeyManager.swift`
- `Sources/Granipa/System/KeychainStore.swift`
- `Sources/Granipa/Audio/LevelGate.swift`
- `Sources/Granipa/AppState.swift`
- `Sources/Granipa/Transcription/SpeechModels.swift` (prewarm)
- `Tests/GranipaTests/DictationTests.swift`
- `docs/wip/2026-09-03-glm-dictation-ui.md` — eso lo escribió un GLM *spawned dentro de Grok*. No es tu informe. Léelo y di qué está mal o incompleto con evidencia.

## Entregable

Escribe `docs/wip/2026-09-03-glm-dictation-code.md`

```
# GLM — dictation overlay code/UI — 2026-09-03
## P0 / P1 / P2
- evidencia: path:línea
- por qué duele
- arreglo mínimo
## Muse / Apple engines
## Hotkey press/release
## Qué el GLM-interno de Grok se inventó o se dejó
```

Cuando termines: un `landed:` a Kimi (`e36502c8-64a8-48cc-a4d5-5dae5f813fd3` / `granipa-kimi`). Réplica cuando exista `docs/wip/2026-09-03-kimi-dictation-ui.md`.
