//
//  TackPathTests.swift
//  SailingCoreTests
//
//  Invariants I1 (length independent of strip count) and I2 (arrival requires
//  balanced cross-track displacement). See docs/invariants.md.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("TackPath")
struct TackPathTests {

    // MARK: - I1: sailed length is L / cos θ, independent of N

    @Test(
        "I1: sailed length matches the closed form for every strip count",
        arguments: [2, 4, 8, 16, 32, 64], [15.0, 30.0, 45.0, 60.0, 75.0])
    func sailedLengthMatchesClosedForm(n: Int, degrees: Double) {
        let axis = CourseAxis.canonical(length: 100)
        let θ = degrees * .pi / 180
        let path = TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)

        // Relative 1e-12: a handful of double operations, per the AGENTS.md
        // tolerance table for closed-form identities.
        #expect(isApprox(path.sailedLength(), axis.length / cos(θ), relative: 1e-12))
    }

    @Test("I1: length is invariant under strip count — the whole point of the unfolding")
    func lengthIsInvariantUnderStripCount() {
        let axis = CourseAxis.canonical(length: 100)
        let θ = Double.pi / 4
        let lengths = [2, 4, 8, 16, 32, 64].map {
            TackPath.uniformAlternating(axis: axis, stripCount: $0, tackingAngle: θ).sailedLength()
        }
        let reference = axis.length / cos(θ)
        #expect(maxDeviation(lengths, from: reference) < 1e-9)
    }

    @Test("I1 negative control: a degenerate tacking angle diverges rather than lying")
    func degenerateAngleDiverges() {
        // θ → π/2 means sailing perpendicular to the course: the path never
        // arrives and its length is unbounded. The guard must surface that as
        // .infinity, NOT clamp to a large finite number — a finite answer here
        // would silently feed a cost model that then "optimizes" nonsense.
        let axis = CourseAxis.canonical(length: 100)
        let path = TackPath.uniformAlternating(axis: axis, stripCount: 4, tackingAngle: .pi / 2)
        #expect(path.sailedLength().isInfinite)
    }

    // MARK: - I2: arrival requires balanced cross-track displacement

    @Test(
        "I2: an even strip count lands on B", arguments: [2, 4, 8, 16, 32])
    func evenStripCountArrives(n: Int) {
        let axis = CourseAxis.canonical(length: 100)
        let path = TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: .pi / 4)
        // Absolute: the quantity is expected to be zero, where relative error
        // is meaningless.
        #expect(isApprox(path.arrivalOffset(), 0, absolute: 1e-9))
    }

    @Test(
        "I2 negative control: an odd strip count does NOT land on B",
        arguments: [1, 3, 5, 7, 9])
    func oddStripCountDoesNotArrive(n: Int) {
        // Σ σᵢ wᵢ tan θ leaves exactly one strip's worth of offset unbalanced.
        // The model must report this rather than clamping it away: an unbalanced
        // path is a real (infeasible) path, not an error to swallow.
        let axis = CourseAxis.canonical(length: 100)
        let θ = Double.pi / 4
        let path = TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)
        let expected = (axis.length / Double(n)) * tan(θ)

        #expect(!isApprox(path.arrivalOffset(), 0, absolute: 1e-9))
        #expect(isApprox(abs(path.arrivalOffset()), expected, relative: 1e-9))
    }

    @Test("I2 negative control: a constant-tack path drifts by the full course length")
    func constantTackDriftsMaximally() {
        // Every strip pushing the same way: offset accumulates to L·tan θ.
        // At θ = 45° that is the entire course length off the rhumb line.
        let axis = CourseAxis.canonical(length: 100)
        let θ = Double.pi / 4
        let path = TackPath.constantTack(axis: axis, stripCount: 8, tackingAngle: θ)

        #expect(isApprox(path.arrivalOffset(), axis.length * tan(θ), relative: 1e-9))
        #expect(!isApprox(path.arrivalOffset(), 0, absolute: 1e-9))
    }

    // MARK: - Cross-track excursion

    @Test(
        "cross-track peak is one strip width of rise", arguments: [2, 4, 8, 16, 32])
    func crossTrackPeakIsOneStripRise(n: Int) {
        let axis = CourseAxis.canonical(length: 100)
        let θ = Double.pi / 4
        let path = TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)
        // The zig-zag turns at every strip boundary, so |n| never exceeds the
        // rise across a single strip. This is what makes the swing term shrink
        // with N and lets an interior optimum exist (I8).
        #expect(isApprox(path.crossTrackPeak(), (axis.length / Double(n)) * tan(θ), relative: 1e-9))
    }

    @Test("cross-track peak strictly decreases as strips are added")
    func crossTrackPeakDecreasesWithStripCount() {
        let axis = CourseAxis.canonical(length: 100)
        let peaks = [2, 4, 8, 16, 32].map {
            TackPath.uniformAlternating(axis: axis, stripCount: $0, tackingAngle: .pi / 4)
                .crossTrackPeak()
        }
        #expect(zip(peaks, peaks.dropFirst()).allSatisfy { $0 > $1 })
    }

    // MARK: - Construction

    @Test("uniformAlternating produces contiguous strips with alternating tacks")
    func uniformAlternatingStructure() {
        let axis = CourseAxis.canonical(length: 100)
        let path = TackPath.uniformAlternating(
            axis: axis, stripCount: 8, tackingAngle: .pi / 4, startingTack: .starboard)

        #expect(path.strips.count == 8)
        #expect(path.strips.first?.sStart == 0)
        #expect(isApprox(path.strips.last?.sEnd ?? 0, 100, relative: 1e-12))
        // Contiguous: no gaps, no overlaps.
        for (a, b) in zip(path.strips, path.strips.dropFirst()) {
            #expect(isApprox(a.sEnd, b.sStart, absolute: 1e-12))
        }
        // Alternating, starting starboard.
        for (i, strip) in path.strips.enumerated() {
            #expect(strip.tack == (i.isMultiple(of: 2) ? .starboard : .port))
        }
    }

    @Test("world vertices are the course vertices lifted through the axis")
    func worldVerticesTrackCourseVertices() {
        // A rotated, offset axis so an accidental identity transform shows up.
        let axis = CourseAxis(origin: Point2D(x: 7, y: -3), destination: Point2D(x: 47, y: 37))
        let path = TackPath.uniformAlternating(axis: axis, stripCount: 4, tackingAngle: .pi / 6)

        for (course, world) in zip(path.courseVertices(), path.worldVertices()) {
            #expect(isApprox(axis.toCourse(world), course, absolute: 1e-9))
        }
    }
}
