//
//  Geometry.swift
//  Sailing
//
//  Lightweight 2D vector / point primitives and a "course frame" attached
//  to the segment AB.  All sailing geometry is expressed either in the
//  world frame (x, y) or the course frame (s along AB, n perpendicular).
//

import Foundation
import CoreGraphics

// MARK: - Point2D

public struct Point2D: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    public static func - (a: Point2D, b: Point2D) -> Vector2D {
        Vector2D(dx: a.x - b.x, dy: a.y - b.y)
    }

    public static func + (p: Point2D, v: Vector2D) -> Point2D {
        Point2D(x: p.x + v.dx, y: p.y + v.dy)
    }

    public static func - (p: Point2D, v: Vector2D) -> Point2D {
        Point2D(x: p.x - v.dx, y: p.y - v.dy)
    }
}

// MARK: - Vector2D

public struct Vector2D: Hashable, Codable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = Vector2D(dx: 0, dy: 0)

    public var magnitude: Double { (dx * dx + dy * dy).squareRoot() }

    public var angle: Double { atan2(dy, dx) }

    public func normalized() -> Vector2D {
        let m = magnitude
        guard m > 0 else { return .zero }
        return Vector2D(dx: dx / m, dy: dy / m)
    }

    /// 90° counter-clockwise rotation.  In the course frame this turns the
    /// "along AB" axis into the "left of AB" axis.
    public func perpendicularLeft() -> Vector2D { Vector2D(dx: -dy, dy: dx) }

    /// 90° clockwise rotation.
    public func perpendicularRight() -> Vector2D { Vector2D(dx: dy, dy: -dx) }

    public func rotated(by radians: Double) -> Vector2D {
        let c = cos(radians), s = sin(radians)
        return Vector2D(dx: c * dx - s * dy, dy: s * dx + c * dy)
    }

    public static func dot(_ a: Vector2D, _ b: Vector2D) -> Double {
        a.dx * b.dx + a.dy * b.dy
    }

    /// 2D scalar cross product (z-component of the 3D cross).
    public static func cross(_ a: Vector2D, _ b: Vector2D) -> Double {
        a.dx * b.dy - a.dy * b.dx
    }

    public static func + (a: Vector2D, b: Vector2D) -> Vector2D {
        Vector2D(dx: a.dx + b.dx, dy: a.dy + b.dy)
    }

    public static func - (a: Vector2D, b: Vector2D) -> Vector2D {
        Vector2D(dx: a.dx - b.dx, dy: a.dy - b.dy)
    }

    public static func * (s: Double, v: Vector2D) -> Vector2D {
        Vector2D(dx: s * v.dx, dy: s * v.dy)
    }

    public static func * (v: Vector2D, s: Double) -> Vector2D { s * v }

    public static prefix func - (v: Vector2D) -> Vector2D {
        Vector2D(dx: -v.dx, dy: -v.dy)
    }
}

// MARK: - CourseAxis
//
// The "course frame" attached to A → B.
//   u = unit vector along AB        (the "s" axis: arc length along course)
//   n = u rotated 90° to the left   (the "n" axis: signed offset off course)
//
// Coordinates in the course frame are written (s, n).  The reflective-strip
// unfolding lives entirely in this frame.
//

public struct CourseAxis: Hashable, Codable {
    public var origin: Point2D       // point A
    public var destination: Point2D  // point B

    public init(origin: Point2D, destination: Point2D) {
        self.origin = origin
        self.destination = destination
    }

    public var asVector: Vector2D { destination - origin }

    public var length: Double { asVector.magnitude }

    public var u: Vector2D { asVector.normalized() }   // along AB

    public var n: Vector2D { u.perpendicularLeft() }   // left of AB

    /// Convert a world-frame point into course-frame (s, n).
    public func toCourse(_ p: Point2D) -> Point2D {
        let v = p - origin
        return Point2D(x: Vector2D.dot(v, u), y: Vector2D.dot(v, n))
    }

    /// Convert a course-frame (s, n) back into world coordinates.
    public func fromCourse(s: Double, n: Double) -> Point2D {
        origin + (s * u) + (n * self.n)
    }

    public func fromCourse(_ p: Point2D) -> Point2D {
        fromCourse(s: p.x, n: p.y)
    }
}
