# KIMI — review adversarial del overlay de dictado (fase implementación)

Eres Kimi (`granipa-kimi`). No escribas código. No commits. No ramas.

El humano corrigió a Grok: las reviews van a **estas sesiones** (k3[1m] / glm-5.3), no a modelos del catálogo de Grok TUI.

## Qué cambió (mandato humano, no lo re-litigues)

- Tesis: local/privacy por defecto; cloud opt-in si mejora la experiencia.
- SÍ queremos overlay de dictado tipo Superwhisper (hold-to-talk → texto en la app de adelante).
- Muse Voice Transcribe es motor **opt-in, apagado por defecto**.
- Captions de reunión: overlay local sobre el ASR que ya corre.
- Grok implementó esto en `feat/dictation-overlay` (working tree sucio, no hay commit).

Tu informe de esta mañana (`docs/wip/2026-09-03-kimi-hallazgos.md`) decía “no copiar el overlay de dictado”. Ese punto quedó anulado por el humano. Revisa el código **nuevo**, no re-argumentes el JTBD.

## Scope (leer)

- `Sources/Granipa/Dictation/` (todo)
- `Sources/Granipa/UI/CaptionsOverlayView.swift`
- `Sources/Granipa/UI/CaptionsOverlayController.swift`
- `Sources/Granipa/UI/Theme.swift` (tokens status*)
- `Sources/Granipa/UI/MenuBarView.swift`
- `Sources/Granipa/UI/SettingsView.swift` (DictationSettings + captions)
- `Sources/Granipa/UI/OnboardingView.swift`
- `Sources/Granipa/System/HotkeyManager.swift`
- `Sources/Granipa/AppState.swift` (wiring)
- `Tests/GranipaTests/DictationTests.swift`
- `docs/wip/2026-09-03-glm-dictation-ui.md` (review de un GLM *interno de Grok* — no es el tuyo; contradice con evidencia si está mal)

Barra: Superwhisper recording window. Hold → overlay instantáneo, no roba foco, waveform, partials, release → paste.

## Entregable

Escribe `docs/wip/2026-09-03-kimi-dictation-ui.md`

```
# Kimi — dictation overlay UI — 2026-09-03
## P0 / P1 / P2
- evidencia: path:línea
- por qué duele
- arreglo mínimo
## Qué GLM-interno acertó / falló
## Réplica pendiente a GLM (sesión granipa-glm)
```

Cuando termines: un `landed:` a GLM (session uuid `3236d4cb-3d71-4527-9869-ab5cda13ccf5` / `granipa-glm`) y espera su informe para réplica en el mismo fichero o `docs/wip/2026-09-03-kimi-dictation-replica.md`.
