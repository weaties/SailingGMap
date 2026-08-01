//
//  GeneralizedTackPathTests.swift
//  SailingCoreTests
//
//  Invariant I4: the heading change at each tack reversal is 2θ, and there are
//  N−1 of them. See docs/invariants.md and the spec on issue #11.
//
//  R3 and R4 are the controls that matter: the pre-fix implementation returned
//  the RIGHT NUMBER of values, all of them zero. Any assertion that only
//  checked the count passed against it.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("GeneralizedTackPath")
struct GeneralizedTackPathTests {

    private let axis = CourseAxis.canonical(length: 100)

    private func linearField(halfWidth: Double = 50) -> AnyProgressField {
        AnyProgressField(LinearProgressField(axis: axis, halfWidth: halfWidth))
    }

    private func warpedField(amplitude: Double = 0.12, sigma: Double = 18) -> AnyProgressField {
        AnyProgressField(
            WarpedProgressField(
                axis: axis, halfWidth: 50, amplitude: amplitude, sigma: sigma))
    }

    // MARK: - R1 / R2: one turn per reversal, each 2θ

    @Test(
        "I4/R2: on a linear field every turn is 2θ",
        arguments: [2, 4, 8, 16], [20.0, 30.0, 45.0, 60.0])
    func linearFieldTurnsAreTwoTheta(n: Int, degrees: Double) {
        let θ = degrees * .pi / 180
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: n, tackingAngle: θ)
        let turns = path.headingChangesAtTurns()

        // R1: one per reversal.
        #expect(turns.count == n - 1)
        // R2: each equals 2θ. On the linear field û is constant, so the only
        // error is floating point — assert tightly rather than at the 1e-2
        // budget the spec allows for warped fields.
        for turn in turns {
            #expect(isApprox(turn, 2 * θ, absolute: 1e-9))
        }
    }

    @Test(
        "I4/R3 NEGATIVE CONTROL: no reversal may be reported as a zero turn",
        arguments: [2, 4, 8, 16], [20.0, 45.0, 60.0])
    func noTurnIsReportedAsZero(n: Int, degrees: Double) {
        // The defining control. Before the fix this returned [0.0, 0.0, …] with
        // exactly the right count, so a count-only assertion passed while the
        // cost term it fed was silently dead.
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: n, tackingAngle: degrees * .pi / 180)
        let turns = path.headingChangesAtTurns()

        #expect(!turns.isEmpty)
        #expect(turns.allSatisfy { $0 > 1e-6 })
    }

    @Test("I4/R4 NEGATIVE CONTROL: a single-band path has no turns at all")
    func singleBandHasNoTurns() {
        // Must be empty, not [0] — a zero-valued entry would mean the detector
        // fired on something that is not a reversal.
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: 1, tackingAngle: .pi / 4)
        #expect(path.headingChangesAtTurns().isEmpty)
    }

    // MARK: - R6: warped fields vary

    @Test("I4/R6: on a warped field the turns vary between reversals")
    func warpedFieldTurnsVary() {
        let θ = Double.pi / 4
        let field = warpedField(amplitude: 0.12, sigma: 18)
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: θ)
        let turns = path.headingChangesAtTurns()

        #expect(!turns.isEmpty)
        // Still near 2θ for a mild warp — within the spec's 1e-2 rad budget
        // amplified for the larger bump, but demonstrably not all identical.
        #expect(turns.allSatisfy { abs($0 - 2 * θ) < 0.2 })
        let spread = (turns.max() ?? 0) - (turns.min() ?? 0)
        #expect(spread > 1e-9)  // û rotates between reversals
    }

    // MARK: - The cost term this feeds

    @Test("the heading-change cost term is non-zero on the generalized path")
    func headingChangeCostIsNonZeroOnGeneralizedPath() {
        // The user-visible consequence: with the warped field on, the
        // "Heading-change μ" slider moved nothing because Σ|Δθ|² was 0.
        let θ = Double.pi / 4
        let field = warpedField()
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: θ)
        let cost = TackingCost(lengthWeight: 0, headingChangeWeight: 1)

        let breakdown = cost.breakdown(path, field: field)
        #expect(breakdown.headingChange > 0)
        // Roughly (N−1)·(2θ)² for a mild warp.
        #expect(isApprox(breakdown.headingChange, 7 * (2 * θ) * (2 * θ), relative: 0.15))
    }

    @Test("NEGATIVE CONTROL: with weight zero the heading term contributes nothing")
    func headingChangeTermRespectsItsWeight() {
        let field = warpedField()
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: .pi / 4)
        let breakdown = TackingCost(lengthWeight: 1, headingChangeWeight: 0)
            .breakdown(path, field: field)
        #expect(breakdown.headingChange == 0)
    }

    // MARK: - Band lookup

    @Test("bandIndex maps progress to the containing band", arguments: [2, 4, 8, 16])
    func bandIndexMapsProgressToBand(n: Int) {
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: n, tackingAngle: .pi / 4)
        for i in 0..<n {
            let mid = (Double(i) + 0.5) / Double(n)
            #expect(path.bandIndex(forProgress: mid) == i)
        }
        // Clamped at the ends rather than crashing or wrapping.
        #expect(path.bandIndex(forProgress: -1) == 0)
        #expect(path.bandIndex(forProgress: 2) == n - 1)
    }

    @Test("tacks alternate across bands", arguments: [2, 4, 8, 16])
    func tacksAlternate(n: Int) {
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: n, tackingAngle: .pi / 4)
        for (a, b) in zip(path.tacks, path.tacks.dropFirst()) {
            #expect(a != b)
        }
    }

    // MARK: - Linear field reduces to the rhumb-line prototype

    @Test(
        "on a linear field the integrated length approaches L / cos θ",
        arguments: [4, 8, 16], [30.0, 45.0])
    func integratedLengthApproachesClosedForm(n: Int, degrees: Double) {
        let θ = degrees * .pi / 180
        let path = GeneralizedTackPath.uniformAlternating(
            field: linearField(), bandCount: n, tackingAngle: θ)
        // Forward Euler with a fixed step overshoots slightly; relative 1e-2 is
        // the integration budget, not a precision claim. Invariant I7 (issue
        // #13) tightens this by reporting the termination reason.
        #expect(isApprox(path.sailedLength(), 100 / cos(θ), relative: 1e-2))
    }
}
