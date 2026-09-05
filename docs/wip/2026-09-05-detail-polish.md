# Detail polish — 2026-09-05

Base: `feat/granipa-v2@d54906e`. This is dated implementation evidence, not a
new product contract. Scope: the user's Home/Dictation consistency and detail
pass. Storage, providers, capture behavior and persistent settings stay unchanged.

## Acceptance defined before changes

- Home and idle Dictation keep the sidebar, heading and primary actions aligned
  at the same window dimensions. Retain live/meeting inspectors and compact access.
- Meaningful, legible navigation symbols; consistent primary/secondary controls,
  spacing and real-data metadata. No fabricated tags, graphs or metrics.
- Initial loading is not presented as empty data; query refresh and failure are
  explicit. Cancel work on disappearance. Paging must not mix query snapshots.
- Bounded local motion respects Reduce Motion; no decorative repeating work.
- Existing action wiring, tap/hold gestures, copy/paste and storage remain intact.
- Build/tests pass; signed bundle verified; scoped AX navigation and geometry
  measurements repeated. Do not claim pixel/FPS validation from AX timings.

## Verified baseline

- `swift test`: 390 tests / 67 suites, exit 0; test execution 5.104 s,
  wall time 9.04 s. Log: `/private/tmp/granipa-polish-baseline-tests.log`.
- Restricted first attempt failed writing the existing Clang module cache;
  authorized host execution passed. This was not a source/build regression.
- Worktree was clean, synced to origin; main was untouched. Base rebase in V2
  reported up to date. A preceding command addressed to main was rejected before
  execution; the corrected command explicitly targeted the V2 worktree.
- Current app PID 14881, measured window size 1249 × 866 points.
- Five-second idle sample: main thread waiting in the event loop, physical
  footprint 82.5M (process lifetime peak 177.0M); subsequent `ps` CPU 0.1%,
  RSS 89424 KB. A directly post-navigation 78.7% sample is not idle consumption.
- AX measurements (`/private/tmp/granipa-polish-baseline-geometry.log`):

| Element | Home x/y | Dictation x/y |
|---|---:|---:|
| Heading | 277 / 56 | 331 / 76 |
| Quick note | 967 / 61 | 660 / 90 |
| Record | 1099 / 60 | 798 / 89 |
| Sidebar Home | 10 / 145 | 10 / 165 |
| Sidebar Dictation | 10 / 178 | 10 / 198 |

Coordinates are relative to the window origin. The two navigation cycles gave
the same positions. This verifies a 20-point whole-sidebar vertical shift and
54-point heading horizontal shift, not only different screenshot framing.

## Audit and decisions

- Verified: `MainWindow.swift` conditionally inserts a toolbar control when an
  inspector kind exists; `AppNavigation.swift` selects `dictationIdle` even with
  no session. These coincide with different titlebar/column layout. Final fix
  must be checked against actual geometry, not assumed from source alone.
- Verified: `DestinationHeader.swift` is a title/actions row;
  `DictationLibraryChrome.swift` adds a 40-point mic tile, 14-point gap, subtitle
  and different action spacing. Unify the visual structure without changing
  meeting-versus-dictation recording actions.
- Verified: Home and Meetings both display `app.meetings`; Home additionally
  shows the next calendar event. Notes filters the same Meeting values for
  notes or non-recording/no-audio records. Files filters recording/audio values.
  Proposed: one Library with All / Notes / Recordings views. The user has been
  asked; do not remove access while the answer is pending.
- Verified: `DictationHistoryView.swift` initializes empty entries/zero stats,
  renders `emptyState` until the async fetch completes, and has no disappearance
  cancellation. GLM owns truthful loading/query-lifecycle fixes and tests.
- Verified: the inspector's 500 ms task catches cancellation with `try?` and
  continues based only on the recording phase. Risk inference: a disappearing
  live inspector could spin its cancelled task. Reproduce before claiming impact.
- Current tags work involving storage remains deferred. This pass only improves
  visual metadata already available in the existing data model.

## Implementation lanes

- Grok: shared shell, Home/libraries and Dictation chrome, isolated
  `fix/v2-polish-shell`.
- GLM: Dictation loading/filter lifecycle and inspector, isolated
  `fix/v2-polish-content`.
- Codex: orchestration, source audit, integration, measurements and signed build.
- Cross-family review occurs on the completed integrated screens, not each patch.

## Integrated changes

- `33e655b`: shared Home/Dictation title/action chrome, stable library toolbar
  occupancy, optional idle Dictation inspector, meaningful sidebar symbols,
  real-data metadata badges and locally scoped Reduce Motion-aware press motion.
- `b6bd875`, `3e38ab8`: explicit initial/refresh/error history states, last-good
  snapshots including empty results, cancellation and stale-query protection.
  Cancellation of the live inspector ticker now stops its loop. The prior busy
  loop was reproduced in a controlled test; this is not a measured app-wide CPU
  percentage. Inspector language/shortcut guidance and listening pulse improved.
- `2d8a415`: keep existing Overview content visible during enhancement, showing
  inline progress. The original worker commit was `79f5255`.
- `d55c361`: language availability has a real Checking state; cancellation and
  stale results cannot replace a newer check. Worker commit: `72cba8e`.
- `a8222dd`: shared primary/secondary controls across meeting and permissions
  screens, preserving existing action wiring. Worker commit: `0c4c796`.
- `42dbb79`: worker evidence for meeting/permissions; original `4ba55bc`.

No dependency, database schema, preference key, bundle identifier, capture gesture
or provider changes. Meetings/Notes/Files remain accessible pending the navigation
decision. New tags storage and integrations remain deferred. Source delta at
`42dbb79`: 1022 additions / 390 deletions, net +632 lines; tests: 723 additions /
41 deletions, net +682. This pass is not a LOC-reduction claim.

## Cross-family review

- Shell: GLM `VERDICT: OK`, with nits, in
  `/private/tmp/granipa-polish-shell-review.log`. Recording status remains in the
  Files row; removing its duplicate metadata did not remove that status.
- Dictation: Grok `VERDICT: ISSUES` in
  `/private/tmp/granipa-polish-content-review.log`. Empty-snapshot refresh/error,
  query-dependent empty copy and pulse restart were fixed in `3e38ab8` with
  regression tests. No second external OK verdict is claimed.
- Completed meeting/permissions screen: GLM `VERDICT: OK`, with nits, in
  `/private/tmp/granipa-polish-meeting-permissions-review.log`. Its worker report
  identifies the worker base `33e655b`; the integrated review base was `3e38ab8`.
- Kimi did not review: its bounded audit attempt returned HTTP 403 weekly quota.
  Grok performed the remaining-screen audit. No retries or review of each patch.
- Residual review nits: some source-text UI checks are implementation-coupled;
  an unused compatibility parameter remains. Neither blocks runtime behavior.

## Final verification, 2026-09-05 17:54 Europe/Madrid

| Measurement | Baseline `d54906e` | Integrated `42dbb79` |
|---|---:|---:|
| Debug tests / suites | 390 / 67 | 431 / 74 |
| Debug execution / wall seconds | 5.104 / 9.04 | 4.228 / 7.09 |
| Release tests / suites | Not repeated at baseline | 395 / 70 |
| Release execution / wall seconds | Not repeated at baseline | 2.244 / 219.62 |
| Signed app, `du -sh` | 26M | 27M |
| Direct dependencies | 3 | 3 |
| Supplemental format diagnostics, changed Swift files | 102 | 56 |

Debug wall times include incremental build; Release wall time includes compilation.
These single-run values are evidence, not a statistically measured speedup.

- `swift test` full final rerun: exit 0, 431 tests / 74 suites. Log:
  `/private/tmp/granipa-polish-final-debug-rerun.log`.
- Important: the preceding full Debug run failed one timing assertion in
  `cancelledWaitReportsStop`: 1.5050649642944336 seconds against <1 second. Its
  stop-result assertion passed. The unchanged full suite then passed; no assertion
  was weakened, removed or skipped. Resource contention is an unverified cause;
  the timing flake remains a residual risk. Failed-run log:
  `/private/tmp/granipa-polish-final-debug.log`.
- `swift test -c release`: exit 0, 395 tests / 70 suites. Log:
  `/private/tmp/granipa-polish-final-release.log`. Different counts reflect
  configuration-conditional tests, not newly skipped tests.
- Swift 6 compiler/type-check passes; no compiler warning/error diagnostics in
  the successful final test logs. `git diff d54906e..HEAD --check`: exit 0.
- No configured project linter. Supplemental `swift format lint`, four-space
  configuration, exited 0 with 56 diagnostics versus 102 on the same baseline
  files. The four GLM-touched files have zero diagnostics. Do not call this a
  zero-warning whole-repo lint result.
- `gitleaks git --log-opts='d54906e..HEAD' --redact --no-banner`: seven commits
  scanned, no leaks. No project dependency-audit command is configured; no
  dependency vulnerability verdict is claimed.
- `Scripts/bundle.sh release`: exit 0, build 165.52 seconds, total 172.85 seconds.
  Log: `/private/tmp/granipa-polish-final-bundle.log`.
- Host `codesign --verify --deep --strict build/Grañipa.app`: exit 0. App and
  Sparkle both have Team ID `R4V252C833`, Apple Development identity. Hardened
  runtime retained. No ad-hoc signing or installation into `/Applications`.
- Previous app PID 14881 quit normally after an idle-capture check. Recoverable
  copy: `/private/tmp/granipa-polish-backup.QEYW9d/Grañipa.app`.
- New signed Release launched, PID 70849. Five-second sample at 17:52 shows all
  main-thread samples waiting in the event loop, not a startup hang. Physical
  footprint 43.8M, peak 97.5M. This is not comparable to baseline memory because
  the session/window conditions and process lifetimes differ.

## Remaining acceptance check — blocked by locked desktop

Final host diagnostic verified `CGSSessionScreenIsLocked=true` and launch complete.
Accessibility returns no actionable main-window controls in this state. Two
Home/Dictation geometry attempts were therefore inconclusive; the search smoke
did not execute. The app is running, but final geometry, navigation, search and
meeting-tab smoke must be repeated after the user unlocks the Mac. No final
pixel, animation/FPS, full speech/paste end-to-end or measured whole-app fluidity
claim is made. The new build is available for testing, not declared fully accepted.

After unlocking, run the prepared geometry/search/navigation helpers against the
exact V2 bundle; compare with the 1249 × 866-point baseline. Do not expand this
delivery with further features. Unmeasured waveform rendering ideas remain
proposals. There is no CONTEXT.md in this worktree; no new durable doc was created.
