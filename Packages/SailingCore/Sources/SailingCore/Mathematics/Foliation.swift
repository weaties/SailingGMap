//
//  Foliation.swift
//  Sailing
//
//  A *foliation* of Ω by a `ProgressField` s is the family of level
//  curves
//
//      { p ∈ Ω : s(p) = c },     c ∈ [0, 1].
//
//  Monotonicity ∂s/∂s_coord > 0 guarantees every horizontal line in the
//  course frame meets each level set exactly once, so the level set is
//  the graph
//
//      n ↦ ŝ(c, n)
//
//  for some function ŝ.  We recover it by 1D bisection at each n.
//
//  Foliations replace the rigid "strip boundaries" of the rhumb-line
//  prototype.  Bands between consecutive level sets play the role of
//  the original strips and the reflection-unfolding picture lifts
//  unchanged: across each level set the gluing is either direct (same
//  tack on both sides) or reflective (a tack reversal).
//

import Foundation

public enum Foliation {

    // MARK: - Level curve extraction

    /// Sample the level set { s = c } in the course frame at `samples`
    /// evenly-spaced cross-track positions.  Returns a polyline running
    /// from (sₛₜₐᵣₜ, −W) to (sₑₙ𝒹, +W).
    public static func levelCurve(
        of field: ProgressField,
        at c: Double,
        samples: Int = 64
    ) -> [Point2D] {
        precondition(samples >= 2, "Need at least 2 samples")
        let W = field.halfWidth
        var pts: [Point2D] = []
        pts.reserveCapacity(samples)
        for k in 0..<samples {
            let t = Double(k) / Double(samples - 1)
            let n = -W + 2 * W * t
            let s = solveForS(of: field, n: n, target: c)
            pts.append(Point2D(x: s, y: n))
        }
        return pts
    }

    /// 1-D bisection: given n, find s such that field.value(s, n) = c.
    /// Brackets are chosen so that any progress value in (0, 1) is hit.
    public static func solveForS(
        of field: ProgressField,
        n: Double,
        target c: Double,
        tol: Double = 1e-7,
        maxIter: Int = 64
    ) -> Double {
        let L = field.axis.length
        var lo: Double = -0.5 * L
        var hi: Double = 1.5 * L
        var fLo = field.value(sCoord: lo, nCoord: n) - c
        var fHi = field.value(sCoord: hi, nCoord: n) - c

        // Expand the bracket up to a few times if the sign hasn't flipped.
        var attempts = 0
        while fLo * fHi > 0 && attempts < 6 {
            lo -= 0.5 * L
            hi += 0.5 * L
            fLo = field.value(sCoord: lo, nCoord: n) - c
            fHi = field.value(sCoord: hi, nCoord: n) - c
            attempts += 1
        }
        if fLo * fHi > 0 {
            // Fallback: pretend the field is linear.
            return c * L
        }
        for _ in 0..<maxIter {
            let mid = (lo + hi) / 2
            let fMid = field.value(sCoord: mid, nCoord: n) - c
            if abs(fMid) < tol { return mid }
            if fMid * fLo < 0 {
                hi = mid; fHi = fMid
            } else {
                lo = mid; fLo = fMid
            }
        }
        return (lo + hi) / 2
    }

    /// Generate `count` evenly-spaced level curves at c = k/(count+1),
    /// k = 1..count.  Useful for drawing the foliation as a background.
    public static func levelCurves(
        of field: ProgressField,
        count: Int,
        samples: Int = 48
    ) -> [[Point2D]] {
        guard count >= 1 else { return [] }
        return (1...count).map { k in
            let c = Double(k) / Double(count + 1)
            return levelCurve(of: field, at: c, samples: samples)
        }
    }

    // MARK: - Monotonicity diagnostic

    /// Sample the field's monotonicity ∂s/∂s_coord on a grid; return the
    /// fraction of samples that violate ∂s/∂s_coord > 0.
    public static func monotonicityViolations(
        of field: ProgressField,
        samplesS: Int = 32,
        samplesN: Int = 16
    ) -> Double {
        let L = field.axis.length
        let W = field.halfWidth
        var bad = 0
        var total = 0
        for i in 0..<samplesS {
            let sc = (Double(i) + 0.5) * L / Double(samplesS)
            for j in 0..<samplesN {
                let nc = -W + (Double(j) + 0.5) * 2 * W / Double(samplesN)
                if !field.isMonotonic(sCoord: sc, nCoord: nc) { bad += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(bad) / Double(total)
    }
}
