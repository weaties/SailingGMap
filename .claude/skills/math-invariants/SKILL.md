---
name: math-invariants
description: The sign conventions, coordinate frames, and system-wide mathematical invariants of SailingGMap that are NOT grep-recoverable — which way n points, what theta is measured from, why sailed length is independent of strip count, what the Euler characteristic must be, and the corrected monotonicity bound for the warped progress field. TRIGGER when modifying anything under Packages/SailingCore/, when a numerical result looks plausible but suspicious, or when reconciling a doc comment against code. DO NOT trigger for SwiftUI layout, CI config, docs-only edits, or questions answerable by reading a single file's header comment.
---

# Mathematical invariants — SailingGMap

The things that must stay true, and the conventions that make "plausible
garbage" look correct if you get them backwards.

## Frames and signs

Two frames. Never mix them; every `Point2D` belongs to exactly one.

| | World | Course |
|---|---|---|
| Coordinates | `(x, y)` | `(s, n)` |
| Origin | arbitrary | `A` |
| Bridge | `CourseAxis.fromCourse(s:n:)` | `CourseAxis.toCourse(_:)` |

- `u` = unit vector `A → B`. The `s` axis.
- `n` = `u` rotated **90° counter-clockwise** (`perpendicularLeft`). Positive
  `n` is to **port** when sailing `A → B`.
- `σ = tack.sign`: `.starboard = +1`, `.port = −1`.
- **`θ` is measured off the course axis, not off the wind.** This is the single
  most common confusion in this codebase. `WindModel.tackingAngle(towards:)`
  converts wind-relative geometry into this course-relative `θ`.
- Heading in strip `i`, course frame: `(cos θ, σᵢ · sin θ)`.
- Cross-track displacement across strip `i`: `σᵢ · wᵢ · tan θ`.

## Invariants

### I1 — Sailed length is independent of strip count

```
L_path = Σ wᵢ / cos θ = L / cos θ
```

This is the geometric content of the unfolding: the lifted path is a single
straight segment of that length. **It does not depend on `N`.** Any cost
model that hopes to find an interior optimum in `N` must therefore get its
`N`-dependence from the turn / heading-change / swing terms — never from
length. If a change makes length vary with `N`, something is wrong.

Negative control: this must *fail* if `θ ≥ π/2` (divergent) — assert the
function returns `.infinity` rather than a finite lie.

### I2 — Arrival requires balanced cross-track displacement

```
Σᵢ σᵢ wᵢ tan θ = 0    ⟺    the path ends at B
```

For uniform alternating strips this needs **even `N`**. An odd count leaves an
offset of `w · tan θ`. The UI enforces even counts; the model does not, and
should not — `arrivalOffset()` reporting non-zero is the correct behavior for
an unbalanced path, not a bug to paper over.

### I3 — Unfolding straightens iff tacks alternate

The reflection unfolding lifts leg `i` by the composed isometry `Φᵢ`. For the
lifted polyline to be colinear, consecutive legs must have opposite `σ`. A
constant-tack path lifts to a zig-zag, **not** a line.

> Historical note: the original `unfoldByHorizontalReflections` never read
> `strip.tack` and emitted `(k·w, k·w·tanθ)` unconditionally, making
> `unfoldedIsStraight` a tautology. This invariant is the reason every
> unfolding test carries a constant-tack negative control.

Composition order matters: `Φᵢ = Φᵢ₋₁ ∘ Rᵢ`, where `Rᵢ` is a reflection
expressed in **original** coordinates. Writing `Rᵢ ∘ Φᵢ₋₁` reflects in
covering coordinates about an original-frame value, which is not the same map.

### I4 — Heading change at every reversal is `2θ`

On the linear field, `|Δθ|` at each tack reversal is exactly `2θ`, and there
are `N − 1` reversals. On a warped field it varies, because `û` rotates
between reversals — but it must still be near `2θ` for small warp, and must
never be identically zero.

> Historical note: `headingChangesAtTurns()` returned all zeros due to an
> off-by-one — the band change was detected from `pts[i]` while the tack that
> produced `pts[i]` came from the band at `pts[i-1]`, so both compared
> segments were pre-turn.

### I5 — G-map topology of a strip chain

`N` quadrilateral faces sewn in a chain along `N − 1` shared edges:

| Quantity | Value |
|---|---|
| Darts | `8N` |
| Vertices (0-cells) | `2(N + 1)` |
| Edges (1-cells) | `4N − (N − 1) = 3N + 1` |
| Faces (2-cells) | `N` |
| **Euler characteristic** | `χ = V − E + F = 1` |

`χ = 1` because the chain is topologically a **disk**. If a change makes
`χ ≠ 1`, either the sewing is wrong or the complex is no longer a disk — both
are bugs unless the change explicitly introduces a hole or a tear.

Verified values: `N=2 → 16/6/7/2`, `N=4 → 32/10/13/4`, `N=8 → 64/18/25/8`.

**Involution laws** (what `isValid` checks): every `αᵢ` is an involution, and
`αᵢαⱼ` is an involution for `|i − j| ≥ 2`. With `ndims = 3` the only
non-adjacent pair is `(0, 2)`, so the check reduces to `(α₀α₂)² = id`.

**`sew` propagates.** `GMap.sew(_:_:alpha:)` walks the sewing orbit, so sewing
a single dart pair at α₂ sews the whole edge. Do not hand-roll a second call
for the partner dart — `isSewable` will reject it and you'll get a silent
`false`.

### I6 — Progress-field monotonicity bound

For `s(p) = s_coord/L + a·exp(−r²/2σ²)`, monotonicity `∂s/∂s_coord > 0`
requires the bump's steepest descent to stay under the linear gradient:

```
max |∂ψ/∂s| = |a| / (σ·√e)        attained at |s − s₀| = σ
⟹  monotonic  ⟺  |a| / (σ·√e) < 1/L
```

> **The bound documented in the original source was `|a|/σ² < 1/L`** — off by
> a factor of `σ/√e`. It reported "safe" for configurations that measurably
> violate monotonicity. Measured against a 200×100 grid:
>
> | `a` | `σ` | old bound | correct bound | `1/L` | actual violations |
> |---|---|---|---|---|---|
> | 0.12 | 18 | 0.00037 | 0.00404 | 0.01 | 0.00% |
> | 0.30 | 18 | 0.00093 | 0.01011 | 0.01 | 0.16% |
> | 0.30 | 8 | 0.00469 | 0.02274 | 0.01 | 2.25% |
> | 0.20 | 6 | 0.00556 | 0.02022 | 0.01 | 1.09% |
> | 0.05 | 4 | 0.00313 | 0.00758 | 0.01 | 0.00% |
>
> The correct bound predicts all five rows; the old one predicts none of the
> failures. Use this table as test data.

### I7 — The integrator must arrive, or say it didn't

`GeneralizedTackPath.integrateInCourseFrame` is forward Euler with a fixed
step and band switching detected at step boundaries. Two failure modes:

1. **Late switching** — the tack flips up to one step after the true level-curve
   crossing, so the endpoint drifts (measured: `(100.127, −0.414)` for a
   nominal `(100, 0)`).
2. **Non-arrival** — a sufficiently warped field can push `s ≥ 1` early or stall
   the trajectory; it hits `maxSteps` and returns a truncated path with no
   signal. Measured: `amp 0.30 / σ 8` stops at `s_coord ≈ 52` of 100.

Any integration API must report termination reason. A caller cannot distinguish
"arrived" from "gave up" by looking at the returned points.

### I8 — Cost-model term behavior

```
J = λ_L · L_path + λ_turn · (N−1) + μ · Σ|Δθᵢ|² + λ_swing · max|n| + ν · ∫|Δs|² dA
```

- `L_path` is constant in `N` (I1) — contributes no gradient.
- `(N−1)` grows with `N`; `max|n| = (L/N)·tan θ` shrinks with `N`. Their
  competition is what creates an interior optimum.
- `∫|Δs|² dA` is **constant in `N`** for a fixed field — it is a property of
  the foliation, not the band count. It therefore cannot move the argmin of a
  sweep over `N`. If you want it to matter, it has to be optimized jointly with
  the field, not swept against band count.
- The integration domain `Ω` depends on `halfWidth`, which the ViewModel
  derives from `stripCount` and `θ`. So `∫|Δs|² dA` is not comparable across
  slider positions. Pin `halfWidth` before comparing.

## Quick self-check

When a result looks plausible but you're unsure, run these:

```
sailedLength(N=8)  == sailedLength(N=32)      // I1
arrivalOffset(even N) ≈ 0, arrivalOffset(odd N) ≠ 0   // I2
unfoldedIsStraight(constant tack) == false     // I3
headingChanges(linear field) all ≈ 2θ          // I4
χ == 1 for every N                             // I5
```
