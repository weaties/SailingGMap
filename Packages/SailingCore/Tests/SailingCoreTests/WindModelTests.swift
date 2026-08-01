//
//  WindModelTests.swift
//  SailingCoreTests
//
//  The wind model was entirely unreferenced, so nothing exercised it and both
//  of its angle computations were wrong. See issue #16.
//
//  The controls here are physical rather than numerical: a heading must be
//  outside the no-go zone, and a tacking angle must put BOTH legs outside it.
//  An implementation can be self-consistent and still describe a boat that
//  cannot sail.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("WindModel")
struct WindModelTests {

    private let northerly = WindModel(fromDirection: Vector2D(dx: 0, dy: 1), noGoHalfAngle: .pi / 4)

    /// Angle between a heading and the direction the wind blows *from*.
    /// Zero means pointing straight into the wind.
    private func degreesOffWind(_ heading: Vector2D, _ wind: WindModel) -> Double {
        let c = max(-1, min(1, Vector2D.dot(heading.normalized(), wind.fromDirection)))
        return acos(c) * 180 / .pi
    }

    // MARK: - closeHauledHeading

    @Test(
        "close-hauled headings sit exactly noGoHalfAngle off the wind",
        arguments: [30.0, 35.0, 45.0, 50.0])
    func closeHauledIsAtTheNoGoBoundary(noGoDegrees: Double) {
        let wind = WindModel(
            fromDirection: Vector2D(dx: 0, dy: 1), noGoHalfAngle: noGoDegrees * .pi / 180)
        for tack in Tack.allCases {
            #expect(
                isApprox(
                    degreesOffWind(wind.closeHauledHeading(tack), wind), noGoDegrees,
                    absolute: 1e-9))
        }
    }

    @Test("NEGATIVE CONTROL: a close-hauled heading is NOT a broad reach")
    func closeHauledIsNotABroadReach() {
        // The defect: the old implementation rotated by π − noGo, returning
        // headings 135° off the wind. That is nearly downwind, and it is what
        // an assertion phrased only as "the angle is consistent on both tacks"
        // would have accepted.
        for tack in Tack.allCases {
            let off = degreesOffWind(northerly.closeHauledHeading(tack), northerly)
            #expect(off < 90)  // upwind of the beam at all
            #expect(!isApprox(off, 135, absolute: 1.0))
        }
    }

    @Test("the two tacks are mirror images across the wind axis")
    func tacksAreMirrored() {
        let s = northerly.closeHauledHeading(.starboard)
        let p = northerly.closeHauledHeading(.port)
        // Same component into the wind, opposite across it.
        #expect(
            isApprox(
                Vector2D.dot(s, northerly.fromDirection),
                Vector2D.dot(p, northerly.fromDirection), absolute: 1e-12))
        #expect(isApprox(s.dx, -p.dx, absolute: 1e-12))
        #expect(isApprox(s.dy, p.dy, absolute: 1e-12))
        // And they are genuinely distinct headings.
        #expect(!isApprox(s.dx, p.dx, absolute: 1e-6))
    }

    @Test("close-hauled headings are unit vectors")
    func closeHauledIsNormalised() {
        for tack in Tack.allCases {
            #expect(isApprox(northerly.closeHauledHeading(tack).magnitude, 1, relative: 1e-12))
        }
    }

    // MARK: - tackingAngle

    @Test(
        "a course outside the no-go zone needs no tacking",
        arguments: [50.0, 60.0, 90.0, 135.0, 180.0])
    func courseOutsideNoGoNeedsNoTacking(courseDegrees: Double) {
        let axis = courseAxis(offWindDegrees: courseDegrees)
        #expect(isApprox(northerly.tackingAngle(towards: axis), 0, absolute: 1e-12))
    }

    @Test(
        "a course inside the no-go zone requires tacking at noGo + alpha",
        arguments: [0.0, 10.0, 20.0, 30.0, 44.0])
    func courseInsideNoGoRequiresTacking(alphaDegrees: Double) {
        let axis = courseAxis(offWindDegrees: alphaDegrees)
        let θ = northerly.tackingAngle(towards: axis) * 180 / .pi
        #expect(isApprox(θ, 45 + alphaDegrees, absolute: 1e-9))
    }

    @Test(
        "NEGATIVE CONTROL: both legs must clear the no-go zone",
        arguments: [0.0, 10.0, 20.0, 30.0, 44.0])
    func bothLegsClearTheNoGoZone(alphaDegrees: Double) {
        // The physical control. The old formula returned noGo − α, which put
        // one leg at α − θ = 2α − noGo off the wind — inside the zone, and at
        // α = 20° that is 5° from dead upwind. A boat cannot sail it.
        //
        // Legs sit at α + θ and |α − θ| from the wind; both must be ≥ noGo.
        let axis = courseAxis(offWindDegrees: alphaDegrees)
        let θ = northerly.tackingAngle(towards: axis) * 180 / .pi
        let noGo = 45.0

        #expect(alphaDegrees + θ >= noGo - 1e-9)
        #expect(abs(alphaDegrees - θ) >= noGo - 1e-9)
    }

    @Test("NEGATIVE CONTROL: the superseded formula puts a leg inside the no-go zone")
    func supersededFormulaIsUnsailable() {
        // Pinned so the sign cannot quietly flip back. noGo − α at α = 20°
        // gives θ = 25°, and |20 − 25| = 5° off the wind.
        let alpha = 20.0, noGo = 45.0
        let oldθ = noGo - alpha
        #expect(abs(alpha - oldθ) < noGo)  // un-sailable, which is the bug
    }

    @Test("tacking angle is symmetric in which side of the wind the course lies")
    func tackingAngleIsSideSymmetric() {
        // Rotating the course to the other side of the wind must not change
        // how far off the course the boat has to sail.
        for degrees in [10.0, 25.0, 40.0] {
            let left = northerly.tackingAngle(towards: courseAxis(offWindDegrees: degrees))
            let right = northerly.tackingAngle(towards: courseAxis(offWindDegrees: -degrees))
            #expect(isApprox(left, right, absolute: 1e-12))
        }
    }

    // MARK: - Tack

    @Test("tack signs and opposites are consistent")
    func tackAlgebra() {
        #expect(Tack.starboard.sign == 1)
        #expect(Tack.port.sign == -1)
        #expect(Tack.starboard.opposite == .port)
        #expect(Tack.port.opposite == .starboard)
        #expect(Tack.starboard.opposite.opposite == .starboard)
    }

    // MARK: - Helpers

    /// A course whose direction sits `offWindDegrees` from the direction the
    /// wind blows from. Positive rotates toward +x.
    private func courseAxis(offWindDegrees: Double) -> CourseAxis {
        let dir = Vector2D(dx: 0, dy: 1).rotated(by: offWindDegrees * .pi / 180)
        return CourseAxis(origin: .zero, destination: Point2D(x: dir.dx * 100, y: dir.dy * 100))
    }
}
