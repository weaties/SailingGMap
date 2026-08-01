//
//  TackPath.swift
//  Sailing
//
//  A `TackPath` glues strips into an actual zig-zag, given a tacking angle θ
//  (the angle between each leg and the AB axis).  It produces the polyline
//  in the world frame, the polyline in the course frame, and total length.
//
//  Sign convention (course frame):
//      heading direction in strip i  =  (cos θ , σ_i · sin θ)
//  where σ_i = strip.tack.sign ∈ {+1, -1}.
//
//  For the path to actually arrive at B, the total signed cross-track
//  displacement must vanish:
//      Σ_i  σ_i · w_i · tan θ  =  0
//  An even number of equal-width alternating strips trivially satisfies this.
//

import Foundation

public struct TackPath: Hashable, Codable {
    public var axis: CourseAxis
    public var strips: [Strip]
    public var tackingAngle: Double  // θ, radians, off the AB axis

    public init(axis: CourseAxis, strips: [Strip], tackingAngle: Double) {
        self.axis = axis
        self.strips = strips
        self.tackingAngle = tackingAngle
    }

    // MARK: - Vertices

    /// Vertices of the zig-zag polyline in the course frame (s, n).
    /// First vertex is A = (0, 0); last vertex is the boat's actual arrival
    /// point.  If the path is balanced, the last vertex is (L, 0).
    public func courseVertices() -> [Point2D] {
        let tanθ = tan(tackingAngle)
        var vs: [Point2D] = [Point2D(x: 0, y: 0)]
        var s: Double = 0
        var n: Double = 0
        for strip in strips {
            let w = strip.width
            s += w
            n += strip.tack.sign * w * tanθ
            vs.append(Point2D(x: s, y: n))
        }
        return vs
    }

    /// Same polyline, lifted into the world frame.
    public func worldVertices() -> [Point2D] {
        courseVertices().map { axis.fromCourse(s: $0.x, n: $0.y) }
    }

    // MARK: - Lengths

    /// Total sailed distance along the zig-zag.  Equals (Σ w_i) / cos θ
    /// for a uniform tacking angle — i.e. it's invariant under strip count
    /// when θ is fixed, which is exactly the geometric content of the
    /// reflection-unfolding picture: the unfolded straight line has length
    /// L / cos θ.
    public func sailedLength() -> Double {
        let cosθ = cos(tackingAngle)
        guard cosθ > 1e-9 else { return .infinity }
        return strips.reduce(0) { $0 + $1.width } / cosθ
    }

    /// Maximum |n| reached on the path — how far you swing off the rhumb-line.
    public func crossTrackPeak() -> Double {
        courseVertices().map { abs($0.y) }.max() ?? 0
    }

    /// Cross-track imbalance at arrival.  Should be 0 for a feasible path.
    public func arrivalOffset() -> Double {
        courseVertices().last?.y ?? 0
    }

    // MARK: - Convenience constructors

    /// Build a uniform alternating tack path:
    ///   N strips of equal width L/N, tacks alternating σ, -σ, σ, -σ, ...
    /// `startingTack` is σ_0.  N must be even for the path to close on B.
    public static func uniformAlternating(
        axis: CourseAxis,
        stripCount N: Int,
        tackingAngle θ: Double,
        startingTack: Tack = .starboard
    ) -> TackPath {
        precondition(N >= 1, "Need at least one strip")
        let L = axis.length
        let w = L / Double(N)
        var strips: [Strip] = []
        strips.reserveCapacity(N)
        var t = startingTack
        for i in 0..<N {
            strips.append(
                Strip(
                    id: i,
                    sStart: Double(i) * w,
                    sEnd: Double(i + 1) * w,
                    tack: t
                ))
            t = t.opposite
        }
        return TackPath(axis: axis, strips: strips, tackingAngle: θ)
    }
}
