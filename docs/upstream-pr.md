# Making SailingGMap buildable, testable, and correct

You offered to hand this off — I'm happy to take it, and this is the state I'd
be taking it over in. Merge it, ignore it, or transfer the repo and I'll carry
it from my fork; all three work.

This branch does three things, in this order and for that reason:

1. **Makes the project buildable** on a released Swift toolchain.
2. **Makes the mathematics testable**, then tests it.
3. **Fixes the five defects the tests found** — one of which was not the defect
   we thought it was.

Every claim below was measured, and the measurement is pasted in. Nothing here
is "should be faster" or "looks correct."

---

## 0. Up front: this was AI-assisted, and it got one thing wrong

Claude Code performed the analysis, wrote the code, and drafted these notes.
That matters because the first pass produced a **confident, wrong bug report**,
and the way it was caught is the best argument for everything else in this PR.

The claim was that `unfoldByHorizontalReflections` was faked because it never
reads `strip.tack`. Writing the correct implementation from the derivation
produced **bit-identical output** for every tack sequence:

```
alternating [S,P,S,P]:
   original zig-zag : (0,0) (25,25) (50,0) (75,25) (100,0)
   shipped unfold   : (0,0) (25,25) (50,50) (75,75) (100,100)
   correct unfold   : (0,0) (25,25) (50,50) (75,75) (100,100)   identical

constant [S,S,S,S] / mixed [S,S,P,P] / mixed [S,P,P,S]:         identical
```

The unfolding reflects every leg to point the same way, so the lift is
`(0,0) → (L, L·tan θ)` **regardless of the tacks**. The closed form is exact and
correctly does not need `strip.tack`. The proposed "negative control" was false
on its face: a constant-tack path in course coordinates is already a straight
line.

The bug report was filed, disproved by its own spec, and closed as invalid. The
narrower defect that survived scrutiny is in §4.

---

## 1. The toolchain gap you already flagged

You called this one before I hit it — the tools version wanting to come down
from 6.4 to 6.3. For the record of *why* it's a hard stop rather than a
nuisance: **Swift 6.4 has not shipped.** The newest release tag on
`swiftlang/swift` is `swift-6.3.3-RELEASE`; 6.4 exists only as
`swift-6.4.x-DEVELOPMENT-SNAPSHOT`. So resolution fails outright rather than
warning:

```
xcodebuild: error: Could not resolve package dependencies:
  'generalizedmap' 0.1.0 contains incompatible tools version (6.4.0)
```

Nothing actually needs 6.4. Both projects compile clean on 6.3.3 at
`-swift-version 6` with full strict concurrency.

`scripts/bootstrap-dependency.sh` handles it: clone the package, rewrite the
manifest, commit and tag it locally as `0.1.1`, and write an `.xcworkspace` in
which the local checkout shadows the remote reference.

Two non-obvious constraints it encodes, both found the hard way:

- **The checkout directory must be named exactly `GeneralizedMap`.** Xcode
  matches a workspace-local package to the reference it shadows by *package
  name*, derived from the directory. A differently-named directory resolves as
  an unrelated package and the remote is fetched anyway.
- **Patching the working tree is not enough.** SwiftPM resolves a versioned
  dependency by checking out a **tag**, so the 6.4 manifest at `0.1.0` is what
  actually gets read. Hence the local `0.1.1` tag.

The payoff is that `Package.swift` stays honest — it declares the real upstream
dependency, not a vendored copy or a path into somebody's home directory:

```swift
.package(url: "https://github.com/SinanKarasu/GeneralizedMap.git", from: "0.1.0")
```

**A one-line PR to `GeneralizedMap` accompanies this one** — that is the real
fix, and merging it makes this shim deletable. Its own XCTest suite passes
unchanged on 6.3.3. Given you've said GeneralizedMap is the one that matters to
you, that PR is the one worth two minutes; everything here can wait.

---

## 2. The mathematics is now testable — 103 tests in 96 ms

`Models/` and `Mathematics/` moved to `Packages/SailingCore`, a local SPM
package. They had no UI dependency; they were in the app target by historical
accident, which made them untestable without a test host and a window server.

```
$ swift test --package-path Packages/SailingCore
✔ Test run with 103 tests in 11 suites passed after 0.096 seconds.
```

The layering claim in the README is now **mechanically enforced** rather than
aspirational. `scripts/lint.sh` asserts, in CI:

```
==> layering: SailingCore imports no UI framework
==> layering: GeneralizedMap boundary is exactly one file
```

Both were true. Nothing kept them true.

### CI

Four jobs on `macos-26` (Xcode 26.6 / Swift 6.3.3 — the same toolchain used
locally, so a green CI means a green desk):

| job | gate |
|---|---|
| `test` | `swift test` |
| `lint` | swift-format, SwiftLint, layering invariants |
| `build` | `xcodebuild`, **failing on any warning** |
| `negative-controls` | a PR adding assertions but no falsifying input fails |

---

## 3. The organizing rule

Every defect in this repo had the same shape: **a mathematical claim written in
prose, never executed.** So `AGENTS.md` is built around one rule:

> A check that **cannot fail** and a check that **is being fooled** are
> indistinguishable from the outside. If you cannot construct an input that
> makes the check fail, the check is not yet a test — regardless of whether the
> code under it is right or wrong.

That formulation is deliberate. The first version said only "write a negative
control," and that framing is what produced the invalid bug report in §0.

`docs/invariants.md` gives all eight invariants (`I1`–`I8`) a **negative
control** up front, so specs and tests reference them by ID rather than
re-deriving them. Examples:

| invariant | positive | negative control |
|---|---|---|
| I1 length `L/cos θ` | any `N`, any `θ` | `θ → π/2` returns `.infinity`, not a finite lie |
| I2 arrival | even `N` lands on B | **odd `N` must not**, missing by exactly `w·tan θ` |
| I5 topology | `χ = 1`, exact `V/E/F` | constant tack has **zero** reflective seams |
| I6 monotonic | below bound → 0 violations | above bound → **> 0** |

Supporting this: `CLAUDE.md` (a thin `@AGENTS.md` import), six skills
(`/tdd`, `/math-invariants`, `/spec`, `/toolchain`, `/pr-checklist`,
`/architecture`), `docs/risk-tiers.md`, and issue/PR templates.

---

## 4. The five defects

### 4.1 `headingChangesAtTurns` returned zero at every reversal

```
before:  values deg = ["0.0","0.0","0.0","0.0","0.0","0.0","0.0"]
after:   values deg = ["90.0","90.0","90.0","90.0","90.0","90.0","90.0"]
```

`2θ = 90°`, exactly as the doc comment promised. Segment `i` is generated using
the band at `pts[i]` — the point the step *departed from* — but the detector
compared `pts[i-1]−pts[i-2]` against `pts[i]−pts[i-1]`, both still pre-turn.

**The count was always right**, so any assertion checking the number of turns —
the obvious thing to check — passed against a function returning all zeros.

User-visible: `headingChangeWeight · Σ|Δθ|²` was identically zero, so the
**"Heading-change μ" slider did nothing** whenever the warped field was on.

### 4.2 The monotonicity bound was wrong by `σ/√e`

`max|∂ψ/∂s|` is attained at `|s−s₀| = σ`, not at the centre:

```
max |∂ψ/∂s| = |a| / (σ·√e)        not  |a| / σ²
```

Measured on a 200×100 grid:

| `a` | `σ` | old bound | correct | `1/L` | actual violations |
|---|---|---|---|---|---|
| 0.12 | 18 | 0.00037 | 0.00404 | 0.01 | 0.00% |
| 0.30 | 18 | 0.00093 | 0.01011 | 0.01 | **0.16%** |
| 0.30 | 8 | 0.00469 | 0.02274 | 0.01 | **2.25%** |
| 0.20 | 6 | 0.00556 | 0.02022 | 0.01 | **1.09%** |
| 0.05 | 4 | 0.00313 | 0.00758 | 0.01 | 0.00% |

The old bound called **all five** safe. Three are not. Every row is reachable
from the sliders as ranged. Now executable as `.maximumBumpSlope` /
`.isMonotonic`, cross-checked against the point-wise sampler.

### 4.3 The integrator truncated silently — and the default step was in the wrong regime

`integrate()` now returns `.arrived` / `.stalled` / `.exceededStepBudget`.
Previously `a=0.30, σ=8` stopped at `s ≈ 52` of 100 and the canvas drew that
truncated path as though it were real.

Then a convergence test **failed** — the error *grew* when the step halved.
Rather than loosen it:

| step | distance from B | ratio |
|---|---|---|
| `L/256` | 0.383 | 0.71 |
| `L/512` | **0.433** | **1.13 ← increases** |
| `L/1024` | 0.090 | 0.21 |
| `L/2048` | 0.042 | 0.46 |
| `L/4096` | 0.018 | 0.44 |

Each band boundary is crossed late by a fraction of a step, and that fraction
*beats against* the step size rather than shrinking with it. **The default
`L/512` sat squarely in the non-convergent regime**, where refining the step
could make the answer worse. Now `L/2048`. The coarse-regime behavior is pinned
as a negative control so the next person to write the obvious convergence test
learns it from a passing suite.

### 4.4 `WindModel` was wrong, and entirely unused

```
closeHauledHeading (wind from north, 45° no-go):
  before: starboard (0.707, -0.707) -> 135.0° off the wind   <- a broad reach
  after:  starboard (0.707,  0.707) ->  45.0° off the wind

tackingAngle (course 20° off the wind):
  before: θ = 25.0°  ->  legs at  -5.0° and 45.0°   <- un-sailable
  after:  θ = 65.0°  ->  legs at  45.0° and 85.0°
```

Legs sit at `α+θ` and `|α−θ|` from the wind; requiring both to clear the no-go
zone gives `θ = noGo + α`, not `noGo − α`. The two agree **only at α = 0** —
dead upwind, presumably the case checked by hand.

Nothing referenced `WindModel`, so the running app had no wind and no no-go
enforcement at all — θ was a free 5–80° slider. It is now wired in, with a
warning when a hand-set θ would be un-sailable.

**A limitation this does not remove:** a single symmetric θ is exactly optimal
only dead upwind. Off-axis the efficient pair is asymmetric, which `TackPath`
cannot express. `tackingAngle` now returns the smallest *sailable* symmetric
angle and says so — conservative rather than silently approximate.

### 4.5 `cumulativeIsometries` composed in the wrong order

```
tacks SPSP
   Φ∘H (correct) : (0,0) (25,25) (50,50) (75,75)  (100,100)  straight
   H∘Φ (shipped) : (0,0) (25,25) (50,50) (75,-25) (100,100)  discontinuous
```

`H` is expressed in original coordinates and must be applied first. Dead code,
so no output ever disagreed — and a **single-reversal** sequence cannot
distinguish the orders, which is why review never caught it.

Also added `unfoldingIsIsometric(of:)`, a check that *can* fail: it asserts the
lift preserves *this* path's leg lengths and sailed distance. A polyline built
with the wrong angle is perfectly straight and fails it.

---

## 5. Performance

Per redraw at `N = 32` with the warped field on:

| | Release | Debug |
|---|---|---|
| before | 5.70 ms | 26.8 ms (≈37 fps ceiling) |
| after, steady state | all cache hits | all cache hits |

Three redundancies: the trajectory was integrated **four times** per frame, the
level curves computed **twice**, and the G-map rebuilt from scratch (3.4 ms,
the dominant cost) on every `body` call.

`GeneralizedTackPath.metrics()` derives all three trajectory metrics from one
pass; the ViewModel memoises on the inputs that produce each value.

The cache is **tested by counting work**, because a cache that silently misses
looks fast in review and is slow in practice:

```swift
counter.reset()
_ = TackingCost(…).breakdown(path, field: field)
#expect(counter.gradientCalls == oneIntegration)      // was 3×

// and the control, without which the above proves nothing:
_ = path.sailedLength(); _ = path.crossTrackPeak(); _ = path.headingChangesAtTurns()
#expect(counter.gradientCalls == 3 * oneIntegration)
```

---

## 5b. What this says about `GeneralizedMap` itself

Since that is the project you actually care about — the adapter exercised it
fairly hard, and it came out clean:

- **The topology is exactly right.** `χ = 1` for every strip count, involution
  laws hold, and `V/E/F/darts` match the closed form for a chain of quads
  (`8N / 2(N+1) / 3N+1 / N`) at `N ∈ {1, 2, 4, 8, 16, 32}`.
- **`sew(_:_:alpha:)` propagating along the sewing orbit is the right call.**
  Sewing one dart pair at α₂ sews the whole edge, which is what makes the
  adapter's single `sew` per seam correct. Worth documenting — it is not
  obvious from the signature, and hand-rolling the partner call gets a silent
  `false` from `isSewable`.
- **`createRing` + attribute containers with `onMerge`/`onSplit` did everything
  the adapter needed** without reaching past the public API.

The one thing I'd raise: `unsew` still carries the Rust port's `todo!()` for the
attribute split. Nothing here hits it, but it will surprise someone.

## 6. What was already right

Worth stating, because the list above is all problems. Independently verified as
correct, and now protected by tests:

- `TackPath` — `L/cos θ` matches the closed form for every `N` and `θ`
- `SailingGMapTopology` — `χ = 1`, involutions valid, exact `V/E/F/darts`
- `LinearProgressField` — value, gradient and Laplacian analytically correct
- `Optimization` — interior optimum found; every cost term behaves as documented
- `PlanarIsometry`, `CourseAxis` — reflections are involutions, frame round-trips
- The `GeneralizedMap` boundary really is one file, exactly as advertised

The layering, the value-type discipline, and the header comments are genuinely
good — and it is precisely because the prose is rigorous enough to check the
code against that these defects were findable at all.

---

## 7. Reviewing this

Eight merged PRs, each with its own issue, spec where the tier required one, and
red-then-green evidence in the body. Reading them in order tells the story:

| PR | |
|---|---|
| #2 | agent infrastructure |
| #4 | `SailingCore` extraction + CI |
| #6 | characterization suite (green, no behavior change) |
| #10 | composition order + falsifiable lift check |
| #12 | `headingChangesAtTurns` |
| #15 | monotonicity bound + integration termination |
| #17 | `WindModel` |
| #19 | performance |

To run it:

```sh
./scripts/bootstrap-dependency.sh
swift test --package-path Packages/SailingCore
open SailingGMap.xcworkspace          # not the .xcodeproj
```
