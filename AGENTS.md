# AGENTS.md — SailingGMap

macOS SwiftUI experiment that gives a precise mathematical home to an old
sailing intuition: flip alternating tacking strips end-to-end and the zig-zag
path becomes a straight line. Reflection unfolding straightens the path, a
generalized map (`GeneralizedMap` package) records strip topology, and a
continuous progress field extends straight strips to curved foliations.

This file is the canonical guide for **any** coding agent (Claude Code, Cursor,
Codex, Copilot, …) and for humans — the single source of truth for conventions
and workflow. Claude Code reads it via an `@AGENTS.md` import in `CLAUDE.md`,
which adds only the Claude-Code-specific mechanics (skill catalog, memory).
References to `/name` below are Claude Code skill shortcuts; the behavior they
wrap is described inline or in `docs/`, so any agent can follow the rule
without them.

---

## Top rules — read first

- **A mathematical claim is not true until a falsifiable test says so.** This is
  the rule this repo exists to enforce; see [The falsifiability
  rule](#the-falsifiability-rule) below. It is not a style preference — every
  defect this project has shipped was a doc comment that described correct
  mathematics sitting above code that did something else.
- **Follow TDD: failing test → implement → green → lint.** Write the red test
  first, and *watch it fail for the right reason* before implementing.
- **Never push directly to `main`.** All changes land through a merged PR on a
  feature branch.
- **Always include `Closes #N`** (or `Fixes #N`) in the PR body so the tracker
  stays clean.
- **Changes under `Packages/SailingCore/Sources/SailingCore/Mathematics/`
  require a structured spec before implementation** — see [Risk
  tiers](#risk-tiers).
- **Never weaken a test to make it pass.** If a tolerance needs loosening, say
  why in the PR body and justify the number. Silent epsilon inflation is how a
  correctness regression ships green.

### Judgment rules (not just process)

- **Surface assumptions before building.** If a task is underspecified, state
  the assumption you are proceeding on rather than silently guessing.
- **Stop and ask when the mathematics and the code disagree.** Do not "fix" the
  comment to match the code, and do not assume the comment is right either.
  Derive it, then decide which one is wrong, then say so in the issue.
- **Push back when warranted.** A worse plan you were handed is still worse.
- **Prefer boring, obvious solutions.** This is a pedagogical artifact — a
  reader should be able to follow the code from the mathematics.
- **Touch only what you are asked to touch.** No drive-by refactors; they widen
  the blast radius and bury the actual change in the diff.

---

## The falsifiability rule

The defining bug of this codebase looked like this:

```swift
/// The classic "billiard unfolding" of a tacking path.  We reflect every
/// down-going (σ = −1) leg across the horizontal line n = n_i …
public static func unfoldByHorizontalReflections(of path: TackPath) -> [Point2D] {
    for strip in path.strips {
        s̃ += w; ñ += w * tanθ          // ← never reads strip.tack
        vs.append(Point2D(x: s̃, y: ñ))
    }
}
```

It emits a straight line by construction. The companion check —
`unfoldedIsStraight(_:)` — then verified that straight line was straight. Both
the function and its test were "passing" for every input, including a path that
missed the destination by the entire course length.

**Therefore: every test of a mathematical claim must include a negative
control** — an input for which the property is *false*, asserted to be
rejected. A test suite that cannot fail is documentation with extra steps.

| Claim under test | Positive case | **Required negative control** |
|---|---|---|
| Alternating tacks unfold straight | uniform alternating path → straight | all-same-tack path → **not** straight |
| Sailed length is `L / cos θ` | uniform strips → matches closed form | θ → π/2 → diverges, not silently clamped |
| Seam is reflective iff tack flips | alternating → all seams reflective | constant tack → **zero** reflective seams |
| Progress field is monotonic | `amp` below bound → 0 violations | `amp` above bound → **> 0** violations |
| Path arrives at B | balanced strips → arrival offset ≈ 0 | odd strip count → arrival offset ≠ 0 |

If you cannot construct the negative control, you do not yet understand the
claim well enough to test it.

---

## Stack & tooling

| Concern | Tool |
|---|---|
| Language | Swift 6 (language mode `.v6`, strict concurrency) |
| UI | SwiftUI, macOS 26+ |
| Core math | `Packages/SailingCore` — a local SPM package, **no UI imports** |
| Topology | [`GeneralizedMap`](https://github.com/SinanKarasu/GeneralizedMap) via SPM |
| Testing | **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest |
| Lint | `swiftlint` (config in `.swiftlint.yml`) |
| Format | `swift-format` (config in `.swift-format`) |
| CI | GitHub Actions, `macos-26` runner (Xcode 26.6 / Swift 6.3.3) |

<important if="the build fails to resolve GeneralizedMap">
**Known toolchain gotcha.** `GeneralizedMap` 0.1.0 declares
`swift-tools-version: 6.4`, which no released Swift toolchain can parse — the
newest release is 6.3.3. Resolution fails with:

```
'generalizedmap' 0.1.0 contains incompatible tools version (6.4.0)
```

Nothing in either project actually requires 6.4. `scripts/bootstrap-dependency.sh`
checks out the package and rewrites the manifest to `6.3`; CI runs it
automatically. See [docs/toolchain.md](docs/toolchain.md) (Claude Code:
`/toolchain`). Delete the shim once the package is retagged upstream.
</important>

---

## Project structure

```
Packages/SailingCore/            # ALL mathematics — pure Swift, no SwiftUI
  Sources/SailingCore/
    Models/                      #   Geometry, Wind, Strip, TackPath
    Mathematics/                 #   Unfolding, ProgressField, Foliation,
                                 #   GeneralizedTackPath, Optimization, Topology
  Tests/SailingCoreTests/        #   Swift Testing; runs headless via `swift test`
SailingGMap/                     # the app — Views + ViewModel ONLY
  SailingGMapApp.swift           #   entry point
  ContentView.swift              #   split-view layout
  ViewModels/                    #   SailingGMapViewModel (@MainActor)
  Views/                         #   ControlsView, SailingGMapCanvasView
SailingGMap.xcodeproj/           # app target; depends on Packages/SailingCore
docs/                            # specs, toolchain notes, design decisions
docs/specs/                      # structured specs, one per Critical-tier change
scripts/                         # bootstrap-dependency.sh, lint.sh
```

Use `ls` / `tree` for detail — don't ask the docs to enumerate every file.

---

## Common commands

```bash
./scripts/bootstrap-dependency.sh        # one-time: fix the GeneralizedMap manifest

swift test --package-path Packages/SailingCore          # all math tests, headless
swift test --package-path Packages/SailingCore --filter UnfoldingTests

./scripts/lint.sh                        # swiftlint + swift-format --lint
swift-format format -i -r Packages SailingGMap          # apply formatting

# Full app build (needs Xcode, not just CLT):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SailingGMap.xcodeproj -scheme SailingGMap \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

All three gates — `swift test`, `swiftlint`, `swift-format --lint` — must pass
before a PR.

---

## Architecture principles

- **`SailingCore` never imports SwiftUI or AppKit.** The mathematics must be
  runnable, and therefore testable, without a window server. This is what makes
  CI fast and reliable; do not break it for convenience.
- **The `GeneralizedMap` boundary is exactly one file.** `import GeneralizedMap`
  appears only in `Mathematics/SailingGMapTopology.swift`. Every dart, orbit,
  cell, sewing, and attribute operation goes through that adapter. Keep it that
  way — it is the project's headline architectural claim.
- **Two coordinate frames, never mixed.** World `(x, y)` and course `(s, n)`.
  `CourseAxis.toCourse` / `.fromCourse` are the only bridges. A function that
  takes a `Point2D` must state which frame it is in.
- **Value types with explicit conformances.** `Hashable`, `Codable`, `Sendable`
  where the type is genuinely a value. Reference types only where the package
  API forces it (`GMap` is a class).
- **The ViewModel derives; the Views draw.** No arithmetic in a `View` beyond
  coordinate transforms to screen space. No `Canvas` code recomputing something
  the ViewModel already has.
- **Derived state is cached, not recomputed per redraw.** SwiftUI calls `body`
  far more often than you think.

### Sign and frame conventions

These are load-bearing; getting one backwards produces plausible-looking
garbage. See `/math-invariants` for the full set.

| Symbol | Meaning |
|---|---|
| `u` | unit vector along `A → B`; the along-course (`s`) axis |
| `n` | `u` rotated **90° counter-clockwise**; the cross-track axis, positive to **port** |
| `σ ∈ {+1, −1}` | tack sign; `.starboard = +1`, `.port = −1` |
| `θ` | tacking half-angle **off the course axis** (not off the wind) |
| heading in strip `i` | `(cos θ, σᵢ · sin θ)` in course coordinates |
| `WindModel.fromDirection` | direction the wind blows **from**; head-to-wind means pointing along it |

---

## Coding conventions

Most style is enforced by `swiftlint` + `swift-format` — don't restate those
rules here. The non-enforceable ones:

- **Doc comments state the mathematics, and the mathematics must be true.** If
  you change behavior, update the derivation in the header comment in the same
  commit. A stale derivation is a latent bug (see [the falsifiability
  rule](#the-falsifiability-rule)).
- **Unicode identifiers are idiomatic here** (`θ`, `σ`, `n̂`, `û`, `s̃`). The
  existing code uses them deliberately so the code reads like the paper. Match
  it; don't ASCII-ify.
- **Every magic number gets a derivation.** `1e-9` in a straightness check needs
  a comment saying what it is relative to. Prefer named constants with units.
- **Guard degenerate cases explicitly** — `cos θ → 0`, `|∇s| → 0`, zero-length
  axis, empty strip array. Return a documented sentinel or throw; never fall
  through to `NaN`.
- **No side effects inside `precondition`.** `precondition(map.sew(...))`
  silently stops sewing under `-Ounchecked`. Assign first, then assert.

---

## Testing

- **Swift Testing, not XCTest.** `@Test`, `#expect`, `#require`,
  `@Test(arguments:)` for parameterized cases.
- **Every test file mirrors a source file**: `Unfolding.swift` →
  `UnfoldingTests.swift`.
- **Negative controls are mandatory** for any test of a mathematical property
  (see the table above).
- **Parameterize over the interesting domain**, not one lucky value:

  ```swift
  @Test(arguments: [2, 4, 8, 16, 32], [15.0, 30.0, 45.0, 60.0])
  func sailedLengthMatchesClosedForm(n: Int, degrees: Double) { … }
  ```

### Floating-point tolerance policy

No bare `#expect(a == b)` on `Double`, and no unexplained epsilons.

| Situation | Tolerance | Rationale |
|---|---|---|
| Closed-form identity (e.g. `L / cos θ`) | relative `1e-12` | double precision, a handful of ops |
| Accumulated over `N` strips | relative `1e-9` | `N ≤ 64` roundings |
| Numerically integrated trajectory | **relative `1e-3`, and assert the error bound itself** | forward Euler is O(h); the test should pin the convergence order, not paper over it |
| Angle comparisons | absolute `1e-9` rad | near-zero angles make relative error meaningless |

Use the `Approx` helpers in `Tests/SailingCoreTests/Support/`. If a test needs a
tolerance outside this table, justify it in a comment on the assertion.

---

## Do / Don't

| Do | Don't |
|---|---|
| Write the failing test first and watch it fail. | Write the code, then a test that ratifies whatever it does. |
| Include a negative control for every mathematical property. | Assert only the happy path — that's how the unfolding bug survived. |
| Keep `SailingCore` free of SwiftUI/AppKit imports. | Reach for `Color` or `CGPoint` conveniences inside the math. |
| Route all G-map calls through `SailingGMapTopology.swift`. | `import GeneralizedMap` anywhere else. |
| Update the header derivation in the same commit as the behavior. | Leave a doc comment describing the old (or aspirational) behavior. |
| Cache derived state on the ViewModel. | Recompute level curves or integrate the trajectory inside `body`. |
| Name the frame in every signature that takes a `Point2D`. | Pass `(s, n)` into something expecting `(x, y)`. |
| Assign a result, then `precondition` on it. | Put a mutating call inside `precondition`. |
| Land changes via a merged PR with `Closes #N`. | Push to `main`. |

---

## Risk tiers

| Tier | Paths | Extra requirements |
|---|---|---|
| **Critical** | `Mathematics/Unfolding.swift`, `Mathematics/SailingGMapTopology.swift`, `Mathematics/ProgressField.swift`, `Mathematics/GeneralizedTackPath.swift` | Structured spec before implementation (`/spec`) + negative-control tests + a stated tolerance justification |
| **High** | `Models/*.swift`, `Mathematics/Foliation.swift`, `Mathematics/Optimization.swift` | Negative-control tests; spec if the change alters an invariant |
| **Normal** | `SailingGMap/Views/`, `SailingGMap/ViewModels/` | Standard TDD |
| **Low** | docs, CI, skills | Review only |

<important if="touching Unfolding.swift / SailingGMapTopology.swift / ProgressField.swift / GeneralizedTackPath.swift">
**Critical-tier change.** Required before you write any implementation:
a structured spec (`/spec`, posted to the issue and approved), negative-control
tests, and an explicit tolerance justification for every floating-point
assertion. See [docs/risk-tiers.md](docs/risk-tiers.md).
</important>

---

## Where to look next

- **Invariants that must hold across the whole system** (unfolding length
  invariance, Euler characteristic, involution laws, monotonicity bound):
  [docs/invariants.md](docs/invariants.md) — Claude Code: `/math-invariants`.
- **Toolchain gotchas** (the `6.4` manifest, `DEVELOPER_DIR`, Rosetta shells):
  [docs/toolchain.md](docs/toolchain.md) — Claude Code: `/toolchain`.
- **Risk tiers and spec formats:** [docs/risk-tiers.md](docs/risk-tiers.md).
- **Structured specs, one per Critical change:** [docs/specs/](docs/specs/).
- **The mathematics itself:** the `README.md` derivations are the reference, and
  each source file's header comment is the local statement of what it proves.
  When they disagree with the code, the code is what shipped — file an issue.
- **Upstream package API:** `GeneralizedMap` sources are the source of truth for
  `createRing`, `sew`, `numberCells`, and attribute containers. `sew(_:_:alpha:)`
  propagates along the sewing orbit, so sewing one dart pair at α₂ sews the whole
  edge — do not hand-roll that.
