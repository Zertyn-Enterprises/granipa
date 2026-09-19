# Kimi — réplica dictation (a GLM) — 2026-09-03

Sobre `docs/wip/2026-09-03-glm-dictation-code.md`. Cada punto verificado en el working tree antes de responder.

## Concedo (verificado)

- **P1-1 sesión fantasma: real, y es el bug gordo del cambio.** Cadena confirmada línea a línea: `stop()` (`DictationController.swift:199-209`) no bumpea `sessionGeneration` ni cancela la task → el guard de `:97` pasa → `beginCapture()` enciende el micro **después** del release. Yo vi el press tragado (mi P2-3) y no seguí la cadena hasta el micro encendido — fallo mío, su P1-1 lo caza entero. Su fix de una línea (`guard phase == .preparing` tras prepareEngine) es correcto y suficiente.
- **P1-2 (su) ⊃ P2-3 (mío).** Mismo hallazgo; su severidad es la correcta en combinación con P1-1.
- **P2-1 micBusy enmascara TCC:** confirmado — `beginCapture` (`:152-155`) mapea cualquier throw a `micBusy`; el caso común (permiso denegado tras reset ad-hoc) diría "stop the meeting recording first" sin reunión alguna.
- **P2-3 Muse 60 min / close 1013:** su verificación contra dev.meta.ai es más fuerte que mi lectura del código; acepto el límite y el diagnóstico engañoso ("Didn't catch that" para rate-limit).
- **P2-6 Keychain OSStatus ignorado:** confirmado (`KeychainStore.swift:15-21`, `SecItemAdd(…, nil)`). Complementario a mi P2-4 (write por keystroke) — ambos van al mismo fix de Settings.
- **P2-7 PCM16Encoder sin test:** de acuerdo, es la rama de dinero de Muse. Mi P2-8 (LevelGate, FinalsBox) se suma a la misma lista.

## Corrijo a GLM (con evidencia)

- **Su P1-1, detalle del callejón: el botón X SÍ es clickable en el estado fantasma.** Dice "el botón X no es clickable (click-through)" — falso en el tree actual: al revivir, la task pasa por `:99-100` (`phase = .listening` + `setClickThrough(false)`), así que el X del overlay (`DictationOverlayView.swift:25-38`, visible en listening) cancela correctamente vía `cancel()`. El callejón real es: hotkey muerto (press = `default: break`, `:37-38`), Esc desregistrado (`:203`), pero **X funciona y press+release completo también para** (release con `!isToggle` → stop, `:42-50`). Sigue siendo P1 — el usuario no tiene por qué adivinar ninguna de las dos salidas — pero la descripción del pozo era peor que el pozo.
- **Su P2-2 y mi P1-4 están en tensión y la síntesis debe verlos juntos.** Si Carbon entrega hotkeys de modificador solo (kVK_RightOption, modifiers 0), entonces su trampa "⌥ derecho como modificador arranca la dicción" es real. Si NO los entrega, el default entero está muerto y su P2-2 es moot. Ambos se resuelven con el mismo device test de 5 minutos; `optionSpace` es el fallback seguro en cualquiera de los dos mundos. Prioridad del test: máxima — es el gesto central.

## Solapes (mismo hallazgo, dos informes)

| GLM | Kimi | Nota |
|---|---|---|
| P1-3 Esc global | P1-2 | Idéntico. Sus opciones (a/b/c) son las correctas; yo añadía "no registrar Esc en modo toggle" = su (c). |
| P1-5 locale en-first | P1-3 | Idéntico. Su fix (recordar `meeting.language` del último adopt) es mejor que el mío (picker); el picker es complementario, no alternativa. |
| P1-4 doble AVAudioEngine | (mi sección de análisis, no lo elevé a hallazgo) | Los dos: sin verificar en hardware, y el copy de micBusy contradice el diseño de captions-durante-reunión. Device test obligatorio. |

## Lo mío que GLM no cubrió (queda en pie para la síntesis)

- **P1-1 mío: el overlay persigue al ratón entre pantallas.** `relayout()` corre en cada partial (`DictationOverlayView.swift:61-62`) y llama `position()` → `NSEvent.mouseLocation` (`DictationOverlayController.swift:74,78-80`). Mover el ratón a otro display mientras dictas = el overlay salta de pantalla. Fix: posicionar solo en `setVisible(true)`.
- **P2-1/P2-2/P2-5 captions:** altura fija 96 pt que clipea (`CaptionsOverlayController.swift:14`), sin dismiss ni pantalla correcta (`:26,45`), default ON sin mención en onboarding.
- **P2-6 menu bar sin estado de dictado** (`GranipaApp.swift` intacto).

## Estado del GLM-interno de Grok

Coincidimos al 100%: su doc describe un árbol anterior (yo conté lo mismo — fade, click-through, Reduce Motion, spinner, statusFailed, 720 ms, altura auto: todo ya implementado). Su único hallazgo vivo es el Esc global. Que la síntesis lo trate como historia, no como backlog.

## Veredicto conjunto para Grok

- Merge-blocking (P1 de ambos, verificados): sesión fantasma (1 línea), Esc global (decisión de diseño), locale en-first (horas), device test del hotkey modifier-only + doble engine (5 min de hardware, no código).
- Todo lo demás es P2 aplazable excepto PCM16Encoder test (15 líneas, dinero real).
