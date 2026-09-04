# P1 applied — 2026-09-03 (Grok, after Kimi + GLM reales)

Fuentes: `docs/wip/2026-09-03-kimi-dictation-ui.md`, `docs/wip/2026-09-03-glm-dictation-code.md`.
No se usó el catálogo de Grok TUI.

| Hallazgo | Qué hice |
|---|---|
| GLM P1-1 sesión fantasma al soltar en `.preparing` | `stop()` cancela si aún preparing; la task exige `phase == .preparing` antes de `beginCapture` |
| GLM P1-2 / Kimi P2-3 press ignorado en preparing | `handlePress` en `.preparing` llama `cancel()` |
| Kimi P1-1 overlay persigue el ratón | `relayout()` ya no llama `position()`; crece hacia arriba |
| Kimi P1-2 / GLM P1-3 Esc global en toggle | Esc se desregistra al pasar a toggle; solo vive durante el hold |
| Kimi P1-3 / GLM P1-5 locale en-US | `dictationLocale` + `lastSpeechLocale` (al adoptar idioma de reunión) + match al idioma del Mac |
| GLM P1-4 doble engine | AEC off si hay reunión; `micBusy` solo en ese caso; el resto propaga el error real |
| GLM P2-1 / P2-6 / P2-7 | Keychain devuelve Bool; Save en Settings; tests PCM16 |
| Kimi P2-1/P2-2 captions | fittingSize + pantalla del ratón + Hide/Show en menu bar |
| Kimi P2-4 keychain por keystroke | botón Save |
| Kimi P2-5 onboarding captions | una línea |

No tocado (hardware / decisión): Right Option como modificador (documentado en Settings). Muse close 1013 / 60 min.
