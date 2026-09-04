# Grañipa optimization baseline — 2026-09-04

Baseline commit: `chore/optimize-2026-09-04@c10dbb8`

The branch was created from `main@bd05f9d` and fast-forwarded to the current
pre-redesign checkpoint, which is the build the user was testing.

## Build, type-check, and tests

| Gate | Command | Exit | Result |
|---|---|---:|---|
| Clean debug build and type-check | `/usr/bin/time -p swift build --scratch-path ../../../.build --skip-update -c debug` | 0 | 27.09 s wall; SwiftPM reported 26.78 s |
| Full tests | `/usr/bin/time -p swift test --scratch-path ../../../.build --skip-update` | 0 | 177/177 tests in 37 suites; 0 skipped; 10.02 s wall; test runtime 0.657 s |
| Script syntax: bundle | `bash -n Scripts/bundle.sh` | 0 | Valid shell syntax |
| Script syntax: release | `bash -n Scripts/release.sh` | 0 | Valid shell syntax |

The build emitted 520 warning records from 26 unique source locations. Swift
batch compilation repeated each location ten times. The unique warnings are 22
actor-isolation/sendability warnings in `PanelMotion.swift` and four redundant
`await` warnings in `MuseSystemTranscriber.swift`. Test compilation added two
unique `var`-was-never-mutated warnings. There were zero compiler errors.

There is no project lint configuration and no installed `swiftlint`,
`periphery`, `shellcheck`, or `shfmt`, so no repository-defined lint command
exists. `swift format 6.3.0` is installed but is not configured as a project
gate; inventing a new formatting policy would not be a baseline measurement.

The first isolated build attempt did not reach compilation. SwiftPM downloaded
134.96 MiB of FluidAudio over 875.15 s, then failed with `RPC failed; curl 56
Recv failure: Operation timed out` and `fatal: early EOF`. The successful build
used the already resolved local dependency checkouts after `swift package
--scratch-path ../../../.build clean`; its 27.09 s figure therefore measures a
clean compile, not dependency download time.

Logs:

- `/tmp/granipa-opt-baseline-build.time`
- `/tmp/granipa-opt-baseline-build-local.log`
- `/tmp/granipa-opt-baseline-build-local.time`
- `/tmp/granipa-opt-baseline-test.log`
- `/tmp/granipa-opt-baseline-test.time`

## Size

| Metric | Baseline |
|---|---:|
| Production Swift | 14,143 LOC in 99 files |
| Test Swift | 2,182 LOC in 32 files |
| Test declarations | 177 `@Test` in 37 `@Suite` declarations |
| `Sources/` | 728 KiB |
| `Tests/` | 156 KiB |
| `Resources/` | 1,884 KiB |
| Repository checkout excluding generated build output | 3,300 KiB |
| SwiftPM scratch directory after clean build/tests | 1,496,832 KiB |
| Debug `Granipa` executable | 29,091,184 bytes |
| Debug `GranipaBatteryHelper` executable | 207,040 bytes |
| Direct dependencies | 3 |
| `node_modules` / `.venv` / `venv` | Not present |

Resolved direct dependencies:

- GRDB `7.11.0`
- FluidAudio `0.15.2`
- Sparkle `2.9.3`

Each dependency has a verified production import: GRDB in storage/models,
FluidAudio in diarization, and Sparkle in `UpdaterManager`.

## Bundle and cold start

`Scripts/bundle.sh` has no `--help` or `--dry-run` mode. It recompiles, replaces
`build/Grañipa.app`, accesses the signing identity, and signs the result. Execution
was rejected by the environment because signing can alter TCC identity state.
The exact baseline bundle size and cold launch-to-ready time are therefore not
measured yet. The raw debug executables above are exact artifacts from
`c10dbb8`; `/Applications/Grañipa.app` was excluded because it contains later
uncommitted fixes and is not byte-identical to the baseline.

The user supplied a verified crash report for the baseline startup path:
`BatteryHelperClient.proxy(reply:)` traps on the XPC reply queue because its
error callback is main-actor isolated. This is tracked as a bug-fix item before
optimization.

## Script audit

- `Scripts/bundle.sh`: read in full and syntax-checked. It has no safe inspection
  flag. Its intended mutations are a Swift build, replacement of the local app
  bundle, framework embedding, and code signing.
- `Scripts/release.sh`: read in full and syntax-checked. It has no safe inspection
  flag. It builds/signs, submits to Apple notarization, staples, creates a ZIP,
  opens Archive Utility, and generates an appcast. It prints but does not execute
  the final `gh release create` command. It was not run.
- No `package.json`, `Makefile`, `Justfile`, or other executable project scripts
  were found. Correction recorded during Phase 4: `.github/workflows/ci.yml`
  already existed at `c10dbb8` and runs `swift build` followed by `swift test`.

## Reproduction commands

```sh
find Sources -name '*.swift' -type f -print0 | xargs -0 wc -l
find Tests -name '*.swift' -type f -print0 | xargs -0 wc -l
find Sources -name '*.swift' -type f | wc -l
find Tests -name '*.swift' -type f | wc -l
rg -n '@Test' Tests | wc -l
rg -n '@Suite' Tests | wc -l
du -sk . Sources Tests Resources docs/wip
du -sk ../../../.build
stat -f '%z %N' ../../../.build/arm64-apple-macosx/debug/Granipa
stat -f '%z %N' ../../../.build/arm64-apple-macosx/debug/GranipaBatteryHelper
rg -n '^import (GRDB|FluidAudio|Sparkle)$' Sources Tests
rg -n '\.disabled|\.skip|XCTSkip|@Test\([^\n]*disabled' Tests Package.swift
```
