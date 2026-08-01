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
    ///
    /// Prefer ``integrate(stepLength:maxSteps:)`` when the caller needs to know
    /// whether the trajectory actually arrived — this accessor cannot say.
    public func integrateInCourseFrame(
        stepLength dℓ: Double? = nil,
        maxSteps: Int = 32768
    ) -> [Point2D] {
        integrate(stepLength: dℓ, maxSteps: maxSteps).points
    }

    /// Why an integration stopped.
    ///
    /// Without this the caller cannot distinguish a completed trajectory from
    /// an abandoned one: both come back as a list of points. A sufficiently
    /// warped field stalls at roughly half the course and the UI drew it as
    /// though it were real (issue #14).
    public enum Termination: Hashable, Sendable {
        /// Reached `s ≥ 1` — the trajectory got to B.
        case arrived
        /// `|∇s|` collapsed, so no heading could be formed. Stopping is the
        /// correct behavior; continuing would emit NaN.
        case stalled
        /// Ran out of steps before arriving. The points are a prefix of a
        /// trajectory, not a trajectory.
        case exceededStepBudget
    }

    /// A trajectory together with the reason integration stopped.
    public struct IntegrationResult: Sendable {
        public let points: [Point2D]
        public let termination: Termination

        public var arrived: Bool { termination == .arrived }

        public init(points: [Point2D], termination: Termination) {
            self.points = points
            self.termination = termination
        }
    }

    /// Default step length as a fraction of the course length.
    ///
    /// Measured arrival error on a linear field, 8 bands, θ = 45° (issue #14):
    ///
    /// | step | distance from B | ratio to previous |
    /// |---|---|---|
    /// | `L/128` | 0.542 | — |
    /// | `L/256` | 0.383 | 0.71 |
    /// | `L/512` | **0.433** | **1.13 — increases** |
    /// | `L/1024` | 0.090 | 0.21 |
    /// | `L/2048` | 0.042 | 0.46 |
    /// | `L/4096` | 0.018 | 0.44 |
    ///
    /// The error is *non-monotone* in the coarse regime: each band boundary is
    /// crossed late by a fraction of a step, and that fraction beats against
    /// the step size rather than shrinking with it. Only once many steps fall
    /// within each band does the O(h) term dominate and halving the step halve
    /// the error.
    ///
    /// The previous default of `L/512` sat squarely in the non-convergent
    /// regime, so refining it could make the answer *worse*. `L/2048` is in the
    /// asymptotic regime with ~0.04% arrival error, at a few thousand steps —
    /// still well under a millisecond.
    public static let defaultStepDivisor = 2048

    /// Integrate the heading field from A, reporting why it stopped.
    public func integrate(
        stepLength dℓ: Double? = nil,
        maxSteps: Int = 32768
    ) -> IntegrationResult {
        let L = field.axis.length
        let dℓEff = dℓ ?? (L / Double(Self.defaultStepDivisor))
        let cosθ = cos(tackingAngle)
        let sinθ = sin(tackingAngle)

        var pts: [Point2D] = [Point2D(x: 0, y: 0)]
        pts.reserveCapacity(min(maxSteps, 4096))

        var p = Point2D(x: 0, y: 0)
        var bandIdx = bandIndex(forProgress: 0)
        var termination = Termination.exceededStepBudget

        for _ in 0..<maxSteps {
            let σ = tacks[bandIdx].sign
            let grad = field.gradient(sCoord: p.x, nCoord: p.y)
            let mag = grad.magnitude
            guard mag > 1e-12 else {
                termination = .stalled
                break
            }
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
            if s >= 1.0 {
                termination = .arrived
                break
            }
            // Update band membership.
            bandIdx = bandIndex(forProgress: s, hint: bandIdx)
        }
        return IntegrationResult(points: pts, termination: termination)
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

    /// Everything derivable from one integration, computed from one integration.
    ///
    /// `sailedLength()`, `crossTrackPeak()` and `headingChangesAtTurns()` each
    /// integrate independently, so asking for all three — which is exactly what
    /// a cost breakdown does — integrated the trajectory three times. Callers
    /// that need more than one metric should ask for this instead (issue #18).
    public struct TrajectoryMetrics: Sendable {
        public let points: [Point2D]
        public let termination: Termination
        public let sailedLength: Double
        public let crossTrackPeak: Double
        public let headingChanges: [Double]

        public var arrived: Bool { termination == .arrived }
    }

    /// Integrate once and derive every metric from that single trajectory.
    public func metrics(
        stepLength dℓ: Double? = nil,
        maxSteps: Int = 32768
    ) -> TrajectoryMetrics {
        let result = integrate(stepLength: dℓ, maxSteps: maxSteps)
        let pts = result.points

        var length = 0.0
        var peak = 0.0
        for (i, p) in pts.enumerated() {
            peak = max(peak, abs(p.y))
            if i > 0 { length += (p - pts[i - 1]).magnitude }
        }

        return TrajectoryMetrics(
            points: pts,
            termination: result.termination,
            sailedLength: length,
            crossTrackPeak: peak,
            headingChanges: Self.headingChanges(in: pts, of: self)
        )
    }

    /// Sailed arclength.  Equals dℓ · (N_steps − 1) when the integrator
    /// terminates at the right step length; we recompute it from the
    /// returned polyline for robustness.
    public func sailedLength() -> Double {
        metrics().sailedLength
    }

    /// Maximum cross-track excursion |n|ₘₐₓ along the trajectory.
    public func crossTrackPeak() -> Double {
        metrics().crossTrackPeak
    }

    /// Sequence of heading-change magnitudes at each tack reversal.
    /// In the rhumb-line case |Δθ| ≡ 2θ at every reversal; in a warped
    /// field it varies because û(p) rotates between reversals.
    ///
    /// Indexing note (issue #11). Segment `i` runs `pts[i] → pts[i+1]` and was
    /// generated using the band at **`pts[i]`** — the point the step departed
    /// from. A reversal between segments `i−1` and `i` therefore shows up as a
    /// band change between `pts[i−1]` and `pts[i]`, and the turn is the angle
    /// between those two segments.
    ///
    /// The previous implementation detected the change at `pts[i]` but compared
    /// `pts[i−1] − pts[i−2]` against `pts[i] − pts[i−1]` — both of which are
    /// still *pre-turn*, because the tack that produced the step into `pts[i]`
    /// came from the band at `pts[i−1]`. It therefore returned `0.0` at every
    /// reversal, with the correct count, silently zeroing the
    /// `headingChangeWeight` cost term.
    public func headingChangesAtTurns() -> [Double] {
        metrics().headingChanges
    }

    /// Turn detection over an already-integrated trajectory.
    ///
    /// Segment `i` runs `pts[i] → pts[i+1]` and was generated using the band at
    /// **`pts[i]`** — the point the step departed from. A reversal between
    /// segments `i−1` and `i` therefore appears as a band change between
    /// `pts[i−1]` and `pts[i]`, and the turn is the angle between those two
    /// segments (issue #11).
    static func headingChanges(in pts: [Point2D], of path: GeneralizedTackPath) -> [Double] {
        guard pts.count >= 3 else { return [] }

        var result: [Double] = []
        var band = path.bandIndex(
            forProgress: path.field.value(sCoord: pts[0].x, nCoord: pts[0].y))

        // Stop at count−1: the final point has no outgoing segment, so a
        // crossing detected there has no post-turn heading to compare against.
        for i in 1..<(pts.count - 1) {
            let next = path.bandIndex(
                forProgress: path.field.value(sCoord: pts[i].x, nCoord: pts[i].y),
                hint: band)
            guard next != band else { continue }

            let before = pts[i] - pts[i - 1]  // generated in the old band
            let after = pts[i + 1] - pts[i]  // generated in the new band
            let cosΔ = max(
                -1,
                min(1, Vector2D.dot(before.normalized(), after.normalized())))
            result.append(acos(cosΔ))
            band = next
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
