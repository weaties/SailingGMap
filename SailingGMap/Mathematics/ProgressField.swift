//
//  ProgressField.swift
//  Sailing
//
//  A *progress field* is a smooth scalar
//
//      s : Ω ⊂ ℝ² → [0, 1]
//
//  satisfying
//
//      s(A) = 0,   s(B) = 1,
//      ∇s · (B − A) > 0      (monotonicity along AB)
//
//  Its level sets { s = c } are the generalised strip boundaries — they
//  replace the rigid perpendicular lines of the rhumb-line prototype.
//  Bands between consecutive level sets play the role of the original
//  strips; the boat sails on a single tack within each band, with
//  heading
//
//      h(p)  =  cos θ · û(p)  +  σ · sin θ · n̂(p)
//
//  where û = ∇s / |∇s| is the local "direction of progress" and n̂ = û
//  rotated 90° to the left.  In the rhumb-line case û is constant and
//  n̂ is the AB-perpendicular; in a warped field both rotate with p.
//
//  We work in the **course frame** (s_coord, n_coord) attached to AB.
//  All geometry stays 2D and dimensionless in field strength.
//

import Foundation

// MARK: - Protocol

public protocol ProgressField {
    /// Underlying rhumb-line frame (A, B, length, u, n).
    var axis: CourseAxis { get }

    /// Half-width of the visible cross-track domain Ω in the course frame.
    var halfWidth: Double { get }

    /// Value s ∈ [0, 1] at the course-frame point (sCoord, nCoord).
    func value(sCoord: Double, nCoord: Double) -> Double

    /// Gradient ∇s = (∂s/∂s_coord, ∂s/∂n_coord) in the course frame.
    func gradient(sCoord: Double, nCoord: Double) -> Vector2D

    /// Laplacian Δs = ∂²s/∂s_coord² + ∂²s/∂n_coord² at the same point.
    /// Used by the foliation-smoothness regulariser ν ∫ |∇²s|² dA.
    func laplacian(sCoord: Double, nCoord: Double) -> Double
}

public extension ProgressField {

    /// Convenience: value at a world-frame point.
    func value(at world: Point2D) -> Double {
        let c = axis.toCourse(world)
        return value(sCoord: c.x, nCoord: c.y)
    }

    /// Monotonicity check: is the component of ∇s along the course
    /// direction strictly positive at (sCoord, nCoord)?  The protocol
    /// guarantees this on the whole domain, but in numerical experiments
    /// you'll want to verify it on a grid before trusting an unfolding.
    func isMonotonic(sCoord: Double, nCoord: Double) -> Bool {
        gradient(sCoord: sCoord, nCoord: nCoord).dx > 0
    }

    /// The local "direction of progress" û = ∇s / |∇s|.
    func progressDirection(sCoord: Double, nCoord: Double) -> Vector2D {
        gradient(sCoord: sCoord, nCoord: nCoord).normalized()
    }

    /// Discrete sweep of the L¹ Laplacian over a uniform (Nₛ × Nₙ) grid
    /// covering [0, L] × [−W, W].  Returns ∫ |∇²s|² dA approximated by a
    /// midpoint rule.
    func laplacianL2Squared(samplesS: Int = 32, samplesN: Int = 24) -> Double {
        let L = axis.length
        let W = halfWidth
        let dS = L / Double(samplesS)
        let dN = (2 * W) / Double(samplesN)
        var sum: Double = 0
        for i in 0..<samplesS {
            let sc = (Double(i) + 0.5) * dS
            for j in 0..<samplesN {
                let nc = -W + (Double(j) + 0.5) * dN
                let v = laplacian(sCoord: sc, nCoord: nc)
                sum += v * v
            }
        }
        return sum * dS * dN
    }
}

// MARK: - LinearProgressField (the rhumb-line case)

/// The trivial progress field s(p) = (p − A) · u_AB / L.  Its level sets
/// are perpendicular lines and the original prototype is exactly the
/// `GeneralizedTackPath` over this field.
public struct LinearProgressField: ProgressField, Hashable, Codable {
    public var axis: CourseAxis
    public var halfWidth: Double

    public init(axis: CourseAxis, halfWidth: Double = 50) {
        self.axis = axis
        self.halfWidth = halfWidth
    }

    public func value(sCoord: Double, nCoord: Double) -> Double {
        sCoord / axis.length
    }

    public func gradient(sCoord: Double, nCoord: Double) -> Vector2D {
        Vector2D(dx: 1 / axis.length, dy: 0)
    }

    public func laplacian(sCoord: Double, nCoord: Double) -> Double { 0 }
}

// MARK: - WarpedProgressField

/// `LinearProgressField` plus a single radially-symmetric Gaussian bump
/// in the course frame:
///
///   s(p)  =  s_coord / L
///          + amp · exp( − ((s − s₀)² + (n − n₀)²) / (2 σ²) ).
///
/// The bump bends level curves around (s₀, n₀).  Monotonicity ∂s/∂s > 0
/// is preserved as long as
///
///   |amp| / σ²  <  1 / L
///
/// (the maximum |∂ψ/∂s| of the bump must stay below the linear gradient
/// 1/L).  `isMonotonic` will detect a violation point-wise.
public struct WarpedProgressField: ProgressField, Hashable, Codable {
    public var axis: CourseAxis
    public var halfWidth: Double

    /// Amplitude of the bump.  Positive = level curves bow forward
    /// (toward B) at the centre; negative = bow backward.
    public var amplitude: Double

    /// Standard deviation of the Gaussian.
    public var sigma: Double

    /// Bump centre in course-frame coords (sCenterFraction · L, nCenter).
    public var sCenterFraction: Double
    public var nCenter: Double

    public init(
        axis: CourseAxis,
        halfWidth: Double = 50,
        amplitude: Double = 0.18,
        sigma: Double = 18,
        sCenterFraction: Double = 0.5,
        nCenter: Double = 0
    ) {
        self.axis = axis
        self.halfWidth = halfWidth
        self.amplitude = amplitude
        self.sigma = sigma
        self.sCenterFraction = sCenterFraction
        self.nCenter = nCenter
    }

    private var s0: Double { sCenterFraction * axis.length }

    private func bumpKernel(sCoord: Double, nCoord: Double) -> Double {
        let ds = sCoord - s0
        let dn = nCoord - nCenter
        return exp(-(ds * ds + dn * dn) / (2 * sigma * sigma))
    }

    public func value(sCoord: Double, nCoord: Double) -> Double {
        sCoord / axis.length
            + amplitude * bumpKernel(sCoord: sCoord, nCoord: nCoord)
    }

    public func gradient(sCoord: Double, nCoord: Double) -> Vector2D {
        let k = bumpKernel(sCoord: sCoord, nCoord: nCoord)
        let σ2 = sigma * sigma
        let ds = sCoord - s0
        let dn = nCoord - nCenter
        let dψds = -amplitude * k * ds / σ2
        let dψdn = -amplitude * k * dn / σ2
        return Vector2D(dx: 1 / axis.length + dψds, dy: dψdn)
    }

    public func laplacian(sCoord: Double, nCoord: Double) -> Double {
        // ψ(s, n) = a · exp(−r²/(2σ²)),  r² = (s−s₀)² + (n−n₀)²
        // Δψ = a · exp(−r²/(2σ²)) · (r² − 2σ²) / σ⁴
        let k = bumpKernel(sCoord: sCoord, nCoord: nCoord)
        let σ2 = sigma * sigma
        let ds = sCoord - s0
        let dn = nCoord - nCenter
        let r2 = ds * ds + dn * dn
        return amplitude * k * (r2 - 2 * σ2) / (σ2 * σ2)
    }
}

// MARK: - Type-erased ProgressField

/// Useful for storing a `ProgressField` in a `@Published` property without
/// committing to one concrete type.  Forwards every call.
public struct AnyProgressField: ProgressField {
    public let axis: CourseAxis
    public let halfWidth: Double
    private let _value: (Double, Double) -> Double
    private let _grad:  (Double, Double) -> Vector2D
    private let _lap:   (Double, Double) -> Double

    public init<F: ProgressField>(_ field: F) {
        self.axis = field.axis
        self.halfWidth = field.halfWidth
        self._value = field.value(sCoord:nCoord:)
        self._grad  = field.gradient(sCoord:nCoord:)
        self._lap   = field.laplacian(sCoord:nCoord:)
    }

    public func value(sCoord: Double, nCoord: Double) -> Double {
        _value(sCoord, nCoord)
    }
    public func gradient(sCoord: Double, nCoord: Double) -> Vector2D {
        _grad(sCoord, nCoord)
    }
    public func laplacian(sCoord: Double, nCoord: Double) -> Double {
        _lap(sCoord, nCoord)
    }
}
