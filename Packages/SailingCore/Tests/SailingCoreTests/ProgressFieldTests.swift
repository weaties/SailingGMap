//
//  ProgressFieldTests.swift
//  SailingCoreTests
//
//  LinearProgressField and the Foliation machinery over it. The warped field's
//  monotonicity bound is a known defect (invariant I6) and is covered by its
//  own failing-test-first change — deliberately not asserted here.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("ProgressField (linear)")
struct ProgressFieldTests {

    private let axis = CourseAxis.canonical(length: 100)
    private var field: LinearProgressField { LinearProgressField(axis: axis, halfWidth: 50) }

    // MARK: - Values

    @Test(
        "s(p) = s_coord / L, independent of cross-track position",
        arguments: [0.0, 25.0, 50.0, 75.0, 100.0], [-40.0, 0.0, 40.0])
    func linearValueIgnoresCrossTrack(s: Double, n: Double) {
        #expect(isApprox(field.value(sCoord: s, nCoord: n), s / 100, relative: 1e-12))
    }

    @Test("boundary conditions: s(A) = 0 and s(B) = 1")
    func boundaryConditions() {
        #expect(isApprox(field.value(sCoord: 0, nCoord: 0), 0, absolute: 1e-12))
        #expect(isApprox(field.value(sCoord: axis.length, nCoord: 0), 1, relative: 1e-12))
    }

    @Test("gradient is the constant (1/L, 0) and the Laplacian vanishes")
    func gradientAndLaplacian() {
        let g = field.gradient(sCoord: 33, nCoord: -12)
        #expect(isApprox(g.dx, 1 / 100, relative: 1e-12))
        #expect(isApprox(g.dy, 0, absolute: 1e-12))
        #expect(isApprox(field.laplacian(sCoord: 33, nCoord: -12), 0, absolute: 1e-12))
        // An affine field is harmonic, so the smoothness functional is exactly 0.
        #expect(isApprox(field.laplacianL2Squared(), 0, absolute: 1e-12))
    }

    @Test("the progress direction is the course axis itself")
    func progressDirectionIsCourseDirection() {
        let u = field.progressDirection(sCoord: 10, nCoord: 7)
        #expect(isApprox(u.dx, 1, relative: 1e-12))
        #expect(isApprox(u.dy, 0, absolute: 1e-12))
    }

    // MARK: - Monotonicity

    @Test("the linear field is monotonic everywhere")
    func linearFieldIsMonotonic() {
        #expect(isApprox(Foliation.monotonicityViolations(of: field), 0, absolute: 1e-12))
    }

    @Test("negative control: a field with a reversed gradient is NOT monotonic")
    func reversedGradientIsNotMonotonic() {
        // Without a case that violates it, `monotonicityViolations` returning 0
        // proves nothing — a function that always returns 0 would pass. A field
        // with ∂s/∂s_coord < 0 everywhere must have *every* sample flagged, so
        // the expected answer is exactly 1.0, not merely "nonzero".
        let violations = Foliation.monotonicityViolations(of: DecreasingField(length: 100))
        #expect(isApprox(violations, 1.0, absolute: 1e-12))
    }

    // MARK: - Foliation level curves

    @Test(
        "level curves of the linear field are vertical lines at s = c·L",
        arguments: [0.1, 0.25, 0.5, 0.75, 0.9])
    func levelCurvesAreVerticalLines(c: Double) {
        let curve = Foliation.levelCurve(of: field, at: c, samples: 32)
        #expect(curve.count == 32)
        // Tolerance derivation: `solveForS` bisects until the *field value* is
        // within 1e-7 of the target. Converting that to an error in s means
        // dividing by |ds/dc| = L = 100, giving ~1e-5. Anything tighter than
        // that is asserting precision the solver never promised; 1e-4 leaves
        // one decade of margin. (Per AGENTS.md, tolerances get a derivation,
        // not a guess — an earlier 1e-6 here failed for exactly this reason.)
        for p in curve {
            #expect(isApprox(p.x, c * 100, absolute: 1e-4))
        }
        // And they span the full cross-track domain.
        #expect(isApprox(curve.first?.y ?? 0, -50, absolute: 1e-9))
        #expect(isApprox(curve.last?.y ?? 0, 50, absolute: 1e-9))
    }

    @Test("negative control: level curves at distinct levels do not coincide")
    func distinctLevelsGiveDistinctCurves() {
        // Guards against a bisection that returns a constant regardless of the
        // requested level.
        let a = Foliation.levelCurve(of: field, at: 0.25, samples: 8)
        let b = Foliation.levelCurve(of: field, at: 0.75, samples: 8)
        #expect(!isApprox(a[0].x, b[0].x, absolute: 1.0))
        #expect(isApprox(b[0].x - a[0].x, 50, absolute: 1e-4))
    }

    @Test("levelCurves generates evenly spaced interior boundaries", arguments: [1, 3, 7, 15])
    func levelCurvesAreEvenlySpaced(count: Int) {
        let curves = Foliation.levelCurves(of: field, count: count, samples: 8)
        #expect(curves.count == count)
        let positions = curves.compactMap(\.first?.x)
        for (k, s) in positions.enumerated() {
            #expect(isApprox(s, Double(k + 1) / Double(count + 1) * 100, absolute: 1e-4))
        }
    }

    @Test("requesting zero level curves yields none")
    func zeroLevelCurves() {
        #expect(Foliation.levelCurves(of: field, count: 0).isEmpty)
    }

    // MARK: - Bisection

    @Test("solveForS inverts the field to the requested tolerance", arguments: [0.05, 0.5, 0.95])
    func solveForSInvertsTheField(c: Double) {
        let s = Foliation.solveForS(of: field, n: 17, target: c)
        #expect(isApprox(field.value(sCoord: s, nCoord: 17), c, absolute: 1e-7))
    }
}

/// A field whose progress *decreases* along +s. Used only as the negative
/// control for the monotonicity diagnostic: every grid sample must be flagged.
private struct DecreasingField: ProgressField {
    let length: Double
    var axis: CourseAxis { CourseAxis(origin: .zero, destination: Point2D(x: length, y: 0)) }
    var halfWidth: Double { 50 }
    func value(sCoord: Double, nCoord: Double) -> Double { 1 - sCoord / length }
    func gradient(sCoord: Double, nCoord: Double) -> Vector2D { Vector2D(dx: -1 / length, dy: 0) }
    func laplacian(sCoord: Double, nCoord: Double) -> Double { 0 }
}
