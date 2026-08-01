//
//  WarpedFieldTests.swift
//  SailingCoreTests
//
//  Invariants I6 (monotonicity bound) and I7 (integration termination).
//  See docs/invariants.md and issues #13, #14.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("Warped field and integration")
struct WarpedFieldTests {

    private let axis = CourseAxis.canonical(length: 100)

    private func warped(_ amplitude: Double, _ sigma: Double) -> WarpedProgressField {
        WarpedProgressField(axis: axis, halfWidth: 50, amplitude: amplitude, sigma: sigma)
    }

    // MARK: - I6: the monotonicity bound

    /// One row of the reference table in `docs/invariants.md` § I6.
    ///
    /// A named type rather than a tuple so the third member reads as what it
    /// is — the *measured* behavior of the field, which the bound predicate
    /// must reproduce.
    struct BumpCase: Sendable {
        let amplitude: Double
        let sigma: Double
        /// Measured on a 200×100 grid: does this configuration actually break
        /// monotonicity?
        let expectViolations: Bool
    }

    static let bumpCases: [BumpCase] = [
        BumpCase(amplitude: 0.12, sigma: 18, expectViolations: false),
        BumpCase(amplitude: 0.30, sigma: 18, expectViolations: true),
        BumpCase(amplitude: 0.30, sigma: 8, expectViolations: true),
        BumpCase(amplitude: 0.20, sigma: 6, expectViolations: true),
        BumpCase(amplitude: 0.05, sigma: 4, expectViolations: false),
    ]

    @Test("I6: the bound predicts monotonicity for every reference case", arguments: bumpCases)
    func boundPredictsMonotonicity(testCase: BumpCase) {
        let field = warped(testCase.amplitude, testCase.sigma)
        let measured = Foliation.monotonicityViolations(of: field, samplesS: 200, samplesN: 100)

        // The predicate and the measurement must agree. The OLD bound
        // (|a|/σ² < 1/L) called all five of these safe; three are not.
        #expect(field.isMonotonic == (measured == 0))
        #expect((measured > 0) == testCase.expectViolations)
    }

    @Test("I6: maximum bump slope is |a| / (sigma * sqrt(e))", arguments: bumpCases)
    func maximumSlopeMatchesClosedForm(testCase: BumpCase) {
        let field = warped(testCase.amplitude, testCase.sigma)
        let expected = abs(testCase.amplitude) / (testCase.sigma * exp(0.5))
        #expect(isApprox(field.maximumBumpSlope, expected, relative: 1e-12))

        // And it really is the maximum: sample ∂ψ/∂s densely and confirm
        // nothing exceeds it. This is what makes the closed form a claim rather
        // than a definition.
        let s0 = 0.5 * axis.length
        var observed = 0.0
        for k in 0...4000 {
            let s = s0 - 4 * testCase.sigma + Double(k) * (8 * testCase.sigma) / 4000
            let slope = field.gradient(sCoord: s, nCoord: 0).dx - 1 / axis.length
            observed = max(observed, abs(slope))
        }
        #expect(observed <= field.maximumBumpSlope * (1 + 1e-6))
        #expect(isApprox(observed, field.maximumBumpSlope, relative: 1e-3))
    }

    @Test("I6 NEGATIVE CONTROL: the superseded bound |a|/sigma^2 misclassifies three cases")
    func supersededBoundIsWrong() {
        // Pinned deliberately so nobody "simplifies" the formula back. The old
        // bound calls every reference case safe; the field disagrees.
        var oldSaidSafeButIsnt = 0
        for testCase in Self.bumpCases {
            let oldBound = abs(testCase.amplitude) / (testCase.sigma * testCase.sigma)
            let oldSaysSafe = oldBound < 1 / axis.length
            if oldSaysSafe && testCase.expectViolations { oldSaidSafeButIsnt += 1 }
        }
        #expect(oldSaidSafeButIsnt == 3)
    }

    @Test("a zero-amplitude bump reduces to the linear field")
    func zeroAmplitudeIsLinear() {
        let field = warped(0, 18)
        #expect(field.isMonotonic)
        #expect(isApprox(field.maximumBumpSlope, 0, absolute: 1e-15))
        #expect(isApprox(Foliation.monotonicityViolations(of: field), 0, absolute: 1e-12))
    }

    // MARK: - I7: integration termination

    @Test("I7: a linear field arrives", arguments: [4, 8, 16], [30.0, 45.0])
    func linearFieldArrives(n: Int, degrees: Double) {
        let field = AnyProgressField(LinearProgressField(axis: axis, halfWidth: 50))
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: n, tackingAngle: degrees * .pi / 180)
        let result = path.integrate()

        #expect(result.termination == .arrived)
        #expect(result.arrived)
    }

    @Test("I7 NEGATIVE CONTROL: a strongly warped field reports NOT arriving")
    func stronglyWarpedFieldDoesNotArrive() {
        // amplitude 0.30 / sigma 8 stalls at s_coord ≈ 52 of 100. Before this
        // change the caller received a truncated point list and no signal, and
        // the canvas drew a short line as though it were a real trajectory.
        let field = AnyProgressField(warped(0.30, 8))
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: .pi / 4)
        let result = path.integrate()

        #expect(!result.arrived)
        #expect(result.termination == .exceededStepBudget)
        // And it really did stop short — this is not a false alarm.
        #expect((result.points.last?.x ?? 0) < 0.75 * axis.length)
    }

    @Test("I7 NEGATIVE CONTROL: a vanishing gradient stalls rather than emitting NaN")
    func vanishingGradientStalls() {
        let path = GeneralizedTackPath.uniformAlternating(
            field: AnyProgressField(FlatField()), bandCount: 4, tackingAngle: .pi / 4)
        let result = path.integrate()

        #expect(result.termination == .stalled)
        #expect(result.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    private func arrivalError(divisor: Int) -> Double {
        let field = AnyProgressField(LinearProgressField(axis: axis, halfWidth: 50))
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: .pi / 4)
        let pts = path.integrateInCourseFrame(stepLength: axis.length / Double(divisor))
        guard let last = pts.last else { return .infinity }
        return (last - Point2D(x: axis.length, y: 0)).magnitude
    }

    @Test("I7: arrival error is first order in the step length (asymptotic regime)")
    func arrivalErrorIsFirstOrder() {
        // Assert the convergence ORDER rather than hiding the drift behind a
        // loose epsilon. Forward Euler is O(h): halving the step halves the
        // error — but only once the step is fine enough. See the next test.
        for divisor in [1024, 2048] {
            let coarse = arrivalError(divisor: divisor)
            let fine = arrivalError(divisor: divisor * 2)
            #expect(fine < coarse * 0.6)
        }
    }

    @Test("I7 NEGATIVE CONTROL: convergence does NOT hold in the coarse regime")
    func convergenceFailsBelowTheAsymptoticRegime() {
        // Pinned deliberately, because it is the reason the default step
        // changed. Each band boundary is crossed late by a fraction of a step,
        // and that fraction beats against the step size instead of shrinking
        // with it. Between L/256 and L/512 the error actually *increases*:
        //
        //   L/256 -> 0.383      L/512 -> 0.433      (ratio 1.13)
        //
        // A test that assumed monotone convergence here would fail against a
        // perfectly correct integrator — which is exactly what happened, and
        // why the default is now L/2048 rather than L/512.
        let coarse = arrivalError(divisor: 256)
        let finer = arrivalError(divisor: 512)
        #expect(finer > coarse)
    }

    @Test("I7: the default step lands in the asymptotic regime")
    func defaultStepIsAccurate() {
        #expect(GeneralizedTackPath.defaultStepDivisor >= 1024)
        // ~0.04% of the course length at the default.
        #expect(arrivalError(divisor: GeneralizedTackPath.defaultStepDivisor) < 0.001 * axis.length)
    }

    @Test("the integration result's points match the legacy accessor")
    func resultPointsMatchLegacyAccessor() {
        // integrateInCourseFrame() is kept for existing callers; it must return
        // exactly the points the richer API reports.
        let field = AnyProgressField(warped(0.12, 18))
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: .pi / 4)
        let legacy = path.integrateInCourseFrame()
        let result = path.integrate()

        #expect(legacy.count == result.points.count)
        #expect(zip(legacy, result.points).allSatisfy { isApprox($0, $1, absolute: 1e-12) })
    }
}

/// A field with zero gradient everywhere: the integrator must stall rather than
/// divide by zero and emit NaN.
private struct FlatField: ProgressField {
    var axis: CourseAxis { .canonical(length: 100) }
    var halfWidth: Double { 50 }
    func value(sCoord: Double, nCoord: Double) -> Double { 0 }
    func gradient(sCoord: Double, nCoord: Double) -> Vector2D { .zero }
    func laplacian(sCoord: Double, nCoord: Double) -> Double { 0 }
}
