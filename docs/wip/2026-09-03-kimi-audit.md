# KIMI — auditoría adversarial UI/UX (fase 1, SOLO LECTURA)

Lee primero `docs/wip/2026-09-03-orquestacion.md`. Eres Kimi. No escribas código. No commits. No ramas.

Cuando termines, escribe `docs/wip/2026-09-03-kimi-hallazgos.md` y manda a GLM (ListAgents → session que matchee `granipa-glm` / uuid `3236d4cb-3d71-4527-9869-ab5cda13ccf5`) un único `landed: UI/UX audit in docs/wip/2026-09-03-kimi-hallazgos.md`.

Si GLM ya dejó `docs/wip/2026-09-03-glm-hallazgos.md`, léelo y escribe la réplica en `docs/wip/2026-09-03-kimi-replica.md` (qué está mal, qué falta, qué rechazas). Si aún no existe, espera ~15 min, relee, replica. No te quedes colgado: si no aparece, deja una línea `blocked: GLM hallazgos ausentes` al final de tu informe.

## Objetivo

Auditoría de producto y UI/UX de Grañipa. El humano quiere mejorar UI, UX, añadir live transcription local tipo SuperWhisper, y bajar recursos. Tú atacas la **superficie**: lo que el usuario ve, entiende, y sufre.

## Scope (leer)

- `Sources/Granipa/UI/` (todos)
- `Sources/Granipa/Clipboard/ClipboardHistoryView.swift` + `ClipboardPanelController.swift`
- `Sources/Granipa/GranipaApp.swift` (escenas/ventanas)
- `Sources/Granipa/System/PermissionCenter.swift`, `HotkeyManager.swift`, `WindowManager.swift`
- `docs/home.png`, `README.md` (promesa vs UI real)
- SuperWhisper docs (ya leídas por Grok; verifica si citas): https://superwhisper.com/docs/get-started/introduction y recording window / menu bar / modes / voice models.

Fuera: no reimplementes ASR. GLM cubre pipeline/perf. Tú puedes señalar UX de latencia/estados de transcripción.

## Preguntas que DEBES responder con evidencia

1. **Job-to-be-done.** ¿La app se entiende en 10 s? Onboarding, home, menubar, HUD: ¿cuál es el camino feliz de “hay una reunión → notas”? ¿Dónde se pierde?
2. **Settings overload.** 8 tabs (`SettingsView.swift`). ¿Cuáles son core vs productividad vs power-user? ¿Qué se puede fusionar/esconder sin perder capacidad?
3. **Recording UX.** `RecordingHUD` compact vs expanded, `RecordingBar`, `MeetingDetailView` live transcript. Compara con SuperWhisper recording window + menu bar. ¿Falta overlay de dictado, o Grañipa no debería ser eso?
4. **Live transcript.** ¿El usuario ve palabras al hablar? Volatile vs final. Estados `preparing/live/finishing/failed`. ¿Errores accionables?
5. **Home/sidebar.** Búsqueda, folders, calendario hero, empty states. Densidad, jerarquía, serif titles vs controles.
6. **Tema.** `Theme.swift` tokens vs hex sueltos / system colors en otras vistas. Dark-only (`.preferredColorScheme(.dark)`). ¿Light mode, accessibility (Dynamic Type, Reduce Motion, VoiceOver)?
7. **Productividad injertada.** Clipboard `⌥⇧V`, OCR `⌥⇧T`, window manager. ¿Ayudan al job de meetings o diluyen? Coste cognitivo + coste de recursos (GLM medirá CPU; tú el de UX).
8. **Permisos.** `OnboardingView` + `PermissionsView` + TCC reset en rebuild ad-hoc. ¿El usuario entiende por qué falla el system audio?
9. **Promesa vs realidad.** README dice “fully local, no cloud, no subscriptions” y a la vez LLM vía CLIs. ¿Copy honesto?
10. **Quick wins P0/P1** (cambio pequeño, ganancia grande) vs rediseños (no proponer rewrite de toda la UI).

## Formato del informe

```
# Kimi hallazgos UI/UX — 2026-09-03
## Camino feliz (verificado)
## Hallazgos
### P0 …
- evidencia: path:línea
- por qué duele
- arreglo mínimo
## SuperWhisper: qué copiar / qué no (y por qué)
## Recorte de superficie (qué apagar por defecto)
## Réplica pendiente / hecha
```

Sé hostil con la app. Si algo es mediocre, dilo. Si Grok se equivocó en los “hechos verificados” de orquestación, corrígelo con archivo:línea.
