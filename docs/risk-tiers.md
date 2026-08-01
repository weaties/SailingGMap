# Risk tiers

What extra scrutiny a change earns, by what it touches. The tier is set by the
*path*, not by the size of the diff — a one-line change to `Unfolding.swift` is
Critical.

| Tier | Paths | Extra requirements |
|---|---|---|
| **Critical** | `Mathematics/Unfolding.swift`<br>`Mathematics/SailingGMapTopology.swift`<br>`Mathematics/ProgressField.swift`<br>`Mathematics/GeneralizedTackPath.swift` | Structured spec, approved on the issue, before implementation (`/spec`)<br>Negative-control test for every asserted property<br>Explicit tolerance justification on every float assertion<br>Spec archived to `docs/specs/` in the PR |
| **High** | `Models/*.swift`<br>`Mathematics/Foliation.swift`<br>`Mathematics/Optimization.swift` | Negative-control tests<br>Spec if the change alters a documented invariant (`docs/invariants.md`) |
| **Normal** | `SailingGMap/Views/`<br>`SailingGMap/ViewModels/` | Standard TDD |
| **Low** | `docs/`, `.github/`, `.claude/`, `scripts/` | Review only |

## Why these four are Critical

Each has already shipped a defect that passed review and ran in production:

| File | Defect | Why tests didn't catch it |
|---|---|---|
| `Unfolding.swift` | `cumulativeIsometries` composed reflections as `H ∘ Φ` instead of `Φ ∘ H`, giving a lift that is discontinuous across seams | Dead code — nothing called it, so no output ever disagreed. A single-reversal path also cannot distinguish the two orders. |
| `GeneralizedTackPath.swift` | `headingChangesAtTurns` returned all zeros (off-by-one in crossing detection) | No test asserted the expected `2θ`; the value fed a cost term nobody read. |
| `ProgressField.swift` | Documented monotonicity bound off by `σ/√e`; reported "safe" for violating configs | The bound was in a comment, never executed. |
| `SailingGMapTopology.swift` | `precondition(map.sew(...))` — a mutating call inside an assertion, elided under `-Ounchecked` | Never built with `-Ounchecked`. |

The common thread: **a mathematical claim written in prose, never executed.**
The Critical tier exists to force those claims into tests.

There is a fifth entry worth recording as a near-miss. `unfoldedIsStraight`
returns `true` for every input — correctly, since the unfolding theorem is
unconditional. A review mistook that vacuity for a fabricated implementation
and filed a bug against working code (#7). The lesson is symmetric with the
others: an assertion that cannot fail tells you nothing about the code beneath
it, in *either* direction.

## The Critical gate, in order

1. Open the issue describing the change.
2. `/spec <issue>` — post the structured spec as an issue comment.
3. **Wait for approval.** Do not write implementation.
4. Write the tests from the spec — every row is at least two cases (property +
   negative control). Watch them fail for the right reason.
5. Implement until green.
6. `/pr-checklist`, then open the PR with `Closes #N` and the spec archived to
   `docs/specs/<issue>-<slug>.md`.

## Promotion and demotion

A file moves to Critical when it acquires a documented invariant in
`docs/invariants.md`. It can be demoted only by a PR that argues the case
explicitly — not silently, and not as a side effect of a refactor.
