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
| **I3** | Unfolded polyline is colinear ⟺ tacks alternate | uniform alternating ⟹ straight | constant tack ⟹ **not** straight | abs `1e-9` |
| **I4** | Heading change at each reversal is `2θ`; there are `N − 1` of them | linear field ⟹ all `≈ 2θ` | none may be identically `0` | abs `1e-9` rad |
| **I5** | Strip chain is a topological disk: `χ = V − E + F = 1` | every `N`: darts `8N`, V `2(N+1)`, E `3N+1`, F `N` | a torn/unsewn chain ⟹ `χ ≠ 1` | exact (integers) |
| **I6** | Warped field is monotonic ⟺ `\|a\| / (σ·√e) < 1/L` | `a=0.12, σ=18` ⟹ 0 violations | `a=0.30, σ=8` ⟹ **> 0** violations | exact (counted) |
| **I7** | Integration reports its termination reason | linear field ⟹ `.arrived` within `1e-3·L` | `a=0.30, σ=8` ⟹ `.exceededStepBudget`, not a silent truncation | rel `1e-3` |
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

### I3 — Unfolding straightens iff tacks alternate

`Φᵢ = Φᵢ₋₁ ∘ Rᵢ` with `Rᵢ` a reflection in **original** coordinates. The
reversed order `Rᵢ ∘ Φᵢ₋₁` reflects in covering coordinates about an
original-frame value — a different map, and wrong.

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

### I7 — Integration termination

Forward Euler, fixed step, band switching detected at step boundaries. Two
failure modes the API must expose rather than hide:

1. **Late switching** — tack flips up to one step after the true crossing.
   Measured drift: `(100.127, −0.414)` for a nominal `(100, 0)`.
2. **Non-arrival** — a warped field can stall the trajectory; it hits
   `maxSteps` and returns a truncated path. Measured: `a=0.30, σ=8` stops at
   `s_coord ≈ 52` of 100.

A caller must be able to distinguish "arrived" from "gave up".

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
