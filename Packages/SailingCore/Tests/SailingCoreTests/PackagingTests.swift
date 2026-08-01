//
//  PackagingTests.swift
//  SailingCoreTests
//
//  Smoke tests for the extraction itself: the package is importable, its public
//  surface is reachable from outside the module, and the frame conversion that
//  everything else depends on round-trips.
//
//  The mathematical suite proper lands separately; these exist so `swift test`
//  is meaningful the moment the package exists, and so a broken extraction
//  fails loudly rather than at the first real test someone writes.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("Packaging")
struct PackagingTests {

    @Test("the public surface the app depends on is reachable from outside the module")
    func publicSurfaceIsReachable() {
        // Each of these is used by SailingGMapViewModel. If the extraction left
        // one of them internal, the app target stops compiling — catching it
        // here gives a clearer failure than a link error in the app build.
        let axis = CourseAxis.canonical(length: 100)
        let path = TackPath.uniformAlternating(axis: axis, stripCount: 4, tackingAngle: .pi / 4)
        let field = AnyProgressField(LinearProgressField(axis: axis, halfWidth: 50))
        let generalized = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 4, tackingAngle: .pi / 4)
        let topology = SailingGMapTopology(path: path)
        let cost = TackingCost.pureLength

        #expect(path.strips.count == 4)
        #expect(generalized.tacks.count == 4)
        #expect(topology.faceCount == 4)
        #expect(cost.evaluate(path) > 0)
        #expect(Foliation.levelCurves(of: field, count: 3).count == 3)
        #expect(!Unfolding.unfoldByHorizontalReflections(of: path).isEmpty)
        #expect(Optimization.uniformOptimum(axis: axis, tackingAngle: .pi / 4, cost: cost).cost > 0)
    }

    @Test(
        "world <-> course frame conversion round-trips",
        arguments: [
            Point2D(x: 0, y: 0), Point2D(x: 50, y: 0), Point2D(x: 10, y: -7),
            Point2D(x: -3, y: 42), Point2D(x: 100, y: 100),
        ])
    func frameRoundTrips(p: Point2D) {
        // A rotated, translated axis so the conversion is non-trivial: if
        // toCourse/fromCourse were accidentally identity, this would catch it.
        let axis = CourseAxis(origin: Point2D(x: 5, y: -2), destination: Point2D(x: 45, y: 38))
        let back = axis.fromCourse(axis.toCourse(p))
        // Absolute: components pass through zero, so a relative bound degenerates.
        #expect(isApprox(back, p, absolute: 1e-9))
    }

    @Test("the course frame is right-handed: n is u rotated 90 degrees counter-clockwise")
    func courseFrameOrientation() {
        // Sign convention, per AGENTS.md: positive n is to PORT sailing A -> B.
        // Getting this backwards silently mirrors every path in the app.
        let axis = CourseAxis.canonical(length: 10)
        #expect(isApprox(Vector2D.cross(axis.u, axis.n), 1, absolute: 1e-12))
        #expect(isApprox(Vector2D.dot(axis.u, axis.n), 0, absolute: 1e-12))
    }
}
