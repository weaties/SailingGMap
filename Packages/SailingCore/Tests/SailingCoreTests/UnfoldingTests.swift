//
//  UnfoldingTests.swift
//  SailingCoreTests
//
//  Invariant I3: the unfolded polyline is the *isometric image* of the tacking
//  path. See docs/invariants.md and issues #8, #9.
//
//  A note on what is NOT asserted here, because it cost an afternoon to learn:
//  the unfolding straightens *every* tack sequence, not only alternating ones.
//  The construction reflects each leg so all legs point the same way, so the
//  result is always the segment (0,0) -> (L, L·tan θ). "A constant-tack path
//  must not unfold straight" is mathematically false — a constant-tack path in
//  course coordinates is already a straight line. See #7 for the full working.
//
//  So straightness is unconditional and therefore useless as a test. What has
//  real content is that the lift is an isometry OF THE ACTUAL PATH: preserve
//  leg lengths, match the sailed distance, stay anchored at A. Those fail when
//  the widths or the angle are wrong; straightness does not.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("Unfolding")
struct UnfoldingTests {

    private let axis = CourseAxis.canonical(length: 100)

    private func alternating(_ n: Int, _ θ: Double) -> TackPath {
        TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)
    }

    private func path(_ tacks: [Tack], _ θ: Double) -> TackPath {
        let w = axis.length / Double(tacks.count)
        let strips = tacks.enumerated().map { i, t in
            Strip(id: i, sStart: Double(i) * w, sEnd: Double(i + 1) * w, tack: t)
        }
        return TackPath(axis: axis, strips: strips, tackingAngle: θ)
    }

    // MARK: - I3.1 — the lift is an isometry of the actual path

    @Test(
        "I3.1: unfolding preserves every leg's length",
        arguments: [2, 4, 8, 16, 32], [15.0, 30.0, 45.0, 60.0, 75.0])
    func unfoldingPreservesLegLengths(n: Int, degrees: Double) {
        let θ = degrees * .pi / 180
        let p = alternating(n, θ)
        #expect(Unfolding.unfoldingIsIsometric(of: p))

        let original = p.courseVertices()
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: p)
        #expect(original.count == unfolded.count)
        for i in 1..<original.count {
            let before = (original[i] - original[i - 1]).magnitude
            let after = (unfolded[i] - unfolded[i - 1]).magnitude
            #expect(isApprox(before, after, relative: 1e-12))
        }
    }

    @Test(
        "I3.1 NEGATIVE CONTROL: a straight polyline with the wrong slope is NOT the isometric lift",
        arguments: [15.0, 30.0, 45.0, 60.0])
    func wrongSlopeIsRejectedEvenThoughStraight(degrees: Double) {
        // The whole point of preferring the isometry check over straightness.
        // This polyline is perfectly straight — `unfoldedIsStraight` accepts it
        // — but its legs are the wrong length for the path, so it is not the
        // lift of anything. A test built on straightness alone cannot tell.
        let θ = degrees * .pi / 180
        let p = alternating(8, θ)
        let w = axis.length / 8
        let wrong = (0...8).map { k in
            Point2D(x: Double(k) * w, y: Double(k) * w * tan(θ / 2))  // θ/2, not θ
        }

        #expect(Unfolding.unfoldedIsStraight(wrong))  // straight, yet wrong
        #expect(!Unfolding.legLengthsMatch(wrong, of: p))
    }

    @Test(
        "I3.2: the lifted segment has length L / cos θ",
        arguments: [2, 4, 8, 16, 32], [15.0, 30.0, 45.0, 60.0])
    func liftedLengthEqualsSailedLength(n: Int, degrees: Double) {
        let θ = degrees * .pi / 180
        let p = alternating(n, θ)
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: p)

        guard let first = unfolded.first, let last = unfolded.last else {
            Issue.record("unfolded polyline is empty")
            return
        }
        #expect(isApprox((last - first).magnitude, p.sailedLength(), relative: 1e-9))
    }

    @Test("I3.2 NEGATIVE CONTROL: a lift with an extra strip does not match the path's length")
    func mismatchedStripCountIsRejected() {
        let θ = Double.pi / 4
        let p = alternating(8, θ)
        // The lift of a *different* path (9 strips over the same course) is
        // still straight and still an isometry of its own path — but it is not
        // the lift of `p`, and the length check catches the substitution.
        let other = Unfolding.unfoldByHorizontalReflections(of: alternating(9, θ))
        #expect(!Unfolding.legLengthsMatch(other, of: p))
    }

    @Test("I3.3: the lift is anchored at A")
    func liftIsAnchoredAtOrigin() {
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: alternating(8, .pi / 4))
        #expect(isApprox(unfolded.first ?? Point2D(x: 9, y: 9), .zero, absolute: 1e-12))
    }

    // MARK: - Straightness (unconditional — documented, not a discriminator)

    @Test(
        "the unfolding straightens EVERY tack sequence, not only alternating ones",
        arguments: [
            [Tack.starboard, .port, .starboard, .port],
            [.starboard, .starboard, .starboard, .starboard],
            [.starboard, .starboard, .port, .port],
            [.starboard, .port, .port, .starboard],
            [.port, .starboard, .starboard, .port],
        ])
    func straightnessIsUnconditional(tacks: [Tack]) {
        // Pinned deliberately. This is the theorem, and it is the reason
        // straightness alone cannot serve as a correctness test: it is true for
        // every input, including inputs that never arrive at B.
        let p = path(tacks, .pi / 4)
        #expect(Unfolding.unfoldedIsStraight(Unfolding.unfoldByHorizontalReflections(of: p)))
    }

    // MARK: - I3.4 — cumulative isometries (issue #8)

    @Test(
        "I3.4: the per-leg isometries reproduce the unfolded polyline",
        arguments: [
            [Tack.starboard, .port, .starboard, .port],
            [.starboard, .port, .starboard, .port, .starboard, .port],
            [.starboard, .starboard, .port, .port],
            [.starboard, .port, .port, .starboard],
        ])
    func isometriesReproduceTheUnfolding(tacks: [Tack]) {
        // The composition-order defect: H∘Φ_prev reflects in covering
        // coordinates about an original-frame value and yields a lift that is
        // not even continuous across seams. Φ_prev∘H is the correct order.
        //
        // NOTE: a sequence with only ONE reversal (e.g. [S,S,P,P]) cannot
        // distinguish the two orders — with a single reflection there is
        // nothing to reorder. The multi-reversal cases above are what matter.
        let θ = Double.pi / 4
        let p = path(tacks, θ)
        let vertices = p.courseVertices()
        let lifts = Unfolding.cumulativeIsometries(of: p)
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: p)

        // Indexing: `cumulativeIsometries` returns N+1 entries with Φ[0] the
        // identity, so the isometry governing leg i is Φ[i+1], not Φ[i].
        #expect(lifts.count == p.strips.count + 1)
        #expect(lifts[0] == .identity)
        for i in 0..<p.strips.count {
            #expect(isApprox(lifts[i + 1].apply(vertices[i + 1]), unfolded[i + 1], absolute: 1e-9))
        }
    }

    @Test("I3.4 NEGATIVE CONTROL: the reversed composition order gives a different, broken lift")
    func reversedCompositionOrderIsBroken() {
        // Reconstructs the old H∘Φ_prev order locally and shows it disagrees.
        // Without this the corrected order could silently regress.
        let θ = Double.pi / 4
        let p = path([.starboard, .port, .starboard, .port], θ)
        let vertices = p.courseVertices()
        let tanθ = tan(θ)

        var broken: [Point2D] = [vertices[0]]
        var current = PlanarIsometry.identity
        var n = 0.0
        var σPrev = p.strips[0].tack.sign
        for (i, strip) in p.strips.enumerated() {
            let σ = strip.tack.sign
            if σ != σPrev {
                current = PlanarIsometry.reflectionAcrossHorizontal(b: n).compose(current)
            }
            broken.append(current.apply(vertices[i + 1]))
            n += σ * strip.width * tanθ
            σPrev = σ
        }

        let correct = Unfolding.unfoldByHorizontalReflections(of: p)
        #expect(zip(broken, correct).contains { !isApprox($0, $1, absolute: 1e-6) })
        // And the broken order is not even straight, unlike the correct one.
        #expect(!Unfolding.unfoldedIsStraight(broken))
        #expect(Unfolding.unfoldedIsStraight(correct))
    }

    @Test("a constant-tack path needs no reflections at all", arguments: [2, 4, 8, 16])
    func constantTackNeedsNoReflections(n: Int) {
        let p = TackPath.constantTack(axis: axis, stripCount: n, tackingAngle: .pi / 4)
        #expect(Unfolding.cumulativeIsometries(of: p).allSatisfy { $0 == .identity })
    }

    // MARK: - Degenerate inputs

    @Test("a single-strip path lifts to itself")
    func singleStripLiftsToItself() {
        let p = alternating(1, .pi / 4)
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: p)
        #expect(Unfolding.unfoldingIsIsometric(of: p))
        #expect(unfolded.count == 2)
    }

    @Test("a zero tacking angle lifts to the rhumb line")
    func zeroAngleLiftsToRhumbLine() {
        let unfolded = Unfolding.unfoldByHorizontalReflections(of: alternating(8, 0))
        #expect(unfolded.allSatisfy { isApprox($0.y, 0, absolute: 1e-12) })
        #expect(Unfolding.unfoldingIsIsometric(of: alternating(8, 0)))
    }

    @Test("an empty strip list produces a single anchored vertex")
    func emptyPathIsHandled() {
        let empty = TackPath(axis: axis, strips: [], tackingAngle: .pi / 4)
        #expect(Unfolding.unfoldByHorizontalReflections(of: empty).count == 1)
        #expect(Unfolding.cumulativeIsometries(of: empty).count == 1)
    }
}
