# Toolchain

Four environment traps, in the order you are likely to hit them. Check here
before debugging project code.

## 1. `incompatible tools version (6.4.0)`

```
xcodebuild: error: Could not resolve package dependencies:
  'generalizedmap' 0.1.0 contains incompatible tools version (6.4.0)
```

`GeneralizedMap` 0.1.0 declares `swift-tools-version: 6.4`. **No released Swift
toolchain can parse that** — the newest release is 6.3.3; 6.4 exists only as
`swift-6.4.x-DEVELOPMENT-SNAPSHOT` tags on `swiftlang/swift`.

The declaration is purely a gate. The package's source, and every file in this
project, compiles cleanly under 6.3.3 at `-swift-version 6` with full strict
concurrency.

**Fix:**

```sh
./scripts/bootstrap-dependency.sh
```

It clones `GeneralizedMap` at tag `0.1.0` into a sibling directory, rewrites the
manifest to `6.3`, and writes `SailingGMap.xcworkspace` so the local checkout
shadows the remote reference. `project.pbxproj` is never touched — the workspace
override is sufficient, and SwiftPM then never contacts GitHub for it.

**Open `SailingGMap.xcworkspace`, not `SailingGMap.xcodeproj`.** The bare
project still points at the unresolvable remote.

This shim is temporary. The permanent fix is upstream: retag `GeneralizedMap`
with a `6.3` manifest, after which the shim and this section can be deleted.

## 2. `xcodebuild requires Xcode, but active developer directory is a command line tools instance`

`xcode-select -p` is pointing at `/Library/Developer/CommandLineTools`.

Prefix rather than reconfiguring the machine:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …
```

Making it permanent (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
changes the active toolchain for every project on the machine — a deliberate
choice, not a build workaround.

## 3. Rosetta shells return nothing

On Apple Silicon a shell may be running translated (`sysctl -n
sysctl.proc_translated` → `1`, `uname -m` → `x86_64`). Symptoms:

```
xcrun: error: unable to load libxcrun (… missing compatible architecture
  (have 'arm64,arm64e', need 'x86_64'))
```

More insidiously, `nm` returns **zero symbols** from a perfectly good arm64
binary — which reads as "nothing was linked" when the build is fine.

```sh
arch -arm64 swift build
arch -arm64 nm -arch arm64 path/to/binary
```

## 4. Supported versions

| | Version |
|---|---|
| macOS deployment target (app) | 26.0 |
| Package platform floor | `.macOS(.v26)` |
| Known-good local | macOS 27.0, Xcode 26.6 (17F113), Swift 6.3.3, Apple M1 Max |
| CI runner | `macos-26` → Xcode 26.6 / Swift 6.3.3 — identical to local |

`macos-15` and older cannot work: no macOS 26 SDK, so the platform floor is
unsatisfiable.

## Verifying a clean setup

```sh
./scripts/bootstrap-dependency.sh
swift test --package-path Packages/SailingCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace SailingGMap.xcworkspace -scheme SailingGMap \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: tests green in seconds, `** BUILD SUCCEEDED **` with zero warnings.
