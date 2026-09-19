# Kimi — dictation overlay UI — 2026-09-03

Review del código nuevo en `feat/dictation-overlay` (working tree, sin commit). Todo verificado leyendo el código esta sesión; `I:` = inferencia etiquetada. Gates: `swift build` ✅ (2.5 s, incremental), `swift test --filter DictationTests` ✅ 8/8. No escribí código.

Barra aplicada: Superwhisper recording window — hold → overlay instantáneo, no roba foco, waveform, partials, release → paste.

## P0

Ninguno. La feature está completa y la mecánica base es correcta.

## P1

### P1-1 — El overlay persigue al ratón entre pantallas con cada partial

- evidencia: `DictationOverlayView.swift:61-62` llama `relayout()` en cada cambio de preview/fase; `relayout()` llama `position()` (`DictationOverlayController.swift:74`); `position()` usa `NSEvent.mouseLocation` (`:78-80`).
- por qué duele: dictando, el usuario mueve el ratón para seguir leyendo en otra pantalla — el overlay salta de display en el siguiente partial. El fix del P2-4 de GLM-interno (pantalla del ratón) es correcto **al abrir**, pero ejecutarlo en cada re-layout convierte cada palabra dictada en un reposition.
- arreglo mínimo: `position()` solo en `setVisible(true)`; `relayout()` debe re-medir altura manteniendo el origen (crecer hacia arriba, no re-centrar).

### P1-2 — Esc global robado mientras dura el dictado

- evidencia: `DictationController.swift:275-283` registra `kVK_Escape` con `modifiers: 0` vía Carbon al entrar en preparing/listening; se desregistra en stop/finish/fail/cancel.
- por qué duele: mientras esté registrado, Esc no llega a la app de delante (cerrar diálogo, cancelar edición): cancela el dictado en su lugar. En hold-to-talk la ventana son segundos; en **modo toggle** (tap corto → `isToggle`, `DictationController.swift:45-48`) puede ser minutos con Esc muerto en todo el sistema. GLM-interno lo marcó (su P1-3); sigue presente.
- arreglo mínimo: en modo toggle, no registrar Esc (el segundo press ya para); registrarlo solo mientras la tecla sigue pulsada. Alternativa honesta: documentar el tradeoff en Settings.

### P1-3 — Dictado en `auto` dicta siempre en el primer locale (en-US por defecto)

- evidencia: `DictationController.preferredLocale()` (`:289-295`): si `defaultLocale == "auto"` usa `probeLocales.first ?? "en-US"`. Default de probes = `["en-US", "es-ES"]` (`LanguageDetection.swift:32`). El path Muse sí manda `languageBias` con ambos idiomas (`DictationController.swift:175-182`); el path local no prueba — un solo analyzer.
- por qué duele: el usuario por defecto de esta app es bilingüe es/en (los meetings sí hacen probing). Con settings de fábrica, dictar en español sale por el modelo inglés. Es la P1 de siempre — el caso en+es — trasladada al dictado.
- arreglo mínimo: picker "Dictation language" en DictationSettings (opciones: los probes seleccionados; default = primero) + una línea de copy. Barato y respeta el coste (probing doble por dictado sería excesivo).

### P1-4 — El gesto central (Right Option solo) no es verificable en lectura

- evidencia: `AppState.registerDictationHotkey()` registra `kVK_RightOption` con `modifiers: 0` (`AppState.swift:94-108` diff). `I:` no puedo confirmar sin dispositivo que Carbon entregue press/release para una tecla modificadora sola; si no dispara, toda la feature está muerta y solo funcionan "Right Command" (también modificador) y "Option+Space" (combo normal, ese sí seguro).
- arreglo mínimo: device test explícito antes de commit; si falla, default a `optionSpace`. Lo dejo como verificación pendiente, no como bug confirmado.

## P2

- **P2-1 Captions con altura fija, sin re-layout.** `CaptionsOverlayController.swift:14` fija 656×96 en `attach` y nunca re-mide; el contenido puede ser header + último segmento (2 líneas, `CaptionsOverlayView.swift:56`) + volátil (2 líneas) ≈ 120 pt. Clip seguro con texto largo. Fix: el mismo `fittingSize` del dictation overlay.
- **P2-2 Captions: sin dismiss, sin drag, pantalla equivocada.** `ignoresMouseEvents = true` permanente (`CaptionsOverlayController.swift:26`): durante una reunión no hay forma de quitarlas salvo Settings → General. Y posiciona en `NSScreen.main` (`:45`), no en la pantalla de la reunión. Mínimo: item de menú "Hide Captions" mientras graba + pantalla del ratón como dictation.
- **P2-3 Segundo press durante `.preparing` ignorado.** `handlePress` solo maneja `.listening where isToggle` (`DictationController.swift:33`); tap (toggle) + press mientras carga el modelo = nada. Sensación de botón roto en el arranque. Fix: press en `.preparing` con `isToggle` → cancel.
- **P2-4 SecureField escribe Keychain por keystroke.** `SettingsView.swift` (DictationSettings): `onChange` → `SecItemDelete`+`SecItemAdd` por carácter; vaciar el campo borra la key sin confirmación. Mínimo: escribir en `onSubmit`/botón Save.
- **P2-5 Captions default ON y ausentes del onboarding.** `meetingCaptionsEnabled ?? true` (`CaptionsOverlayController.swift:33-34`): la primera grabación abre un panel flotante no pedido. El onboarding añadió el atajo de dictado (`OnboardingView.swift:132`) pero no menciona captions. Una línea en step 2, o banner la primera vez.
- **P2-6 Menu bar mudo para dictado.** `GranipaApp.swift` sin cambios: el icono refleja reunión, no dictado. Con `Theme.status*` ya creado (`Theme.swift:22-26`), un estado en el `MenuBarExtra` cierra mi hallazgo de esta mañana para ambos modos.
- **P2-7 `paste()` destruye el clipboard previo** (`DictationController.swift:227-239`). Estándar en la categoría y recuperable vía clipboard history — anotado como decisión consciente, no bug.
- **P2-8 Lógica pura nueva sin tests.** `LevelGate` (intervalo+delta, ramas) y `FinalsBox`/`FinalTextBox` (acumulación) no tienen tests; `DictationTests` cubre trigger/parser/idiomas (8 tests, verde). Rank 4 de Code Quality — baratos de añadir.

## Lo que está bien (verificado)

- Hold/release/toggle con threshold 0.22 s — testeado (`DictationTests.swift:6-14`), `sessionGeneration` cancela sesiones obsoletas (`DictationController.swift:84,97,102`).
- Cero robo de foco: `nonactivatingPanel` + paste a la app de delante vía `PasteService`; overlay visible desde `preparing` — feedback instantáneo al pulsar.
- Reduce Motion respetado en todo el overlay (`DictationOverlayView.swift:5,20,49,74,83`) — primer lugar de la app que lo hace; que se extienda al resto.
- Click-through por fase, fade in/out, `ProgressView` en processing, tokens `status*` en `Theme`.
- Reuso disciplinado: `transcribeChannel`, `BufferConverter`, `PasteService`, `HotkeyManager`, `SpeechModels`. Nada reinventado.
- Quick wins de la síntesis aplicados en el mismo diff: API default off (`AppState.swift:211`), webhook loop gated (`:228-232`), clipboard gated + setter, detector fuera de main (`MeetingDetector.swift:39-40`), prewarm de speech assets (`SpeechModels.swift:22-36`), throttle de niveles (`LevelGate` en `RecordingEngine.swift:25` y dictation), "Show Recording HUD" en el menú.
- Copy honesto en todas las superficies: onboarding bullets, `Info.plist` usage descriptions, README Privacy — "fully local" → "local by default" en todos lados. Mi P1 de copy de esta mañana queda cerrado.

## Qué GLM-interno acertó / falló

Su review (`docs/wip/2026-09-03-glm-dictation-ui.md`) fue contra una versión anterior del working tree — casi todo está ya arreglado en el código actual:

- **Stale (ya arreglado, verificado)**: P0-1 altura fija (`relayout()` existe y corre en cada cambio), P0-2 colisión captions/dictation (dictation a bottom+150, `:84`, y exclusión mutua vía `DictationController.swift:90,271-273`), P1-1 fade (`:41-54`), P1-2 click-through por fase, P1-4 Reduce Motion, P1-5 spinner en processing, P2-1 placeholder a `textSecondary`, P2-3 `statusFailed` existe, P2-6 done a 720 ms (`:259`).
- **Sigue vivo**: P1-3 Esc global (mi P1-2); P2-5 hit target — ahora 22×22 con hover (`DictationOverlayView.swift:29-36`), mejorado pero bajo el mínimo cómodo.
- **Falló** al afirmar "frame is set once at attach" (su P0-1): falso en el código actual. Y su fix de posicionar en la pantalla del ratón (su P2-4, aplicado) es la causa directa de mi P1-1: correcto al abrir, incorrecto en cada re-layout.

## Réplica pendiente a GLM (sesión granipa-glm)

Pendiente su review. Réplica irá en `docs/wip/2026-09-03-kimi-dictation-replica.md` cuando entregue.
