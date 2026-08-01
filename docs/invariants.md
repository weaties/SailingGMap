# Invariants

The canonical, numbered list of properties that must hold across SailingGMap.
Each has a stable ID (`I1`…) referenced from specs, tests, and PR bodies.

Every invariant carries a **negative control**: an input for which the property
is false. A test that asserts only the positive case cannot distinguish a
correct implementation from one that ignores its input — see `AGENTS.md`
§ "The falsifiability rule".

| ID | Invariant | Positive case | Negative control | Tolerance |
|---|---|---|---|---|
| **I1** | Sailed length `L_path = L / cos θ`, independent of strip count `N` | any even `N ∈ [2, 64]` matches the closed form | `θ → π/2` returns `.infinity`, not a finite value | rel `1e-12` |
| **I2** | Path arrives at B ⟺ `Σ σᵢ wᵢ tan θ = 0` | even `N` ⟹ `arrivalOffset ≈ 0` | odd `N` ⟹ `arrivalOffset = w·tan θ ≠ 0` | abs `1e-9` |
| **I3** | The unfolding is an isometric lift of the path | leg lengths preserved; total = `sailedLength()` | a straight polyline with the wrong angle ⟹ **rejected** | rel `1e-9` |
| **I4** | Heading change at each reversal is `2θ`; there are `N − 1` of them | linear field ⟹ all `≈ 2θ` | none may be identically `0` | abs `1e-9` rad |
| **I5** | Strip chain is a topological disk: `χ = V − E + F = 1` | every `N`: darts `8N`, V `2(N+1)`, E `3N+1`, F `N` | a torn/unsewn chain ⟹ `χ ≠ 1` | exact (integers) |
| **I6** | Warped field is monotonic ⟺ `\|a\| / (σ·√e) < 1/L` | `a=0.12, σ=18` ⟹ 0 violations | `a=0.30, σ=8` ⟹ **> 0** violations | exact (counted) |
| **I7** | Integration reports its termination reason | linear field ⟹ `.arrived` within `1e-3·L` | `a=0.30, σ=8` ⟹ `.exceededStepBudget`, not a silent truncation | rel `1e-3` |
| **I7b** | Arrival error is O(h) **in the asymptotic regime only** | `L/1024 → L/2048 → L/4096` each halve the error | between `L/256` and `L/512` the error **increases** | ratio < 0.6 |
| **I8** | Cost terms have the documented `N`-dependence | `(N−1)` grows, `max\|n\|` shrinks, interior optimum exists | `∫\|Δs\|²dA` is **constant** in `N` — cannot move the argmin | rel `1e-9` |

## Detail

### I1 — Length invariance under strip count

```
L_path = Σᵢ wᵢ / cos θ = L / cos θ
```

The geometric content of the unfolding: the lifted path is one straight segment
of that length. Because it does not depend on `N`, any cost model hoping for an
interior optimum in `N` must get that dependence from the turn, heading-change,
or swing terms. A change that makes length vary with `N` is a bug.

### I2 — Arrival condition

Uniform alternating strips need **even** `N`. The model does not enforce this
and should not; `arrivalOffset()` reporting non-zero for an unbalanced path is
correct behavior, not something to clamp.

### I3 — The unfolding is an isometric lift

Straightness is **unconditional**: the construction reflects every leg to the
same direction, so the lift is the segment `(0,0) → (L, L·tan θ)` for any tack
sequence. It therefore cannot serve as a correctness check.

> Corrected 2026-08-01. This invariant previously read "colinear ⟺ tacks
> alternate", which is false — a constant-tack path is already a straight line
> in course coordinates. Issue #7 was filed against working code on that
> premise and closed as invalid.

The content is that the lift is an isometry of the *specific* path:
anchored at A, leg lengths preserved, end-to-end distance equal to
`sailedLength()`. A polyline built with the wrong tacking angle is perfectly
straight and fails all three.

Composition order: `Φᵢ = Φᵢ₋₁ ∘ Rᵢ` with `Rᵢ` in **original** coordinates. The
reverse gives a lift that is discontinuous across seams, and a single-reversal
path cannot distinguish the two orders.

### I4 — Heading change per reversal

On the linear field exactly `2θ`. On a warped field it varies as `û` rotates,
but must remain near `2θ` for small warp and must never be identically zero.

### I5 — G-map topology

`χ = 1` because a chain of quads glued along shared edges is a disk. Verified:
`N=2 → 16/6/7/2`, `N=4 → 32/10/13/4`, `N=8 → 64/18/25/8`.

Involution laws: every `αᵢ` is an involution and `αᵢαⱼ` is an involution for
`|i−j| ≥ 2`. At `ndims = 3` that reduces to `(α₀α₂)² = id`.

### I6 — Monotonicity bound

For `ψ = a·exp(−r²/2σ²)`, `max|∂ψ/∂s| = |a|/(σ√e)` attained at `|s−s₀| = σ`.
Monotonicity of `s = s_coord/L + ψ` therefore requires `|a|/(σ√e) < 1/L`.

Reference data (200×100 grid, `L = 100`):

| `a` | `σ` | `\|a\|/σ²` (wrong) | `\|a\|/(σ√e)` (correct) | `1/L` | violations |
|---|---|---|---|---|---|
| 0.12 | 18 | 0.00037 | 0.00404 | 0.01 | 0.00% |
| 0.30 | 18 | 0.00093 | 0.01011 | 0.01 | 0.16% |
| 0.30 | 8 | 0.00469 | 0.02274 | 0.01 | 2.25% |
| 0.20 | 6 | 0.00556 | 0.02022 | 0.01 | 1.09% |
| 0.05 | 4 | 0.00313 | 0.00758 | 0.01 | 0.00% |

The correct bound classifies all five rows; `|a|/σ²` classifies none of the
failures. Use this table directly as parameterized test data.

Exposed as `WarpedProgressField.maximumBumpSlope` and `.isMonotonic` so the
criterion is executable rather than a claim in a comment.

### I7 — Integration termination and convergence

Forward Euler, fixed step, band switching detected at step boundaries. The API
must expose which of three things happened — `.arrived`, `.stalled`,
`.exceededStepBudget` — because all three otherwise return an indistinguishable
list of points.

Measured non-arrival: `a = 0.30, σ = 8` stops at `s_coord ≈ 52` of 100.

**Convergence is not monotone at coarse steps.** Linear field, 8 bands, θ = 45°:

| step | distance from B | ratio |
|---|---|---|
| `L/128` | 0.542 | — |
| `L/256` | 0.383 | 0.71 |
| `L/512` | **0.433** | **1.13 — increases** |
| `L/1024` | 0.090 | 0.21 |
| `L/2048` | 0.042 | 0.46 |
| `L/4096` | 0.018 | 0.44 |

Each band boundary is crossed late by a fraction of a step, and that fraction
beats against the step size rather than shrinking with it. Only once many steps
fall inside each band does the O(h) term dominate.

Consequence: the original default of `L/512` sat in the non-convergent regime,
where refining the step could make the answer *worse*. The default is now
`L/2048` (~0.04% arrival error). Any convergence assertion must use divisors
≥ 1024; asserting it below that fails against a perfectly correct integrator.

### I8 — Cost-term behavior

```
J = λ_L·L_path + λ_turn·(N−1) + μ·Σ|Δθᵢ|² + λ_swing·max|n| + ν·∫|Δs|²dA
```

`L_path` is constant in `N` (I1). `(N−1)` grows, `max|n| = (L/N)·tan θ`
shrinks — their competition creates the interior optimum. `∫|Δs|²dA` is a
property of the field, constant in `N`, and cannot move the argmin of a sweep
over band count. Its value also depends on `halfWidth`, which the ViewModel
derives from `stripCount` and `θ` — so it is not comparable across slider
positions unless `halfWidth` is pinned.
