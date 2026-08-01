//
//  GeometryTests.swift
//  SailingCoreTests
//
//  The frame and sign conventions everything else depends on. Getting one of
//  these backwards produces plausible-looking garbage everywhere downstream,
//  which is why they are pinned explicitly rather than assumed.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("Geometry")
struct GeometryTests {

    // MARK: - Vector algebra

    @Test("perpendicularLeft is a +90 degree rotation; perpendicularRight is -90")
    func perpendicularsRotateCorrectly() {
        let v = Vector2D(dx: 3, dy: 4)
        let left = v.perpendicularLeft()
        let right = v.perpendicularRight()

        // Left turn: cross product positive (counter-clockwise).
        #expect(Vector2D.cross(v, left) > 0)
        #expect(Vector2D.cross(v, right) < 0)
        // Both orthogonal and length-preserving.
        #expect(isApprox(Vector2D.dot(v, left), 0, absolute: 1e-12))
        #expect(isApprox(Vector2D.dot(v, right), 0, absolute: 1e-12))
        #expect(isApprox(left.magnitude, v.magnitude, relative: 1e-12))
        // And they are opposites of each other.
        #expect(isApprox(left.dx, -right.dx, absolute: 1e-12))
        #expect(isApprox(left.dy, -right.dy, absolute: 1e-12))
    }

    @Test(
        "rotation preserves length and composes additively",
        arguments: [0.0, 0.3, 1.0, 2.5, -0.7, .pi])
    func rotationIsAnIsometry(angle: Double) {
        let v = Vector2D(dx: 3, dy: -4)
        let r = v.rotated(by: angle)
        #expect(isApprox(r.magnitude, 5, relative: 1e-12))
        // Rotating twice by θ equals rotating once by 2θ.
        #expect(
            isApprox(
                v.rotated(by: angle).rotated(by: angle).dx, v.rotated(by: 2 * angle).dx,
                absolute: 1e-9))
    }

    @Test("negative control: rotating by a nonzero angle actually moves the vector")
    func rotationIsNotIdentity() {
        // Without this, every rotation assertion above is satisfied by a
        // function that returns its input unchanged.
        let v = Vector2D(dx: 1, dy: 0)
        #expect(!isApprox(v.rotated(by: .pi / 2).dx, v.dx, absolute: 1e-6))
        #expect(isApprox(v.rotated(by: .pi / 2).dy, 1, absolute: 1e-12))
    }

    @Test("normalizing the zero vector yields zero rather than NaN")
    func zeroVectorNormalizesSafely() {
        // A NaN escaping here would propagate silently through the whole
        // heading field, so the degenerate case is pinned deliberately.
        let n = Vector2D.zero.normalized()
        #expect(n == .zero)
        #expect(!n.dx.isNaN && !n.dy.isNaN)
    }

    // MARK: - CourseAxis

    @Test("the course frame is orthonormal and right-handed")
    func courseFrameIsOrthonormal() {
        let axis = CourseAxis(origin: Point2D(x: -4, y: 9), destination: Point2D(x: 20, y: 16))
        #expect(isApprox(axis.u.magnitude, 1, relative: 1e-12))
        #expect(isApprox(axis.n.magnitude, 1, relative: 1e-12))
        #expect(isApprox(Vector2D.dot(axis.u, axis.n), 0, absolute: 1e-12))
        // n is u rotated counter-clockwise, so the cross product is +1.
        // Per AGENTS.md, positive n is to PORT when sailing A -> B.
        #expect(isApprox(Vector2D.cross(axis.u, axis.n), 1, absolute: 1e-12))
    }

    @Test("A maps to course origin and B to (L, 0)")
    func endpointsMapToCanonicalCoordinates() {
        let axis = CourseAxis(origin: Point2D(x: 5, y: 5), destination: Point2D(x: 25, y: 5))
        #expect(isApprox(axis.toCourse(axis.origin), .zero, absolute: 1e-12))
        #expect(isApprox(axis.toCourse(axis.destination), Point2D(x: 20, y: 0), absolute: 1e-12))
        #expect(isApprox(axis.length, 20, relative: 1e-12))
    }

    @Test(
        "world <-> course round-trips through a rotated, translated frame",
        arguments: [
            Point2D(x: 0, y: 0), Point2D(x: 13, y: -21), Point2D(x: -8, y: 3),
            Point2D(x: 100, y: 100),
        ])
    func frameRoundTrips(p: Point2D) {
        let axis = CourseAxis(origin: Point2D(x: 2, y: 11), destination: Point2D(x: 32, y: -19))
        #expect(isApprox(axis.fromCourse(axis.toCourse(p)), p, absolute: 1e-9))
    }

    @Test("negative control: the conversion is not the identity for a rotated frame")
    func conversionIsNotIdentity() {
        // A rotated axis must actually change coordinates. If toCourse were
        // accidentally a pass-through, every round-trip test above would still
        // pass — this is what rules that out.
        let axis = CourseAxis(origin: Point2D(x: 10, y: 10), destination: Point2D(x: 20, y: 20))
        let p = Point2D(x: 30, y: 5)
        #expect(!isApprox(axis.toCourse(p), p, absolute: 1e-6))
    }

    // MARK: - PlanarIsometry

    @Test("reflections are involutions", arguments: [-10.0, 0.0, 3.5, 42.0])
    func reflectionsAreInvolutions(offset: Double) {
        let p = Point2D(x: 7, y: -2)
        let horizontal = PlanarIsometry.reflectionAcrossHorizontal(b: offset)
        let vertical = PlanarIsometry.reflectionAcrossVertical(a: offset)

        #expect(isApprox(horizontal.apply(horizontal.apply(p)), p, absolute: 1e-12))
        #expect(isApprox(vertical.apply(vertical.apply(p)), p, absolute: 1e-12))
    }

    @Test("negative control: a reflection is not the identity off its axis")
    func reflectionMovesPointsOffItsAxis() {
        let h = PlanarIsometry.reflectionAcrossHorizontal(b: 0)
        #expect(!isApprox(h.apply(Point2D(x: 1, y: 5)), Point2D(x: 1, y: 5), absolute: 1e-6))
        // ...but fixes points that lie on it.
        #expect(isApprox(h.apply(Point2D(x: 1, y: 0)), Point2D(x: 1, y: 0), absolute: 1e-12))
    }

    @Test("compose applies right-to-left: (a∘b)(p) == a(b(p))")
    func composeAppliesRightToLeft() {
        // Composition order is load-bearing for the unfolding (invariant I3),
        // where reflecting in original vs covering coordinates gives different
        // maps. Pin the convention here so a change there is caught.
        let a = PlanarIsometry.reflectionAcrossHorizontal(b: 3)
        let b = PlanarIsometry.reflectionAcrossVertical(a: 5)
        let p = Point2D(x: 1, y: 1)
        #expect(isApprox(a.compose(b).apply(p), a.apply(b.apply(p)), absolute: 1e-12))
    }

    @Test("negative control: composition does not commute for two parallel reflections")
    func compositionDoesNotCommute() {
        // Note the reflections must be *parallel* to expose non-commutativity.
        // A horizontal and a vertical reflection act on independent components
        // and therefore do commute — using that pair here would assert nothing.
        //
        // Two horizontal reflections compose to a translation whose sign
        // depends on the order: H_b1∘H_b2 translates by 2(b1−b2), the reverse
        // by 2(b2−b1). This is exactly the structure the unfolding relies on
        // (invariant I3), which is why the order is worth pinning.
        let a = PlanarIsometry.reflectionAcrossHorizontal(b: 3)
        let b = PlanarIsometry.reflectionAcrossHorizontal(b: 7)
        let p = Point2D(x: 1, y: 1)

        let forward = a.compose(b).apply(p)
        let reverse = b.compose(a).apply(p)
        #expect(!isApprox(forward, reverse, absolute: 1e-6))
        // The two results differ by 4(b2 − b1) = 16 in the cross-track component.
        #expect(isApprox(reverse.y - forward.y, 16, absolute: 1e-12))
    }

    @Test("two parallel reflections compose to a pure translation")
    func parallelReflectionsComposeToTranslation() {
        let a = PlanarIsometry.reflectionAcrossHorizontal(b: 3)
        let b = PlanarIsometry.reflectionAcrossHorizontal(b: 7)
        // Translation by 2(3 − 7) = −8 in n, leaving s untouched.
        for p in [Point2D(x: 0, y: 0), Point2D(x: 5, y: -2), Point2D(x: -1, y: 11)] {
            let q = a.compose(b).apply(p)
            #expect(isApprox(q.x, p.x, absolute: 1e-12))
            #expect(isApprox(q.y, p.y - 8, absolute: 1e-12))
        }
    }

    @Test("identity composes as a no-op on both sides")
    func identityIsNeutral() {
        let a = PlanarIsometry.reflectionAcrossHorizontal(b: 3)
        let p = Point2D(x: 4, y: -6)
        #expect(isApprox(a.compose(.identity).apply(p), a.apply(p), absolute: 1e-12))
        #expect(isApprox(PlanarIsometry.identity.compose(a).apply(p), a.apply(p), absolute: 1e-12))
    }
}
