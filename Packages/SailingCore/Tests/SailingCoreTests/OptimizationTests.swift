//
//  OptimizationTests.swift
//  SailingCoreTests
//
//  Invariant I8: the cost terms' dependence on strip count. Length is constant
//  in N (I1), the turn count grows, the cross-track swing shrinks — and it is
//  that competition, not length, that produces an interior optimum.
//

import Foundation
import Testing

@testable import SailingCore

@Suite("Optimization")
struct OptimizationTests {

    private let axis = CourseAxis.canonical(length: 100)
    private let θ = Double.pi / 4

    private func path(_ n: Int) -> TackPath {
        TackPath.uniformAlternating(axis: axis, stripCount: n, tackingAngle: θ)
    }

    // MARK: - Cost breakdown

    @Test("pure length reproduces the closed form and nothing else")
    func pureLengthBreakdown() {
        let b = TackingCost.pureLength.breakdown(path(8))
        #expect(isApprox(b.length, 100 / cos(θ), relative: 1e-12))
        #expect(b.turns == 0)
        #expect(b.headingChange == 0)
        #expect(b.swing == 0)
        #expect(isApprox(b.total, b.length, relative: 1e-12))
    }

    @Test("the turn term counts N-1 reversals", arguments: [2, 4, 8, 16, 32])
    func turnTermCountsReversals(n: Int) {
        let cost = TackingCost(lengthWeight: 0, turnPenalty: 3)
        #expect(isApprox(cost.breakdown(path(n)).turns, 3 * Double(n - 1), relative: 1e-12))
    }

    @Test("the heading-change term is (N-1)·(2θ)² on the rhumb line", arguments: [2, 4, 8, 16])
    func headingChangeTermIsQuadratic(n: Int) {
        let cost = TackingCost(lengthWeight: 0, headingChangeWeight: 1)
        let expected = Double(n - 1) * (2 * θ) * (2 * θ)
        #expect(isApprox(cost.breakdown(path(n)).headingChange, expected, relative: 1e-12))
    }

    @Test("the swing term shrinks as 1/N", arguments: [2, 4, 8, 16, 32])
    func swingTermShrinks(n: Int) {
        let cost = TackingCost(lengthWeight: 0, swingPenalty: 1)
        #expect(isApprox(cost.breakdown(path(n)).swing, (100 / Double(n)) * tan(θ), relative: 1e-9))
    }

    // MARK: - I8: length contributes no gradient in N

    @Test("I8: the length term is identical across strip counts")
    func lengthTermIsConstantInStripCount() {
        let cost = TackingCost.pureLength
        let lengths = [2, 4, 8, 16, 32, 64].map { cost.breakdown(path($0)).length }
        #expect(maxDeviation(lengths, from: 100 / cos(θ)) < 1e-9)
    }

    @Test("I8 negative control: the turn and swing terms are NOT constant in N")
    func turnAndSwingDoVaryWithStripCount() {
        // The control that gives the previous test meaning: if every term were
        // constant, `uniformOptimum` could not have an interior minimum at all
        // and the sweep would be theatre.
        let cost = TackingCost(lengthWeight: 0, turnPenalty: 1, swingPenalty: 1)
        let turns = [2, 8, 32].map { cost.breakdown(path($0)).turns }
        let swings = [2, 8, 32].map { cost.breakdown(path($0)).swing }

        #expect(turns[0] < turns[1] && turns[1] < turns[2])  // grows
        #expect(swings[0] > swings[1] && swings[1] > swings[2])  // shrinks
    }

    // MARK: - Sweep

    @Test("uniformOptimum finds an interior optimum when turn and swing compete")
    func interiorOptimumExists() {
        let cost = TackingCost(lengthWeight: 1, turnPenalty: 2, swingPenalty: 1)
        let result = Optimization.uniformOptimum(
            axis: axis, tackingAngle: θ, cost: cost, minStrips: 2, maxStrips: 64)

        // Interior: neither endpoint of the swept range.
        #expect(result.stripCount > 2)
        #expect(result.stripCount < 64)
        #expect(result.stripCount.isMultiple(of: 2))

        // And it really is the minimum of the family it swept.
        let sweep = stride(from: 2, through: 64, by: 2).map {
            (n: $0, j: cost.evaluate(path($0)))
        }
        #expect(isApprox(result.cost, sweep.map(\.j).min() ?? 0, relative: 1e-12))
        #expect(result.stripCount == sweep.min(by: { $0.j < $1.j })?.n)
    }

    @Test("negative control: with no turn or swing penalty every N ties")
    func pureLengthHasNoInteriorOptimum() {
        // Because length is invariant in N (I1), a pure-length sweep cannot
        // discriminate — every candidate has the same cost. This is why the
        // README's claim that "the turn penalty favors fewer bands while the
        // cross-track swing favors more" is the entire mechanism.
        let cost = TackingCost.pureLength
        let costs = stride(from: 2, through: 32, by: 2).map { cost.evaluate(path($0)) }
        #expect(maxDeviation(costs, from: 100 / cos(θ)) < 1e-9)
    }

    @Test("a dominant turn penalty drives the optimum to the smallest count")
    func dominantTurnPenaltyPrefersFewestStrips() {
        let cost = TackingCost(lengthWeight: 1, turnPenalty: 1000, swingPenalty: 0)
        #expect(
            Optimization.uniformOptimum(axis: axis, tackingAngle: θ, cost: cost).stripCount == 2)
    }

    @Test("a dominant swing penalty drives the optimum to the largest count")
    func dominantSwingPenaltyPrefersMostStrips() {
        let cost = TackingCost(lengthWeight: 1, turnPenalty: 0, swingPenalty: 1000)
        let result = Optimization.uniformOptimum(
            axis: axis, tackingAngle: θ, cost: cost, minStrips: 2, maxStrips: 32)
        #expect(result.stripCount == 32)
    }
}
