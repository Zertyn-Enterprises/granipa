# Integrated-screen review — Grok, 2026-09-05

Root attached the complete-screen review while GLM addresses lifecycle findings.
Review source: `/private/tmp/granipa-meeting-loading-review-grok.log`.
Verdict: ISSUES. Not a completion claim. No new product scope.

Confirmed overlap with the active follow-up: ticking before engine.play, nil/missing paths not releasing old audio, stale asynchronous completions. The review also flags missing-path channel changes not invalidating an in-flight replacement.

Additional UI findings to reconcile before integration:

- The first AI Notes frame sees empty `document.blocks` because the prefix is populated in `.task`. Show genuine preparing feedback until the first prepared content, and do not flash previous source content while a re-enhance invalidates it. Avoid any artificial delay.
- Grok inferred that nesting MarkdownBlocksView's LazyVStack inside EnhancedNotesView's eager VStack defeats bounded row realization. Verify actual layout behavior or eliminate the eager parent so the long document remains lazy in its real scroll container. Do not equate a type name with measured laziness.
- EOF tests should distinguish real engine progress/EOF from a false `.ended` state; channel-switch tests should verify the old underlying playback stops, not only immediate UI flags.

Evidence correction from root arithmetic: the old benchmark failure is `entryNs * 8 = 733799672`, so the actual entry was **91724959 ns (91.724959 ms)**, not 733.8 ms. `fullNs = 84840000` is 84.84 ms. Correct the historical measurement wording; do not claim a measured new entry duration from a boolean ratio test alone.

## Native layout probe from root

Root ran `/private/tmp/granipa-lazy-layout-probe.swift`, an offscreen NSWindow + NSHostingView with a 700×500 ScrollView, summary, 2,000 synthetic rows and footer. Results (`/private/tmp/granipa-lazy-layout-probe.log`):

| Outer stack | Inner rows stack | Row initializations | Row bodies | Appearances |
| --- | --- | ---: | ---: | ---: |
| VStack | VStack | 4000 | 2000 | 2000 |
| VStack | LazyVStack | 20 | 10 | 10 |
| LazyVStack | LazyVStack | 20 | 10 | 10 |

Therefore Grok's assertion that an outer VStack necessarily forces every nested LazyVStack row to realize is **not reproduced** on this Mac. This is a synthetic structural probe, not a production-frame-rate test; it does not reproduce every Markdown modifier. Do not present the reviewer's inferred generalization as a confirmed bug or require an outer-stack rewrite solely on that basis. Loading/stale-source presentation still needs its own reconciliation.
