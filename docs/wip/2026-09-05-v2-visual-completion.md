# V2 visual completion — 2026-09-05

## User direction

The user postponed bookmarks, tags and standalone tasks to try the existing build.
After testing it, the user confirmed improvement but rejected visual completion.
This supersedes the earlier tentative approval to begin additive local tables:
no new persistence work is included in this pass. No claim of completed V2.

## Verified starting point

- Branch `feat/granipa-v2`, code baseline `2c6929b`, synced with origin.
- Fresh `swift test`: 317 tests / 55 suites pass, execution 0.680 seconds.
  Log: `/private/tmp/granipa-v2-visual-baseline-tests.log`.
- Source gaps: serif `Theme.titleFont`; default1120 hides inspector under1280;
  Home's no-calendar header is Notes; shared Dictation header starts a meeting;
  bare grouped statistics and sparse library rows; meeting overview capped720.
- These are source inspections, not screenshot-based certification of this build.
  Current visual screenshot requested from the user; reference screenshots inspected.
- Official Kimi attempt failed with HTTP403 weekly quota. No substitute endpoint used.

## Implementation boundaries and acceptance

- Grok: shared theme, shell/sidebar, headers, Home/Notes/Files composition.
- GLM: Dictation capture action and visual hierarchy, metric tiles, cards, inspectors.
- Grok separate lane: recorded-meeting header/player/tabs/transcript and live-stage layout.
- Preserve existing storage/API/credentials/audio-engine behavior and tests.
- No invented billing, participants, connected providers, accuracy, trends or timestamps.
- No new dependencies; no permanent animated decoration or extra audio polling.
- Build and full suite on integration; one cross-family review per integrated screen group.
- Visual/runtime smoke is separate from compilation. Any unavailable gate stays explicit.

## User clarification after this pass started

The user supplied eleven more reference images and explicitly requested tags again,
live dictation in the contextual panel, and Settings as an in-app screen rather
than a second window. This supersedes deferral of tags above. Settings entry points
must converge on the same main-window destination, without duplicate sidebars.
The references also emphasize decisions/outcomes, owned actions, key moments and
a chapter timeline. Automatic versus manual moment creation was asked separately;
video thumbnails remain unsupported by the audio-only capture path.

Implementation order: integrate the in-flight visual groups; embed Settings; add
real local tags with independent test-author coverage before implementation.
No new persisted fields are added to Meeting or DictationEntry JSON contracts.
Migration tests use ephemeral databases only. Applying a new migration to the
user's actual database remains a human action, not an unattended app launch.
