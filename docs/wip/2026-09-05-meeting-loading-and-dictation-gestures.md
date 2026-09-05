# Meeting loading and dictation gestures — 2026-09-05

Historical working report, not product requirements. Base: `feat/granipa-v2@ea6171e`.

## Scope and acceptance

- Normal meeting entry opens Overview. Explicit Notes-library entry and active live recording retain their intentional routes.
- Meeting/tab navigation does not eagerly build an entire AI-notes document. Pending transcript/audio work has truthful states and stale completions cannot overwrite another load.
- Right Command short tap latches listening until the next press; hold records until release. Classification uses the physical gesture, independent of slow UI/setup. Menu and retry starts remain latched.
- Preserve storage, playback, capture exclusion, transcript filtering, notes editing and automatic paste/history. No dependencies or migrations.
- GLM implements meeting loading; Grok implements gestures. Review complete features across families, not each small patch. Codex integrates and verifies.

## Baseline verified this session

- `swift test`: exit 0; 355 tests / 62 suites; test execution 4.390 seconds. Log: `/private/tmp/granipa-meeting-load-baseline-tests.log`.
- Running Release build: PID 27164, same worktree bundle as previous report.
- Source: `MeetingDetailView.init` explicitly selected Transcript for entries with audio, Notes otherwise. Playback loading called `AVAudioPlayer(contentsOf:)` and `prepareToPlay()` on MainActor during entry. `MarkdownBlocksView.body` reparsed Markdown and used an eager VStack of inline-formatted blocks.
- Source: dictation classified release using `Date.now - pressStartedAt`, with the start timestamp taken before synchronous overlay presentation. `start()` reset `isToggle` even when a menu caller had just set it. The pending capture task could enter listening after a stop had set processing. These are verified code paths; which one caused each reported physical-key failure is not separately established.

### UI diagnostic, not a frame-rate benchmark

Read-only AX navigation was limited to the expected worktree app. No recording, playback, edits or private content dumps. AX press-return measures accessibility action latency, **not time to rendered pixels**; probing the accessibility tree can itself trigger layout. Concurrent development/compilation and user navigation make these indicative traces, not a controlled before/after FPS measurement.

One existing open meeting: AI Notes press-return `0.981306292 s`; Overview `0.53283025 s`; Transcript `0.268717708 s`. A sampling trace captured SwiftUI layout and `MarkdownBlocksView.inline`/`AttributedString` work on the main thread. The initial tree-crawling harness encountered stale controls and its failed sequence is not a successful smoke.

Second traversal, first row of Meetings (different meeting):

| Action | AX press-return before | AX response after 250 ms |
| --- | ---: | ---: |
| Open first meeting | 0.334158833 s | 0.058621459 s |
| Overview | 0.249503042 s | 0.003001291 s |
| AI Notes | 0.27995225 s | 0.000693791 s |
| Transcript | 0.284498583 s | 0.327318708 s |
| Action Items | 0.256881 s | 0.005483708 s |
| Overview again | 0.205872042 s | 0.000211084 s |

Diagnostic logs: `/private/tmp/granipa-meeting-tabs-sequence-before.log`, `/private/tmp/granipa-meeting-entry-before.log`; sample traces end in `.sample`. Names/text were deliberately excluded.

## Result

Integrated on `feat/granipa-v2@12fbc04` (19 commits since baseline):

- Overview default; separate transcript loading/empty/failed/retry states; retain loaded rows across tabs.
- AI Notes caches parsed blocks per source, uses a 30-block initial prefix and detached full parsing, lazy row rendering, and a truthful first-load/stale-source formatting indicator.
- AVAudioPlayer belongs to an actor; preparation does not run on MainActor. Pending audio has a preparing indicator. Follow-up fixes release audio on nil/missing paths, invalidate stale loads/ticks, and start ticks after the actual play command.
- Right Command uses physical timestamps with the existing 0.22-second threshold. Short taps latch; holds stop on release. Menu/Retry latch; stop-before-capture cannot reopen a session; terminal phases reject late partials. Tests use isolated event dispatch instead of registering live system-wide hotkeys.

### Integrated gates

| Gate | Result |
| --- | --- |
| `swift test` | exit 0; 390 tests / 67 suites; 2.098 s execution |
| `swift test -c release` | exit 0; 354 tests / 63 suites; 1.888 s execution |
| Swift 6 compilation/type checking | no compiler warnings/errors in either run |
| Supplemental `swift format lint` on changed Swift files | exit 0; identical 52 pre-existing style diagnostics before/after |
| `git diff --check` | exit 0 |
| `gitleaks git --log-opts='ea6171e..HEAD' --redact --no-banner` | exit 0; 19 commits; no leaks |

There is no configured project linter. The supplemental formatter configuration uses four-space indentation. Exact diagnostic message multiset compared equal; existing style diagnostics were not suppressed or reformatted. Release omits DEBUG-only fixture/capture-hook tests; pure gesture timing tests run in both configurations. Hook tests never open the user microphone or paste into user apps.

Review: Grok reviewed the complete meeting screen; GLM reviewed the complete dictation feature. Both initial verdicts were **ISSUES**, not OK. Confirmed lifecycle/late-callback/test-isolation issues were fixed and tested; speculative findings were reconciled with probes. No second external review is claimed for the fixes. Detailed meeting evidence: `2026-09-05-v2-meeting-loading.md` and `2026-09-05-meeting-review-followup.md`. Dictation red/green logs: `/tmp/granipa-dictation-gestures/`; review logs: `/private/tmp/granipa-{meeting-loading-review-grok,dictation-gestures-review-glm}.log`.

Native structural layout probe (not full production UI): an offscreen 700×500 NSHostingView with 2,000 rows initialized 2,000 row bodies with eager stacks versus **10** with the nested LazyVStack. An eager outer VStack did not defeat inner laziness in this probe; that review assertion was not treated as fact.

No storage schema, preference names, dependencies, identity, installed app or release publication changed. README already describes tap-toggle/hold-release; these fixes restore its stated behavior, so no durable documentation change is needed.

### Signed build and runtime smoke

- `Scripts/bundle.sh release`: exit 0; build 316.01 s, total 323.33 s. Normal non-testable release rebuild recompiles dependencies after release tests; this is build time, not application startup time.
- `build/Grañipa.app`: 26M; ARM64 executable UUID `E130DC86-6029-3EFF-B75A-1F573B9C46F7`; bundle version remains 1.0.4 (5).
- Host `codesign --verify --deep --strict`: valid, including Sparkle and nested helpers; Team `R4V252C833`, same Apple Development identity. No ad-hoc fallback.
- Old process 27164 normally terminated after Dictation showed enabled Record and no active Stop controls. New worktree build launched as PID 14881 and remained alive after the smoke.
- Read-only preferences check: `dictationKeyCode=54`, `dictationModifiers=0` (Right Command); preferences were not changed.
- Actual meeting selection: Meetings → first row → AXSelected confirmed **Overview=true**, AI Notes/Transcript/Action Items=false. Navigated AI Notes → Transcript → Action Items → Overview → AI Notes → Overview successfully. No recording, playback, meeting edits or clipboard writes were driven by the UI diagnostic.

| Action in new build | AX press-return | AX response after 250 ms |
| --- | ---: | ---: |
| Open first meeting | 0.145108084 s | 0.363190167 s |
| AI Notes, first entry | 0.112837292 s | 0.127336291 s |
| Transcript | 0.120547792 s | 0.028651125 s |
| Action Items | 0.090261291 s | 0.000217167 s |
| Overview | 0.091354042 s | 0.000297208 s |
| AI Notes, return | 0.127742791 s | 0.000255166 s |
| Overview, return | 0.099955208 s | 0.0002675 s |

The first-open follow-up AX request still took 0.363190167 s; this is **not** evidence of zero UI stalls or a finished performance audit. Action-return improved in this traversal, but no percentage/FPS improvement is claimed because caches and concurrent user activity were not controlled. Runtime log: `/private/tmp/granipa-loading-gestures-meeting-smoke.log`.

Immediately after navigation, ps reported 13.7% CPU. A later settled read reported 0.0% CPU and RSS 102608 KB. The intervening 5-second sample still included layout work and recorded 141.4M physical footprint / 148.2M peak; it is not a pristine idle benchmark. No RAM improvement is claimed.

The two temporary implementation worktrees were removed after clean integration; all commits remain recoverable in git. The main checkout and installed `/Applications` app were not modified. Build remains open in the integration worktree.

Physical keyboard plus spoken-audio confirmation remains separate from deterministic gesture tests. No claim that all V2 screens/features are finished.
