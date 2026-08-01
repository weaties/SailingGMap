//
//  Approx.swift
//  SailingCoreTests
//
//  Floating-point comparison helpers.
//
//  AGENTS.md § "Floating-point tolerance policy" forbids bare `==` on `Double`
//  and unexplained epsilons. These helpers make the *kind* of tolerance
//  explicit at the call site, so a reviewer can see whether a relative or an
//  absolute bound was intended without reverse-engineering the magnitudes.
//

import Foundation

@testable import SailingCore

/// Relative comparison: `|a − b| ≤ tol · max(|a|, |b|)`.
///
/// Use for quantities whose scale is set by the inputs (lengths, costs). Not
/// meaningful when either operand may be zero — use ``isApprox(_:_:absolute:)``
/// there, because the relative error of a near-zero quantity is unbounded.
public func isApprox(_ a: Double, _ b: Double, relative tol: Double) -> Bool {
    if a == b { return true }
    guard a.isFinite, b.isFinite else { return false }
    let scale = max(abs(a), abs(b))
    return abs(a - b) <= tol * scale
}

/// Absolute comparison: `|a − b| ≤ tol`.
///
/// Use for quantities expected to be near zero (cross-track offsets, angle
/// differences) and for angles generally, where a relative bound degenerates.
public func isApprox(_ a: Double, _ b: Double, absolute tol: Double) -> Bool {
    if a == b { return true }
    guard a.isFinite, b.isFinite else { return false }
    return abs(a - b) <= tol
}

/// Point comparison in whichever frame the caller is working in. The frame is
/// the caller's responsibility — this only compares components.
public func isApprox(_ a: Point2D, _ b: Point2D, absolute tol: Double) -> Bool {
    isApprox(a.x, b.x, absolute: tol) && isApprox(a.y, b.y, absolute: tol)
}

/// Largest absolute deviation of `values` from `expected`. Useful in failure
/// messages so a red test reports *how far off* it was, not merely that it was.
public func maxDeviation(_ values: [Double], from expected: Double) -> Double {
    values.reduce(0) { max($0, abs($1 - expected)) }
}

// MARK: - Fixtures

extension CourseAxis {
    /// A canonical course of the given length along +x, origin at A.
    ///
    /// Most invariants are frame-independent, so tests use this unless they are
    /// specifically exercising the world/course conversion.
    public static func canonical(length: Double = 100) -> CourseAxis {
        CourseAxis(origin: .zero, destination: Point2D(x: length, y: 0))
    }
}

extension TackPath {
    /// A path whose tacks do **not** alternate — every strip on the same tack.
    ///
    /// This is the standard negative control for the unfolding invariant (I3):
    /// it accumulates cross-track offset monotonically and lands a full course
    /// length off the rhumb line, so it must not unfold to a straight segment.
    public static func constantTack(
        axis: CourseAxis,
        stripCount n: Int,
        tackingAngle θ: Double,
        tack: Tack = .starboard
    ) -> TackPath {
        let w = axis.length / Double(n)
        let strips = (0..<n).map {
            Strip(id: $0, sStart: Double($0) * w, sEnd: Double($0 + 1) * w, tack: tack)
        }
        return TackPath(axis: axis, strips: strips, tackingAngle: θ)
    }
}
