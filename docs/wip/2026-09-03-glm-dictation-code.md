# GLM — dictation overlay code/UI — 2026-09-03

Review adversarial del working tree de `feat/dictation-overlay` (bd05f9d + 14
ficheros modificados + 11 nuevos sin commit). Solo lectura; nada de esto está
en main. Líneas citadas = working tree actual.

Antes de los hallazgos, lo verificado POSITIVO — porque este cambio también
ADOPTA el quick-win pack de la fase 1, y conviene que Grok lo sepa:

- LevelGate en ambos paths de niveles (`RecordingEngine.swift` diff,
  `DictationController.swift:25,139-146`) — mi P1-3 de la mañana, adoptado.
- Detector fuera de main (`MeetingDetector.swift` diff: `Task.detached` +
  `apply(active:)`) — P1-5 adoptado. Clipboard gating + intervalo 2 s off
  (`ClipboardMonitor.swift` diff, `AppState.setClipboardCaptureEnabled`) — P1-4
  adoptado. Webhook guard (`AppState.swift:228-233`) y API default OFF
  (`AppState.swift:211`) — P2-1/P2-2 adoptados. Prewarm de speech assets al
  launch (`SpeechModels.prewarmPreferredLocales` + llamada en `AppState` init)
  — P1-2(a) adoptado. "Show Recording HUD" en menu bar + "Dictate" —
  hallazgos de Kimi adoptados.
- HotkeyManager ahora soporta press+release (`kEventHotKeyPressed` +
  `kEventHotKeyReleased`, ambos en el mismo InstallEventHandler) y
  `unregister(id:)` real (antes append-only leak). Re-registrar limpia el ref
  previo. Correcto.
- Muse wire protocol **verificado contra la doc oficial de Meta**
  (dev.meta.ai/docs/speech-to-text, fetched hoy): endpoint
  `wss://api.meta.ai/v1/asr/realtime?sessionId=…` ✓, auth en el handshake
  (`authorization.accessToken` con "Bearer ", el header HTTP se ignora — el
  shape "raro" del código es el CORRECTO) ✓, `PCM_24KHZ` s16le mono ✓,
  `PUSH_TO_TALK` ✓, `CUMULATIVE` ✓, `{"type":"endStream"}` + leer hasta close
  1000 ✓, eventos `transcript{transcript,final}`/`speechComplete{transcript}`/
  `error{message}` ✓. Modelo `muse-voice-transcribe-1.0` ✓. Precio "$0.18/hour"
  del Settings ✓ (página del modelo: $3/1.000 audio-minutos).
- Honestidad de privacidad actualizada en README (sección Dictation + Privacy
  nombra el opt-in de audio a Muse), Info.plist y onboarding. Bien.

## Hallazgos

### P1-1 — Soltar durante `.preparing` deja una sesión fantasma que arranca el micro DESPUÉS del release

- evidencia: `DictationController.swift:93-117` — la task hace
  `prepareEngine()` → (guard generation) → `beginCapture()` → `phase = .listening`
  → `runEngine`. `stop()` (`:199-209`) solo actúa sobre el estado PRESENTE
  (`phase = .processing`, finish del continuation — que aún es nil —, y
  `await transcribeTask?.value`). No bumpea `sessionGeneration` ni cancela la
  task.
- failure path: primera dicción del usuario (o tras cambiar de locale):
  `ensureInstalled`/`bestAvailableAudioFormat` tardan segundos → el usuario
  pulsa, habla, suelta mientras `phase == .preparing` → `handleRelease` →
  `stop()` consume el stop (guard pasa por `.preparing`), desregistra Escape
  (`:203`) y pone el overlay click-through (`:202`) → la task despierta, el
  guard de generation PASA (nadie lo bumpó), `beginCapture()` enciende el micro
  YA con el usuario callado, `phase = .listening`, y el engine transcribe
  silencio/habitación indefinidamente. El hotkey no lo para por press
  (`handlePress:31-40` — `.listening` sin `isToggle` cae en `default: break`);
  lo para un press+release completo (release con `!isToggle` sí llama stop) o
  el menu bar. La Escape del overlay ya no existe (desregistrada por el stop
  fantasma) y el botón X no es clickable (click-through).
- por qué duele: rompe exactamente en la primera dicción — el momento de la
  demo. El audio dicho durante el load se pierde (el micro ni existía).
- arreglo mínimo: en la task, tras `prepareEngine`, `guard self.phase == .preparing
  else { return }` (el stop ya solicitado gana). Una línea. Alternativa
  equivalente: `stop()` bumpea `sessionGeneration` cuando `.preparing`.

### P1-2 — Press de toggle-cancel tragado durante `.preparing`

- evidencia: `handlePress` (`:31-40`) solo maneja `.listening where isToggle`;
  un segundo tap durante `.preparing` cae en `default: break`. Su release no
  hace nada (`handleRelease:43` exige `!isToggle`... y en tap-toggle `isToggle`
  se puso true en el primer release). Mismo clan que P1-1: durante el load, el
  hotkey no responde.
- arreglo mínimo: incluir `.preparing` en la interrupción (press durante
  `.preparing`/`.listening` → stop/cancel).

### P1-3 — Escape global sin modificadores captura Esc de TODA la máquina mientras dicta

- evidencia: `registerEscape` (`DictationController.swift:275-283`) registra
  `kVK_Escape` con `modifiers: 0` vía `RegisterEventHotKey` — un hotkey global
  Carbon consume el evento para todas las apps. En modo toggle (minutos) cada
  Esc del usuario (cerrar diálogos, cancelar edits en la app en la que está
  DICTANDO) cancela la dicción Y nunca llega a la app destino. El GLM-interno
  de Grok lo marcó (su P1-3) y sigue abierto.
- arreglo mínimo: ninguna opción es perfecta sin event tap. Opciones: (a) soltar
  Esc global y quedarse con el botón X del overlay (no click-through durante
  listening) + release del hotkey como cancel; (b) Esc con modificador (⌘Esc);
  (c) solo registrar Esc mientras `phase == .listening` en modo hold (ventana
  corta) y nunca en toggle. Decisión de síntesis; documentar el tradeoff.

### P1-4 — Dicción durante una reunión: dos AVAudioEngine con voice-processing sobre el mismo input — sin verificar y con diagnóstico contradictorio

- evidencia: `beginCapture` (`:137-150`) crea un `MicRecorder` nuevo (segundo
  `AVAudioEngine` sobre el mismo device de entrada) con `echoCancellation`
  default true (`:138`) mientras `RecordingSession` puede tener el suyo con AEC
  activo. Si el device no admite dos engines con voice processing, `start`
  falla y sale como `DictationError.micBusy` (`:152-155`) cuyo texto dice
  "Microphone is busy — stop the meeting recording first" (`MuseDictationEngine.swift:179`
  — caso micBusy). Pero el propio controller ASUME que dicción-durante-meeting
  funciona: `meetingIsRecording` (`:17`, seteado por `AppState`) y el
  escondite/restauración de captions (`:90,271-273`).
- por qué duele: o funciona (y entonces ok, pero hay que probarlo) o falla — y
  el mensaje de fallo recomienda parar la grabación de la reunión, que es lo
  peor que puedes decirle a un usuario en mitad de una reunión. *Inferencia no
  verificada en hardware — hay que probar dictation con meeting recording
  activo en ambas configuraciones de AEC.*
- arreglo mínimo: probar en hardware; si falla, degradar con AEC off para
  dictation cuando `meetingIsRecording` y mensaje honesto ("dictation overlaps
  the meeting recording" con opción de continuar).

### P1-5 — `preferredLocale()` con "auto" elige el PRIMER probe (en-US): dicción en inglés para el usuario bilingüe

- evidencia: `DictationController.swift:289-295` — `auto` → `probes.first ?? "en-US"`
  y el default de probes es `["en-US", "es-ES"]` (`LanguageDetection.swift:32`).
  Las reuniones resuelven el idioma con cross-vote; la dicción ni prueba ni
  recuerda: un usuario es/en con settings default dicta SIEMPRE en en-US.
- por qué duele: es exactamente el usuario para el que existe el probe. La
  primera frase en español sale en inglés y se pega así en la app destino.
- arreglo mínimo: recordar el último locale adoptado por una reunión
  (`meeting.language` ya se persiste tras `adopt`) y usarlo como default de
  dicción cuando `defaultLocale == auto`; fallback al primero. Días→horas.

### P2-1 — `micBusy` enmascara el fallo real #1: TCC del micro denegado

- evidencia: `beginCapture` (`:152-155`) convierte CUALQUIER throw de
  `recorder.start` en `micBusy`. `MicRecorder.start` lanza un NSError propio
  ("Microphone input device is not ready") o falla el engine (permiso TCC
  denegado — el caso común tras el reset de grants por firma ad-hoc que
  documenta el propio README). El usuario ve "Microphone is busy — stop the
  meeting recording first" cuando no hay ninguna reunión grabando.
- arreglo mínimo: propagar el error subyacente; solo mapear a micBusy cuando
  de verdad haya otra captura activa.

### P2-2 — Right Option como hotkey dispara en cada uso de ⌥ como modificador

- evidencia: default `kVK_RightOption` + `modifiers: 0`
  (`AppState.registerDictationHotkey`); "Option + Space" usa `optionKey` (either
  option). Carbon dispara onPress en el key-down del modificador, use o no use
  como modificador: teclear "é" con ⌥E derecho, o cualquier shortcut ⌥-… que
  use la tecla derecha, arranca la dicción; mantener >220 ms y soltar pegará
  basura. SuperWhisper vive con el mismo tradeoff, pero aquí es configurable y
  sin documentar la trampa (el caption del Settings no la menciona).
- arreglo mínimo: documentarlo; si se quiere fix real, se necesita
  `CGEventTap` flagsChanged con supresión cuando hay otras teclas — no mínimo,
  decisión de síntesis.

### P2-3 — Muse: límite de 60 min y closes sin evento error se tragan como "éxito"

- evidencia: la doc verificada: sesión máx 60 min; rechazos con close 1013 SIN
  evento `error` previo. El receiver trata cualquier fallo de receive como
  "happy path" (`MuseDictationEngine.swift:84-87`) → transcribe devuelve
  `finals` vacío → `DictationError.empty` → "Didn't catch that — try again"
  (`:115-117,187`). Un rate-limit o corte de sesión larga se diagnostica como
  "no te entendí". En modo toggle olvidado, la sesión muere a los 60 min con
  este mensaje engañoso.
- arreglo mínimo: inspeccionar el close code (URLSessionWebSocketDelegate) y
  diferenciar; auto-stop de toggle dictation a los ~55 min.

### P2-4 — La dicción machaca el clipboard del usuario

- evidencia: `paste` (`DictationController.swift:227-239`) hace
  `clearContents` + `setString` sin guardar/restaurar el contenido previo.
  Comportamiento estándar en herramientas de dictado (SuperWhisper igual), pero
  en una app que TAMBIÉN es clipboard manager (`ClipboardMonitor` lo guardará
  todo, así que es recuperable vía ⌥⇧V) — solo dejarlo dicho.

### P2-5 — `bufferingNewest(48)` puede descartar audio y el drain en ráfaga roza el límite de backlog

- evidencia: `beginCapture` (`:132-135`). Buffers de 4096 frames ≈ 85 ms → 48
  chunks ≈ 4 s. Si el engine consume más lento de lo que produce el micro (Muse
  con red lenta), se caen los chunks más viejos = texto con huecos. Y al
  soltar, el drain del buffer en ráfaga choca con el "paced at roughly real
  time / ≤5 s send-ahead" de la doc verificada. Riesgo bajo (el envío por WS es
  más rápido que realtime), pero es el techo silencioso de robustez.

### P2-6 — KeychainStore.set ignora el OSStatus

- evidencia: `KeychainStore.swift:15-21` — `SecItemDelete` + `SecItemAdd(…, nil)`
  sin mirar status. Si el add falla (keychain bloqueado, entitlement raro), el
  usuario cree que la clave está guardada (el SecureField se ve lleno) y la
  dicción Muse fallará luego con "Add a Meta API key". Devolver Bool y pintarlo
  en Settings.

### P2-7 — Tests: falta PCM16Encoder

- evidencia: `DictationTests.swift` (8 tests) cubre trigger/parser/bias/keywords
  — bien. Pero `PCM16Encoder.data` (`PCM16Encoder.swift:12-34`) es rama pura
  con downmix float→int16 + clipping y es EL camino de dinero de Muse (bytes
  erróneos = transcripción basura facturada a $0.18/h). Un test con valores
  conocidos (0, +1, -1, 0.5 estéreo) son 15 líneas.
- huecos mayores (state machine del controller) necesitan refactor de
  inyección; no exijo ahora, pero el P1-1 es exactamente el tipo de bug que
  ese test habría cazado.

## Muse / Apple engines

- **Apple** (`AppleDictationEngine.swift`): reutiliza `transcribeChannel` de
  reuniones — buena reutilización; `.fastResults`/`.volatileResults` ya vienen
  de ahí. `FinalsBox` acumula finals y muestra partials correcto. Detalle:
  `ensureInstalled` se llama dos veces por dicción (controller `:122` y engine
  `:9`) — inofensivo (check async), redundante.
- **Muse** (`MuseDictationEngine.swift` + `MuseProtocol.swift`): protocolo
  verificado contra doc oficial (ver arriba) — incluyendo el auth "raro" que es
  el correcto. Cumulative partials → replace en FinalTextBox: correcto.
  `withTimeout(8 s)` para el receiver: correcto contra hangs. Keywords y
  languageBias en el handshake: coincide con la doc (custom vocabulary).
  `MuseLanguages` mapea ~26 códigos BCP-47.
- **Inferencia etiquetada**: ni un número medido de latencia/RAM de ningún
  engine (igual que en mi tabla A/B/C/D de la mañana). El local arranca un
  SpeechAnalyzer por dicción (sin reuse entre dicciones — setup por
  utterance); si la primera palabra tarda >300 ms perceptible, un
  analyzer/pool persistente es la palanca. Medir antes de tocar.

## Hotkey press/release

- Implementación Carbon correcta: ambos `kEventHotKeyPressed/Released` en un
  InstallEventHandler, dispatch por `GetEventKind`, handlers por id con
  onPress/onRelease opcionales, unregister real. Los release events de Carbon
  llegan si los modificadores siguen presionados — con Right Option hold puro,
  correcto.
- `WindowManager.setEnabled` ahora registra/desregistra los 14 hotkeys al
  toggle — adopta el gating (con default aún ON; el default-off de Extras
  sigue siendo decisión pendiente de la síntesis).
- Conflictos de ids verificados: 1 clipboard, 2 OCR, 3 dicción, 4 Esc temporal,
  100-113 ventanas. Sin colisiones.
- La trampa de modifiers: `optionSpace` con `optionKey` (either) choca con
  launchers tipo Raycast en ⌥Space de CUALQUIER option. Ver P2-2.

## Qué el GLM-interno de Grok se inventó o se dejó

`docs/wip/2026-09-03-glm-dictation-ui.md` describe un árbol ANTERIOR: **11 de
sus 13 hallazgos ya están implementados en el working tree actual**. Mapeo
(claim suyo → estado real):

| Su hallazgo | Estado en el tree |
|---|---|
| P0-1 altura fija clipea (456×128, "never re-sizes") | FALSO ya: `relayout()` (`DictationOverlayController.swift:62-75`) con fallback 456×160, llamado en cada `setVisible(true)` y en `onChange` de preview/phase (`DictationOverlayView.swift:61-62`) |
| P0-2 colisión con captions | FALSO ya: dictation anclado a minY+150 (`:84`), captions 28–124 → sin solape |
| P1-1 pop sin fade | FALSO ya: alpha 0→1/1→0 con NSAnimationContext (`:41-55`) |
| P1-2 no click-through por fase | FALSO ya: `setClickThrough` en cada transición — es literalmente el "patch" que él proponía |
| P1-3 Esc global | VIGENTE (mi P1-3) |
| P1-4 sin Reduce Motion | FALSO ya: `accessibilityReduceMotion` gating en todas las animaciones y el glow |
| P1-5 sin affordance en processing | FALSO ya: `ProgressView().controlSize(.mini)` (`DictationOverlayView.swift:15-18`) |
| P2-1 placeholder ilegible (tertiary) | FALSO ya: placeholder usa `textSecondary` (`:120`) |
| P2-2 contentTransition sin animation | FALSO ya: `.animation(value: dictation.phase)` (`:20`) |
| P2-3 .orange hardcodeado, falta statusFailed | FALSO ya: `Theme.statusFailed` existe y se usa (`:119`) |
| P2-4 NSScreen.main | FALSO ya: posiciona por `NSEvent.mouseLocation` (`:77-80`) |
| P2-5 cancel 18×18 sin hover | FALSO ya: 22×22 + `hoverHighlight` (`:29-36`) |
| P2-6 520 ms done | ahora 720 ms (`DictationController.swift:259`) |

Conclusión: ese doc es HISTORIA (pre-fix), no estado. Si la síntesis lo lee
como actual, planificará 11 fixes ya hechos. Lo que dejó fuera por completo
— todo el correctness no-UI, que nadie había cubierto hasta ahora: P1-1
(estado fantasma), P1-2 (press tragado), P1-4 (doble engine), P1-5 (locale
en-first), P2-1 (micBusy enmascara TCC), P2-3 (60 min/1013), P2-6 (keychain
silencioso), P2-7 (test PCM16). Nada "inventado" — sus citas eran correctas
para el árbol que leyó; el problema es que no volvió a mirar después de que
aplicaran sus propios patches.

## Réplica pendiente / hecha

Pendiente: `docs/wip/2026-09-03-kimi-dictation-ui.md` no existe aún al escribir
esto. Cuando aparezca, réplica en `docs/wip/2026-09-03-glm-dictation-replica.md`.
