//
//  Wind.swift
//  Sailing
//
//  A minimal wind model.  All a sailboat really needs to do tacking math
//  is: which direction is the wind coming FROM, and how close to the wind
//  can the boat point (the "no-go" half-angle).
//

import Foundation

public struct WindModel: Hashable, Codable, Sendable {
    /// Direction the wind is coming **from**, as a unit vector in the world frame.
    /// Convention: this is the direction you'd point your nose into to sail
    /// "head-to-wind".
    public var fromDirection: Vector2D

    /// Half-width of the close-hauled "no-go" zone, in radians.  Realistic
    /// values are roughly 35°–50° (≈ 0.61–0.87 rad).  This is the smallest
    /// angle the boat can sail off the true wind.
    public var noGoHalfAngle: Double

    public init(fromDirection: Vector2D, noGoHalfAngle: Double) {
        self.fromDirection = fromDirection.normalized()
        self.noGoHalfAngle = noGoHalfAngle
    }

    /// Default wind: blowing from "north" (i.e. you're trying to sail north),
    /// 45° no-go zone.
    public static let standard = WindModel(
        fromDirection: Vector2D(dx: 0, dy: 1),
        noGoHalfAngle: .pi / 4
    )

    /// The two close-hauled headings — the unit vectors pointing as close
    /// to the wind as the boat can manage, one on each tack.
    /// `.starboard` keeps the wind on the right side of the boat; `.port`
    /// keeps it on the left.  Both make a `noGoHalfAngle` with `fromDirection`.
    public func closeHauledHeading(_ tack: Tack) -> Vector2D {
        // Heading toward the wind would be `fromDirection`; rotate it away
        // from the wind by ±noGoHalfAngle to get the closest-hauled course.
        let sign: Double = (tack == .starboard) ? -1 : +1
        return fromDirection.rotated(by: sign * (.pi - noGoHalfAngle))
            .normalized()
    }

    /// Smallest tacking half-angle off the AB axis that the boat can
    /// realise.  Let α = angle(u, fromDirection) be the angle between the
    /// course direction and "where the wind is coming from".
    ///
    ///     α ≥ noGoHalfAngle  ⇒ no tack needed (return 0)
    ///     α <  noGoHalfAngle ⇒ must tack at θ = noGoHalfAngle − α
    ///
    /// Domain: θ ∈ [0, noGoHalfAngle].
    public func tackingAngle(towards course: CourseAxis) -> Double {
        let cosα = Vector2D.dot(fromDirection, course.u)
        let α = acos(max(-1, min(1, cosα)))
        return max(0, noGoHalfAngle - α)
    }
}

// MARK: - Tack

/// Discrete control state.  ±1 in the math, "starboard" / "port" in the world.
public enum Tack: Int, Hashable, Codable, CaseIterable {
    case starboard = 1    // wind on the starboard (right) side
    case port      = -1   // wind on the port (left) side

    public var sign: Double { Double(rawValue) }

    public var opposite: Tack { self == .starboard ? .port : .starboard }

    public var label: String { self == .starboard ? "starboard" : "port" }
}
