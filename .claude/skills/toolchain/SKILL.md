---
name: toolchain
description: Build and toolchain troubleshooting for SailingGMap — the GeneralizedMap swift-tools-version 6.4 resolution failure, xcode-select pointing at Command Line Tools, Rosetta shells producing empty binary-inspection results, and which SDK/runner combinations actually work. TRIGGER when a build or package resolution fails, when xcodebuild or swift is not found, or when setting up CI. DO NOT trigger for test failures, compile errors in project source, or runtime bugs — those are code problems, not toolchain problems.
---

# Toolchain runbook

Four known environment traps. Check here before debugging project code.

## 1. `incompatible tools version (6.4.0)` — the big one

```
xcodebuild: error: Could not resolve package dependencies:
  'generalizedmap' 0.1.0 contains incompatible tools version (6.4.0)
```

**Cause.** `GeneralizedMap` 0.1.0's `Package.swift` declares
`swift-tools-version: 6.4`. No released Swift toolchain can parse that — the
newest release is **6.3.3**; 6.4 exists only as
`swift-6.4.x-DEVELOPMENT-SNAPSHOT` tags on `swiftlang/swift`.

**It is purely declarative.** The package's source compiles cleanly under
6.3.3, and so does every file in this project, at `-swift-version 6` with full
strict concurrency.

**Fix.**

```bash
./scripts/bootstrap-dependency.sh
```

That clones the package next to the repo, rewrites the manifest to `6.3`, and
leaves a `SailingGMap.xcworkspace` that shadows the remote reference with the
local checkout. `project.pbxproj` is never modified — the workspace override is
enough, and SwiftPM then never contacts GitHub for it.

Open **`SailingGMap.xcworkspace`**, not `SailingGMap.xcodeproj`. The bare
project still points at the unresolvable remote.

**Permanent fix** is upstream: retag `GeneralizedMap` with a `6.3` manifest,
then delete the shim and this section.

## 2. `xcodebuild requires Xcode, but active developer directory is a command line tools instance`

`xcode-select -p` points at `/Library/Developer/CommandLineTools`.

**Don't** run `sudo xcode-select -s` unasked — that changes the machine's
active toolchain for every project, and it's the user's call. Prefix instead:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …
```

Or call the binary directly:
`/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`.

If the user wants it permanent, hand them the command to run themselves.

## 3. Rosetta shells silently return nothing

Agent shells on Apple Silicon may run translated (`sysctl -n
sysctl.proc_translated` → `1`, `uname -m` → `x86_64`). Symptoms:

```
xcrun: error: unable to load libxcrun (… missing compatible architecture
  (have 'arm64,arm64e', need 'x86_64'))
```

…and, more insidiously, `nm` returning **zero symbols** from a perfectly good
arm64 binary. That reads as "nothing is linked" when everything is fine.

Prefix architecture-sensitive tools with `arch -arm64`:

```bash
arch -arm64 swift build
arch -arm64 nm -arch arm64 path/to/binary
```

If a binary-inspection result looks impossibly empty, suspect this before
suspecting the build.

## 4. Which SDK / runner actually works

| | Version |
|---|---|
| Minimum macOS (app target) | 26.0 |
| Package platform floor | `.macOS(.v26)` (GeneralizedMap) |
| Known-good local | macOS 27.0, Xcode 26.6 (17F113), Swift 6.3.3, Apple M1 Max |
| CI runner | `macos-26` → Xcode 26.6 / Swift 6.3.3 — **identical to local** |

`macos-15` and older will not work: no macOS 26 SDK, so the package's platform
floor can't be satisfied.

## Verifying a clean setup

```bash
./scripts/bootstrap-dependency.sh
swift test --package-path Packages/SailingCore     # headless, no Xcode needed beyond the SDK
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace SailingGMap.xcworkspace -scheme SailingGMap \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `swift test` green in a few seconds; `** BUILD SUCCEEDED **` with
zero warnings.
