---
name: tdd
description: SailingGMap test patterns — Swift Testing idioms, the mandatory negative-control recipe, the floating-point tolerance table, and how to watch a red test fail for the right reason. AGENTS.md already mandates the Red-Green-Refactor cycle and the falsifiability rule; this skill encodes the project-specific mechanics that aren't recoverable from existing tests at a glance. TRIGGER when writing or modifying Swift source under Packages/SailingCore/ or adding any test. DO NOT trigger for documentation, CI config, skill definitions, SwiftUI view layout, or changes that can't affect numerical behavior.
---

# TDD — SailingGMap patterns

`AGENTS.md` already mandates: failing test → implement → green → lint, and
"a mathematical claim is not true until a falsifiable test says so." This
skill is the mechanics.

## The cycle, concretely

1. **Write the red test.** Include the negative control in the same commit.
2. **Run it and read the failure message.** It must fail for the reason you
   intended. A test that fails because of a typo, a wrong fixture, or a
   compile error has told you nothing.
3. **Implement the minimum** that turns it green.
4. **Re-run the negative control.** If it still passes after your fix, your
   test does not discriminate — go back to step 1.
5. `./scripts/lint.sh`.

```bash
swift test --package-path Packages/SailingCore --filter UnfoldingTests
```

## Negative controls — the recipe

For every property `P(x)` you assert, construct an `x'` where `P` is false and
assert the code says so. Concretely, for this codebase:

```swift
@Test("alternating tacks unfold to a straight line")
func alternatingUnfoldsStraight() {
    let path = TackPath.uniformAlternating(axis: .unitCourse(length: 100),
                                           stripCount: 8, tackingAngle: .pi / 4)
    #expect(Unfolding.unfoldedIsStraight(Unfolding.unfold(path)))
}

// The control. Without this, the test above passes on a function that
// ignores its input entirely — which is exactly what shipped.
@Test("a constant-tack path does NOT unfold to a straight line")
func constantTackDoesNotUnfoldStraight() {
    let path = TackPath(axis: .unitCourse(length: 100),
                        strips: (0..<8).map {
                            Strip(id: $0, sStart: Double($0) * 12.5,
                                  sEnd: Double($0 + 1) * 12.5, tack: .starboard)
                        },
                        tackingAngle: .pi / 4)
    #expect(!Unfolding.unfoldedIsStraight(Unfolding.unfold(path)))
}
```

**Sanity check on your own test:** temporarily stub the function under test to
`return` a constant, and confirm the negative control goes red. If it stays
green, the test is decorative.

## Tolerance helpers

Never `#expect(a == b)` on `Double`. Use `Tests/SailingCoreTests/Support/Approx.swift`:

```swift
#expect(isApprox(path.sailedLength(), 100 / cos(θ), relative: 1e-12))
#expect(isApprox(endpoint.y, 0, absolute: 1e-9))
```

Tolerance selection is specified in `AGENTS.md` § "Floating-point tolerance
policy". The one that trips people up:

**Numerically integrated results get a *convergence* test, not a loose
epsilon.** Don't assert `#expect(isApprox(x, 100, relative: 1e-2))` and move
on — that hides an integrator that is wrong by 0.4%. Assert the error *shrinks
at the expected order* when you halve the step:

```swift
@Test("integrator arrival error is first-order in step length")
func integratorConvergesFirstOrder() {
    let e1 = arrivalError(stepLength: h)
    let e2 = arrivalError(stepLength: h / 2)
    // Forward Euler is O(h): halving the step should roughly halve the error.
    #expect(e2 < e1 * 0.6)
}
```

## Parameterize over the domain

One lucky value is not coverage. The interesting axes here are strip count,
tacking angle, and field warp:

```swift
@Test("sailed length is independent of strip count", arguments: [2, 4, 8, 16, 32, 64])
func lengthInvariantUnderStripCount(n: Int) {
    let p = TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)
    #expect(isApprox(p.sailedLength(), axis.length / cos(θ), relative: 1e-12))
}
```

Include the **degenerate ends** of each axis: `stripCount: 1`, `θ` near `0`,
`θ` near `π/2`, zero-length axis, `amplitude: 0`.

## Don't rationalize skipping the cycle

| Rationalization | Rebuttal |
|---|---|
| "This is a pure refactor, behavior is identical." | Then the existing tests pass unchanged and you lose nothing by running them first. If there are no existing tests for it, it isn't a refactor — it's an unverified rewrite. |
| "The math is obviously right, I derived it on paper." | Every defect in this repo was correct on paper and wrong in the file. The derivation goes in the doc comment; the test proves the code matches it. |
| "I'll add the negative control after." | The negative control is what makes the positive test meaningful. Shipped without it, you have a test that passes for a function returning a constant. |
| "The tolerance just needs a nudge to pass." | Loosening a tolerance to get green is how a regression ships. Find out *why* the error grew. If the looser bound is genuinely correct, justify the number in a comment. |
| "It's a SwiftUI view, I'll eyeball it." | True for layout. Not true for anything the view computes — and views here should not compute. If you're tempted to test a view's arithmetic, move that arithmetic to the ViewModel or SailingCore. |

## Where tests live

| Source | Test |
|---|---|
| `Models/TackPath.swift` | `Tests/SailingCoreTests/TackPathTests.swift` |
| `Mathematics/Unfolding.swift` | `Tests/SailingCoreTests/UnfoldingTests.swift` |
| … | one-to-one, same base name + `Tests` |

Cross-cutting invariants that span files (Euler characteristic, length
invariance) go in `InvariantTests.swift` and should reference
`docs/invariants.md` by section.
