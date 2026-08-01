//
//  Optimization.swift
//  Sailing
//
//  Once the unfolding is in hand, the optimisation problem becomes
//  cleaner.  This module contains a *scaffolding* — not a complete
//  solver — for the kinds of cost functionals that naturally live on
//  combinatorial-map paths.
//
//  Three layers, increasing in expressiveness:
//
//  1.  Pure length, uniform tacking angle.
//      Total sailed length L_path = L / cos θ is independent of N — the
//      reflection-unfolding picture makes this obvious.  So pure length
//      gives no gradient over the strip count.
//
//  2.  Length + per-tack penalty + per-tack heading-change² penalty.
//          J = lengthWeight · L                       (sailed length)
//            + turnPenalty  · N_tacks                 (count of reversals)
//            + headingChangeWeight · Σ |Δθᵢ|²          (heaviness of each)
//            + swingPenalty · max|n|                  (corridor width)
//      With the rhumb-line prototype |Δθᵢ| ≡ 2θ at every turn and the
//      heading-change term collapses to `headingChangeWeight · (N−1) · 4θ²`.
//      On a curved foliation each turn's |Δθᵢ| is different.
//
//  3.  Foliation smoothness.
//          J += foliationSmoothnessWeight · ∫_Ω |Δs|² dA.
//      Pushes the progress field s toward a harmonic / quasi-affine
//      shape and keeps level curves from degenerating into nonsense.
//      Approximated by `ProgressField.laplacianL2Squared(...)`.
//
//  All four weights are optional; setting them all to zero except
//  `lengthWeight = 1` recovers the pure-length case.
//

import Foundation

// MARK: - Cost model

public struct TackingCost: Hashable, Codable, Sendable {
    public var lengthWeight: Double
    public var turnPenalty: Double
    public var headingChangeWeight: Double  // μ
    public var swingPenalty: Double
    public var foliationSmoothnessWeight: Double  // ν

    public init(
        lengthWeight: Double = 1,
        turnPenalty: Double = 0,
        headingChangeWeight: Double = 0,
        swingPenalty: Double = 0,
        foliationSmoothnessWeight: Double = 0
    ) {
        self.lengthWeight = lengthWeight
        self.turnPenalty = turnPenalty
        self.headingChangeWeight = headingChangeWeight
        self.swingPenalty = swingPenalty
        self.foliationSmoothnessWeight = foliationSmoothnessWeight
    }

    public static let pureLength = TackingCost(lengthWeight: 1)
}

// MARK: - CostBreakdown

/// Per-term breakdown of a cost evaluation; handy for UI display.
public struct CostBreakdown: Hashable, Codable {
    public var length: Double
    public var turns: Double
    public var headingChange: Double
    public var swing: Double
    public var foliationSmoothness: Double

    public var total: Double {
        length + turns + headingChange + swing + foliationSmoothness
    }
}

// MARK: - Evaluation on the rhumb-line TackPath

public extension TackingCost {
    func breakdown(_ path: TackPath) -> CostBreakdown {
        let L = lengthWeight * path.sailedLength()
        let N = max(0, path.strips.count - 1)
        let turns = turnPenalty * Double(N)
        // For the rhumb-line case |Δθᵢ| = 2θ at every reversal.
        let dθ = 2 * path.tackingAngle
        let head = headingChangeWeight * Double(N) * dθ * dθ
        let swing = swingPenalty * path.crossTrackPeak()
        return CostBreakdown(
            length: L, turns: turns,
            headingChange: head, swing: swing,
            foliationSmoothness: 0
        )
    }

    func evaluate(_ path: TackPath) -> Double { breakdown(path).total }
}

// MARK: - Evaluation on the GeneralizedTackPath + ProgressField

public extension TackingCost {
    func breakdown(
        _ path: GeneralizedTackPath,
        field: ProgressField
    ) -> CostBreakdown {
        // One integration, not three. sailedLength / headingChangesAtTurns /
        // crossTrackPeak each integrate independently, so asking for all three
        // — which is exactly what a breakdown does — integrated the trajectory
        // three times per call (issue #18).
        let m = path.metrics()
        let L = lengthWeight * m.sailedLength
        let N = max(0, path.tacks.count - 1)
        let turns = turnPenalty * Double(N)
        let head = headingChangeWeight * m.headingChanges.reduce(0) { $0 + $1 * $1 }
        let swing = swingPenalty * m.crossTrackPeak
        let fol = foliationSmoothnessWeight * field.laplacianL2Squared()
        return CostBreakdown(
            length: L, turns: turns,
            headingChange: head, swing: swing,
            foliationSmoothness: fol
        )
    }

    func evaluate(
        _ path: GeneralizedTackPath,
        field: ProgressField
    ) -> Double {
        breakdown(path, field: field).total
    }
}

// MARK: - Uniform-strip optimum (rhumb-line)

public enum Optimization {

    /// Sweep even strip counts and pick the minimiser of `cost` on the
    /// uniform alternating family.  The sailed length L/cos θ is invariant
    /// under N (the unfolding-invariance theorem), so any N-dependence
    /// comes from the turn / heading-change / swing terms.
    public static func uniformOptimum(
        axis: CourseAxis,
        tackingAngle θ: Double,
        cost: TackingCost,
        minStrips: Int = 2,
        maxStrips: Int = 64
    ) -> (stripCount: Int, cost: Double) {
        var bestN = max(2, minStrips)
        var bestJ = Double.infinity
        var N = max(2, minStrips)
        if N % 2 != 0 { N += 1 }
        while N <= maxStrips {
            let path = TackPath.uniformAlternating(
                axis: axis, stripCount: N, tackingAngle: θ
            )
            let J = cost.evaluate(path)
            if J < bestJ { bestJ = J; bestN = N }
            N += 2
        }
        return (bestN, bestJ)
    }

    /// Same sweep but on the generalised path, given a fixed progress
    /// field.  When the field is `LinearProgressField` this reproduces
    /// `uniformOptimum` up to integration error.
    public static func uniformGeneralizedOptimum(
        field: AnyProgressField,
        tackingAngle θ: Double,
        cost: TackingCost,
        minBands: Int = 2,
        maxBands: Int = 32
    ) -> (bandCount: Int, cost: Double) {
        var bestN = max(2, minBands)
        var bestJ = Double.infinity
        var N = max(2, minBands)
        if N % 2 != 0 { N += 1 }
        while N <= maxBands {
            let path = GeneralizedTackPath.uniformAlternating(
                field: field, bandCount: N, tackingAngle: θ
            )
            let J = cost.evaluate(path, field: field)
            if J < bestJ { bestJ = J; bestN = N }
            N += 2
        }
        return (bestN, bestJ)
    }
}
