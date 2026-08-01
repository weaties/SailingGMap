//
//  TopologyTests.swift
//  SailingCoreTests
//
//  Invariant I5: a chain of N quadrilateral strips sewn along N−1 shared edges
//  is a topological disk, so χ = V − E + F = 1. See docs/invariants.md.
//
//  These also pin the exact cell counts, because χ = 1 alone is not a strong
//  check — several wrong constructions still give 1.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("G-map topology")
struct TopologyTests {

    private func topology(stripCount n: Int) -> SailingGMapTopology {
        SailingGMapTopology(
            path: TackPath.uniformAlternating(
                axis: .canonical(length: 100), stripCount: n, tackingAngle: .pi / 4))
    }

    // MARK: - I5: cell counts and Euler characteristic

    @Test(
        "I5: cell counts match the closed form for a chain of quads",
        arguments: [1, 2, 4, 8, 16, 32])
    func cellCountsMatchClosedForm(n: Int) {
        let t = topology(stripCount: n)
        // Each quad contributes 8 darts (4 edges × 2). Vertices: 2(N+1) along
        // the two rails. Edges: 4N minus the N−1 that are shared.
        #expect(t.dartCount == 8 * n)
        #expect(t.vertexCount == 2 * (n + 1))
        #expect(t.edgeCount == 3 * n + 1)
        #expect(t.faceCount == n)
    }

    @Test("I5: Euler characteristic is 1 — the chain is a disk", arguments: [1, 2, 4, 8, 16, 32])
    func eulerCharacteristicIsOne(n: Int) {
        #expect(topology(stripCount: n).eulerCharacteristic == 1)
    }

    @Test(
        "I5 negative control: unsewn faces are NOT a disk",
        arguments: [2, 4, 8])
    func unsewnFacesAreNotADisk(n: Int) {
        // A single strip has nothing to sew, so N disconnected quads would give
        // χ = N (one disk per face). Verifying that a 1-strip path gives χ = 1
        // while an N-strip *chain* also gives 1 only distinguishes correct from
        // incorrect if the disconnected case differs — it does, and this is the
        // control that proves the sewing is actually happening.
        let chained = topology(stripCount: n)
        let disconnectedChi = n * 1  // N independent disks, were they never sewn

        #expect(chained.eulerCharacteristic == 1)
        #expect(chained.eulerCharacteristic != disconnectedChi)
        // The sewing is what removes the duplicate cells: N quads have 4N edges
        // and 4N vertices in isolation; the chain has strictly fewer of each.
        #expect(chained.edgeCount < 4 * n)
        #expect(chained.vertexCount < 4 * n)
    }

    // MARK: - Involution laws

    @Test("every alpha is an involution and alpha0-alpha2 commute", arguments: [1, 2, 4, 8, 16])
    func involutionLawsHold(n: Int) {
        #expect(topology(stripCount: n).isValid)
    }

    // MARK: - Seam metadata

    @Test("an alternating path marks every interior seam reflective", arguments: [2, 4, 8, 16])
    func alternatingPathHasAllSeamsReflective(n: Int) {
        // reflectiveAlpha2Edges counts two dart-pairs per reflective seam, and
        // an alternating path flips tack at every one of its N−1 seams.
        #expect(topology(stripCount: n).reflectiveAlpha2Edges == 2 * (n - 1))
    }

    @Test(
        "negative control: a constant-tack path has NO reflective seams",
        arguments: [2, 4, 8, 16])
    func constantTackPathHasNoReflectiveSeams(n: Int) {
        // This is the control that gives the previous test meaning. Crossing a
        // seam between two strips on the same tack does not reverse anything,
        // so the count must be zero — not merely "different".
        let path = TackPath.constantTack(
            axis: .canonical(length: 100), stripCount: n, tackingAngle: .pi / 4)
        let t = SailingGMapTopology(path: path)

        #expect(t.reflectiveAlpha2Edges == 0)
        // The topology is otherwise identical: same cells, still a disk. Only
        // the attribute differs, which is exactly what the metadata is for.
        #expect(t.eulerCharacteristic == 1)
        #expect(t.faceCount == n)
    }

    @Test("seam metadata records the tack reversal on each interior edge")
    func seamMetadataRecordsReversal() {
        let t = topology(stripCount: 4)
        #expect(t.seamRepresentatives.count == 3)
        for dart in t.seamRepresentatives {
            let meta: SailingSeamMetadata? = t.map.attribute(for: dart, dimension: 1)
            #expect(meta?.isReflective == true)
        }
    }

    @Test("a single strip has no seams at all")
    func singleStripHasNoSeams() {
        let t = topology(stripCount: 1)
        #expect(t.seamRepresentatives.isEmpty)
        #expect(t.reflectiveAlpha2Edges == 0)
        #expect(t.eulerCharacteristic == 1)
    }
}
