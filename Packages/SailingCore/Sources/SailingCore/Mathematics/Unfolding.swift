//
//  Unfolding.swift
//  Sailing
//
//  The core formal step.  Given a tacking zig-zag in the course frame,
//  reflect every other strip across one of its boundary lines.  After all
//  reflections are composed, the polyline becomes a straight line in the
//  "covering" plane.
//
//  Concretely, for strips i = 0, 1, …, N−1 with widths w_i and tacks σ_i,
//  define a chain of isometries Φ_0, Φ_1, …, Φ_N of the (s, n)-plane such
//  that Φ_i applied to the i-th leg lifts every leg into the same half-plane,
//  with all heading vectors pointing in the same direction.  The result —
//  the "unfolded" polyline — is a single straight segment from
//      (0, 0)   to   (L, L · tan θ)
//  whose length L / cos θ exactly equals the sailed distance.
//
//  This is the same trick used to:
//    * straighten billiard trajectories in polygons,
//    * compute geodesics on translation surfaces,
//    * unfold polyhedra in computational geometry.
//
//  Reference:
//    H. Masur & S. Tabachnikov, "Rational billiards and flat structures."
//    A. Zorich, "Flat surfaces."
//

import Foundation

// MARK: - Reflections in (s, n)

/// Reflection across the vertical line s = a, fixing n.
public struct ReflectionAcrossVerticalLine: Hashable, Codable {
    public var a: Double
    public init(a: Double) { self.a = a }

    public func apply(_ p: Point2D) -> Point2D {
        Point2D(x: 2 * a - p.x, y: p.y)
    }
}

/// Reflection across the horizontal line n = b, fixing s.
public struct ReflectionAcrossHorizontalLine: Hashable, Codable {
    public var b: Double
    public init(b: Double) { self.b = b }

    public func apply(_ p: Point2D) -> Point2D {
        Point2D(x: p.x, y: 2 * b - p.y)
    }
}

// MARK: - Unfolding

public enum Unfolding {

    /// The classic "billiard unfolding" of a tacking path.  We reflect every
    /// down-going (σ = −1) leg across the horizontal line n = n_i, where n_i
    /// is the cross-track value at the *start* of that leg.  After reflection,
    /// every leg points "up and to the right" with slope +tan θ, and the
    /// polyline becomes a straight line of slope tan θ in the covering frame.
    ///
    /// Returns the unfolded vertex sequence in covering coordinates (s̃, ñ).
    /// For a uniform alternating path, the result is colinear:
    ///     ṽ_k = (k · w, k · w · tan θ).
    public static func unfoldByHorizontalReflections(
        of path: TackPath
    ) -> [Point2D] {
        let θ = path.tackingAngle
        let tanθ = tan(θ)
        var vs: [Point2D] = [Point2D(x: 0, y: 0)]
        var s̃: Double = 0
        var ñ: Double = 0
        // Every leg, regardless of σ_i, is rendered as going "up" by w·tan θ.
        // Horizontal reflections collectively flip every other leg about its
        // start so that all legs share the same heading.
        for strip in path.strips {
            let w = strip.width
            s̃ += w
            ñ += w * tanθ
            vs.append(Point2D(x: s̃, y: ñ))
        }
        return vs
    }

    /// The "translation-surface" unfolding.  Same idea, but we glue strips
    /// edge-to-edge along the *direction of travel* in the covering, so the
    /// covering coordinate is (path arc-length, signed cross-track in the
    /// covering frame).
    ///
    /// Returns the cumulative isometries Φ_0 … Φ_N applied to each leg.
    /// Φ_i maps strip i's leg from the original (s, n) frame into the
    /// covering frame.  The composition is built from horizontal reflections
    /// Hₙ across n = n_i for each tack reversal.
    public static func cumulativeIsometries(
        of path: TackPath
    ) -> [PlanarIsometry] {
        // Tracked as a running value rather than re-reading `Φ.last!`: the
        // array is never empty, but expressing that with a force unwrap makes
        // the invariant implicit and trips force_unwrapping.
        var current: PlanarIsometry = .identity
        var Φ: [PlanarIsometry] = [current]
        let tanθ = tan(path.tackingAngle)
        var n: Double = 0
        var σ_prev: Double = path.strips.first?.tack.sign ?? 1
        for strip in path.strips {
            let σ = strip.tack.sign
            // When the tack flips, compose with a horizontal reflection
            // across the current n.
            if σ != σ_prev {
                let H = PlanarIsometry.reflectionAcrossHorizontal(b: n)
                current = H.compose(current)
            }
            Φ.append(current)
            n += σ * strip.width * tanθ
            σ_prev = σ
        }
        return Φ
    }

    /// Sanity check: unfolded polyline is straight to within `tol`.
    public static func unfoldedIsStraight(
        _ unfolded: [Point2D],
        tol: Double = 1e-9
    ) -> Bool {
        guard unfolded.count >= 3, let p0 = unfolded.first, let pN = unfolded.last else {
            return true
        }
        let v = pN - p0
        let L = v.magnitude
        guard L > tol else { return unfolded.allSatisfy { ($0 - p0).magnitude < tol } }
        let û = v.normalized()
        for p in unfolded {
            let r = p - p0
            // Component perpendicular to û.
            let perp = abs(Vector2D.cross(r, û))
            if perp > tol { return false }
        }
        return true
    }
}

// MARK: - PlanarIsometry
//
// A 2x2 orthogonal matrix M plus a translation t.  Acts as p ↦ M·p + t.
// We only ever need reflections and translations, so M is always orthogonal
// with det = ±1.
//

public struct PlanarIsometry: Hashable, Codable, Sendable {
    public var m00, m01, m10, m11: Double
    public var tx, ty: Double

    public init(
        m00: Double, m01: Double, m10: Double, m11: Double,
        tx: Double, ty: Double
    ) {
        self.m00 = m00; self.m01 = m01
        self.m10 = m10; self.m11 = m11
        self.tx = tx; self.ty = ty
    }

    public static let identity = PlanarIsometry(
        m00: 1, m01: 0, m10: 0, m11: 1, tx: 0, ty: 0
    )

    /// Reflection across the horizontal line n = b in the (s, n) plane.
    public static func reflectionAcrossHorizontal(b: Double) -> PlanarIsometry {
        // (s, n) ↦ (s, 2b − n)
        PlanarIsometry(m00: 1, m01: 0, m10: 0, m11: -1, tx: 0, ty: 2 * b)
    }

    /// Reflection across the vertical line s = a in the (s, n) plane.
    public static func reflectionAcrossVertical(a: Double) -> PlanarIsometry {
        // (s, n) ↦ (2a − s, n)
        PlanarIsometry(m00: -1, m01: 0, m10: 0, m11: 1, tx: 2 * a, ty: 0)
    }

    public func apply(_ p: Point2D) -> Point2D {
        Point2D(
            x: m00 * p.x + m01 * p.y + tx,
            y: m10 * p.x + m11 * p.y + ty
        )
    }

    /// Composition: (self ∘ other)(p) = self(other(p)).
    public func compose(_ other: PlanarIsometry) -> PlanarIsometry {
        let n00 = m00 * other.m00 + m01 * other.m10
        let n01 = m00 * other.m01 + m01 * other.m11
        let n10 = m10 * other.m00 + m11 * other.m10
        let n11 = m10 * other.m01 + m11 * other.m11
        let ntx = m00 * other.tx + m01 * other.ty + tx
        let nty = m10 * other.tx + m11 * other.ty + ty
        return PlanarIsometry(
            m00: n00, m01: n01, m10: n10, m11: n11,
            tx: ntx, ty: nty
        )
    }
}
