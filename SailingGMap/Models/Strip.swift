//
//  Strip.swift
//  Sailing
//
//  A `Strip` is a band of the plane perpendicular to AB, between two
//  arc-length values s_start and s_end on the course axis.  Inside a strip
//  the boat sails on a single tack at a single heading.
//
//  In the course frame (s, n), strip i is the rectangle
//      { (s, n) : s_i ≤ s ≤ s_{i+1},  n ∈ ℝ }
//  with a discrete orientation tag σ_i ∈ {+1, −1} (the tack).
//

import Foundation

public struct Strip: Hashable, Codable, Identifiable {
    public var id: Int          // index along the course
    public var sStart: Double   // arc-length at the leading boundary
    public var sEnd: Double     // arc-length at the trailing boundary
    public var tack: Tack       // discrete control state (±1)

    public init(id: Int, sStart: Double, sEnd: Double, tack: Tack) {
        precondition(sEnd >= sStart, "Strip must have non-negative width")
        self.id = id
        self.sStart = sStart
        self.sEnd = sEnd
        self.tack = tack
    }

    public var width: Double { sEnd - sStart }

    public var sMid: Double { (sStart + sEnd) / 2 }
}
