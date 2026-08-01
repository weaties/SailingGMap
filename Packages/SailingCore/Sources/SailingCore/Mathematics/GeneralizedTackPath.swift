//
//  GeneralizedTackPath.swift
//  Sailing
//
//  The continuous variational generalisation of `TackPath`.
//
//  Strips are no longer rigid rectangles perpendicular to AB; they are
//  bands of the progress field s : Ω → [0, 1] bounded by level curves
//  { s = c_i } and { s = c_{i+1} }.  Inside band i the boat sails on
//  tack σᵢ ∈ {−1, +1} at a fixed offset angle θ from the local
//  progress direction û(p) = ∇s(p) / |∇s(p)|.  The heading field is
//
//      h(p)  =  cos θ · û(p)  +  σᵢ · sin θ · n̂(p),
//      n̂(p)  =  û(p) rotated 90° CCW.
//
//  The trajectory γ(t) is the integral curve of h starting at A, with
//  σᵢ switching to σᵢ₊₁ when γ crosses the next level curve { s = c_{i+1} }.
//
//  Special case.  For `LinearProgressField`, û is constant and equal to
//  the AB unit vector, n̂ is the AB-perpendicular, the level curves are
//  AB-perpendicular lines, and `GeneralizedTackPath` reduces to the
//  rectilinear `TackPath` of the prototype (modulo numerical integration
//  vs. closed-form vertices).
//

import Foundation

public struct GeneralizedTackPath {

    public var field: AnyProgressField
    /// Tack sequence σ₀, σ₁, …, σ_{N−1}.
    public var tacks: [Tack]
    /// Band boundaries c₀ < c₁ < … < c_N, with c₀ = 0 and c_N = 1.  The
    /// i-th band is { c_i ≤ s ≤ c_{i+1} } and carries tack σᵢ.
    public var bandBoundaries: [Double]
    /// Tacking half-angle θ off the local progress direction û.
    public var tackingAngle: Double

    public init(
        field: AnyProgressField,
        tacks: [Tack],
        bandBoundaries: [Double],
        tackingAngle: Double
    ) {
        precondition(tacks.count >= 1)
        precondition(bandBoundaries.count == tacks.count + 1)
        precondition(
            bandBoundaries.first.map { abs($0) < 1e-9 } ?? false,
            "First boundary must be 0")
        precondition(
            bandBoundaries.last.map { abs($0 - 1) < 1e-9 } ?? false,
            "Last boundary must be 1")
        self.field = field
        self.tacks = tacks
        self.bandBoundaries = bandBoundaries
        self.tackingAngle = tackingAngle
    }

    // MARK: - Construction helpers

    /// Uniform alternating bands over an arbitrary progress field.
    /// `N` is the band count; tacks alternate starting from `startingTack`.
    public static func uniformAlternating(
        field: AnyProgressField,
        bandCount N: Int,
        tackingAngle θ: Double,
        startingTack: Tack = .starboard
    ) -> GeneralizedTackPath {
        precondition(N >= 1)
        let boundaries = (0...N).map { Double($0) / Double(N) }
        var tacks: [Tack] = []
        tacks.reserveCapacity(N)
        var t = startingTack
        for _ in 0..<N { tacks.append(t); t = t.opposite }
        return GeneralizedTackPath(
            field: field,
            tacks: tacks,
            bandBoundaries: boundaries,
            tackingAngle: θ
        )
    }

    // MARK: - Integration

    /// Integrate the heading field h starting at A.  The arclength
    /// parameterisation uses a fixed Δℓ step.  At every step we look up
    /// the local s-value, find which band we're in, and step along
    /// h(p) for that band.  Integration stops when s ≥ 1 or after
    /// `maxSteps` to guard against pathological fields.
    ///
    /// Returns the trajectory in **course-frame** coordinates (s, n).
    public func integrateInCourseFrame(
        stepLength dℓ: Double? = nil,
        maxSteps: Int = 8192
    ) -> [Point2D] {
        let L = field.axis.length
        let dℓEff = dℓ ?? (L / 512)
        let cosθ = cos(tackingAngle)
        let sinθ = sin(tackingAngle)

        var pts: [Point2D] = [Point2D(x: 0, y: 0)]
        pts.reserveCapacity(min(maxSteps, 4096))

        var p = Point2D(x: 0, y: 0)
        var bandIdx = bandIndex(forProgress: 0)

        for _ in 0..<maxSteps {
            let σ = tacks[bandIdx].sign
            let grad = field.gradient(sCoord: p.x, nCoord: p.y)
            let mag = grad.magnitude
            guard mag > 1e-12 else { break }
            let û = (1 / mag) * grad
            let n̂ = û.perpendicularLeft()
            let h = cosθ * û + (σ * sinθ) * n̂
            // |h| ≡ 1, so the arclength step is just dℓEff · h.
            let next = Point2D(
                x: p.x + dℓEff * h.dx,
                y: p.y + dℓEff * h.dy)
            pts.append(next)
            p = next

            let s = field.value(sCoord: p.x, nCoord: p.y)
            if s >= 1.0 { break }
            // Update band membership.
            bandIdx = bandIndex(forProgress: s, hint: bandIdx)
        }
        return pts
    }

    /// Same trajectory, lifted to the world frame.
    public func integrateInWorldFrame(
        stepLength dℓ: Double? = nil,
        maxSteps: Int = 8192
    ) -> [Point2D] {
        let coursePts = integrateInCourseFrame(
            stepLength: dℓ,
            maxSteps: maxSteps)
        return coursePts.map {
            field.axis.fromCourse(s: $0.x, n: $0.y)
        }
    }

    // MARK: - Metrics

    /// Sailed arclength.  Equals dℓ · (N_steps − 1) when the integrator
    /// terminates at the right step length; we recompute it from the
    /// returned polyline for robustness.
    public func sailedLength() -> Double {
        let pts = integrateInCourseFrame()
        guard pts.count >= 2 else { return 0 }
        var L: Double = 0
        for i in 1..<pts.count {
            L += (pts[i] - pts[i - 1]).magnitude
        }
        return L
    }

    /// Maximum cross-track excursion |n|ₘₐₓ along the trajectory.
    public func crossTrackPeak() -> Double {
        integrateInCourseFrame().map { abs($0.y) }.max() ?? 0
    }

    /// Sequence of heading-change magnitudes at each tack reversal.
    /// In the rhumb-line case |Δθ| ≡ 2θ at every reversal; in a warped
    /// field it varies because û(p) rotates between reversals.
    public func headingChangesAtTurns() -> [Double] {
        var result: [Double] = []
        let pts = integrateInCourseFrame()
        guard pts.count >= 3 else { return [] }
        var prevHeading: Vector2D?
        var prevBand = bandIndex(forProgress: 0)
        for i in 1..<pts.count {
            let s = field.value(sCoord: pts[i].x, nCoord: pts[i].y)
            let band = bandIndex(forProgress: s, hint: prevBand)
            let v = pts[i] - pts[i - 1]
            if band != prevBand {
                if let ph = prevHeading {
                    let cosΔ = max(
                        -1,
                        min(
                            1,
                            Vector2D.dot(
                                ph.normalized(),
                                v.normalized())))
                    result.append(acos(cosΔ))
                }
                prevBand = band
            }
            prevHeading = v
        }
        return result
    }

    // MARK: - Band lookup

    /// Linear scan with a hint — cheap because band count is small and
    /// crossings are sequential along the trajectory.
    public func bandIndex(forProgress s: Double, hint: Int = 0) -> Int {
        let last = tacks.count - 1
        if s <= bandBoundaries[0] { return 0 }
        if s >= bandBoundaries[last + 1] { return last }
        // Walk forward from `hint`.
        var i = max(0, min(hint, last))
        while i < last && s > bandBoundaries[i + 1] { i += 1 }
        while i > 0 && s < bandBoundaries[i] { i -= 1 }
        return i
    }
}
