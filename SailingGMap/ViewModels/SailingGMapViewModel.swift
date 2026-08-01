//
//  SailingGMapViewModel.swift
//  Sailing
//

import Combine
import Foundation
import SailingCore
import SwiftUI

@MainActor
final class SailingGMapViewModel: ObservableObject {

    // MARK: - Inputs (bindable from controls)

    @Published var stripCount: Int = 8 {
        didSet { if stripCount % 2 != 0 { stripCount = max(2, stripCount - 1) } }
    }

    /// Tacking angle θ off the AB axis, in degrees (UI-friendly).
    /// Used directly unless ``deriveAngleFromWind`` is on.
    @Published var tackingAngleDegrees: Double = 45

    // MARK: - Wind (issue #16)
    //
    // `WindModel` existed but nothing referenced it, so the app had no wind
    // direction and no no-go enforcement — θ was a free slider that could be
    // set to angles no boat could sail. These bind it to the UI.

    /// Direction the wind blows **from**, in degrees clockwise from the
    /// cross-course axis. 0° puts the wind abeam (no tacking needed); 90° is
    /// dead upwind along the course.
    @Published var windFromDegrees: Double = 90

    /// Half-width of the close-hauled no-go zone. Realistic: 35°–50°.
    @Published var noGoHalfAngleDegrees: Double = 45

    /// When on, θ is derived from the wind instead of set by hand, so the
    /// displayed path is always one the boat could actually sail.
    @Published var deriveAngleFromWind: Bool = false

    /// Course length in arbitrary units.
    @Published var courseLength: Double = 100

    // Cost weights.
    @Published var turnPenalty: Double = 0
    @Published var headingChangeWeight: Double = 0
    @Published var swingPenalty: Double = 0
    @Published var foliationSmoothnessWeight: Double = 0

    // Topological extension (warped foliation).
    @Published var useWarpedField: Bool = false
    @Published var bumpAmplitude: Double = 0.12
    @Published var bumpSigma: Double = 18
    @Published var bumpCenterFraction: Double = 0.5

    // MARK: - Derived: core frames + fields

    /// The wind as configured, in the world frame. The course runs along +x,
    /// so `windFromDegrees = 90` points the wind straight down the course.
    var windModel: WindModel {
        WindModel(
            fromDirection: Vector2D(dx: 0, dy: 1).rotated(by: -windFromDegrees * .pi / 180),
            noGoHalfAngle: noGoHalfAngleDegrees * .pi / 180
        )
    }

    /// The smallest symmetric tacking angle that keeps both legs sailable,
    /// given the current wind. Zero when the rhumb line is already outside the
    /// no-go zone.
    var derivedTackingAngleDegrees: Double {
        windModel.tackingAngle(towards: axis) * 180 / .pi
    }

    /// Whether the rhumb line itself lies inside the no-go zone.
    var courseIsInNoGoZone: Bool { derivedTackingAngleDegrees > 0 }

    /// θ actually used by every derived path.
    var effectiveTackingAngleDegrees: Double {
        deriveAngleFromWind ? derivedTackingAngleDegrees : tackingAngleDegrees
    }

    var tackingAngleRadians: Double { effectiveTackingAngleDegrees * .pi / 180 }

    /// Whether the hand-set angle would put a leg inside the no-go zone —
    /// i.e. the drawn path is not one the boat could sail. Advisory only when
    /// ``deriveAngleFromWind`` is off.
    var handSetAngleIsUnsailable: Bool {
        guard !deriveAngleFromWind, courseIsInNoGoZone else { return false }
        return tackingAngleDegrees + 1e-9 < derivedTackingAngleDegrees
    }

    var axis: CourseAxis {
        CourseAxis(
            origin: Point2D(x: 0, y: 0),
            destination: Point2D(x: courseLength, y: 0)
        )
    }

    /// Visible half-width of the corridor in the course frame.  Chosen to
    /// comfortably contain the rhumb-line zig-zag's cross-track peak.
    var halfWidth: Double {
        let peak = (courseLength / Double(max(stripCount, 2))) * tan(tackingAngleRadians)
        return max(20, peak * 2.2)
    }

    /// The active progress field — linear (rhumb-line) or warped (Gaussian
    /// bump deformation).
    var progressField: AnyProgressField {
        if useWarpedField {
            return AnyProgressField(
                WarpedProgressField(
                    axis: axis,
                    halfWidth: halfWidth,
                    amplitude: bumpAmplitude,
                    sigma: bumpSigma,
                    sCenterFraction: bumpCenterFraction,
                    nCenter: 0
                ))
        } else {
            return AnyProgressField(
                LinearProgressField(
                    axis: axis, halfWidth: halfWidth
                ))
        }
    }

    // MARK: - Derived: paths

    /// Rectilinear prototype: rectangular strips perpendicular to AB.
    var rhumbPath: TackPath {
        TackPath.uniformAlternating(
            axis: axis,
            stripCount: stripCount,
            tackingAngle: tackingAngleRadians,
            startingTack: .starboard
        )
    }

    /// Continuous generalisation over the active progress field.
    var generalizedPath: GeneralizedTackPath {
        GeneralizedTackPath.uniformAlternating(
            field: progressField,
            bandCount: stripCount,
            tackingAngle: tackingAngleRadians
        )
    }

    // MARK: - Derived: visualisation helpers

    var courseVertices: [Point2D] { rhumbPath.courseVertices() }

    var unfoldedVertices: [Point2D] {
        Unfolding.unfoldByHorizontalReflections(of: rhumbPath)
    }

    /// Level curves of the active progress field — interior boundaries
    /// only (excludes c = 0 and c = 1 which coincide with A and B).
    ///
    /// Cached: SwiftUI calls `body` far more often than any input changes, and
    /// this is bisection-heavy (issue #18). `drawBandShading` reads this rather
    /// than recomputing the identical curves a second time per frame.
    var foliationLevelCurves: [[Point2D]] {
        Self.levelCurveCache.value(for: fieldCacheKey) {
            Foliation.levelCurves(of: progressField, count: stripCount - 1, samples: 48)
        }
    }

    /// Every metric derivable from the integrated trajectory, from **one**
    /// integration and cached across redraws.
    var trajectoryMetrics: GeneralizedTackPath.TrajectoryMetrics {
        Self.metricsCache.value(for: fieldCacheKey) { generalizedPath.metrics() }
    }

    /// Integrated trajectory γ(t) on the generalised path, in course frame.
    var integratedTrajectoryCourse: [Point2D] { trajectoryMetrics.points }

    /// Whether the integrated trajectory actually reached B. A strongly warped
    /// field can stall at half the course; before #14 the canvas drew that
    /// truncated path with no indication anything was wrong.
    var trajectoryArrived: Bool { trajectoryMetrics.arrived }

    // MARK: - Caching
    //
    // Everything derived is a function of these inputs. One key covers them
    // all: a change to any of them invalidates every cached product, and
    // nothing else can.

    private struct FieldCacheKey: Hashable {
        let stripCount: Int
        let tackingAngle: Double
        let courseLength: Double
        let useWarped: Bool
        let amplitude: Double
        let sigma: Double
        let centerFraction: Double
    }

    private var fieldCacheKey: FieldCacheKey {
        FieldCacheKey(
            stripCount: stripCount,
            tackingAngle: tackingAngleRadians,
            courseLength: courseLength,
            useWarped: useWarpedField,
            amplitude: bumpAmplitude,
            sigma: bumpSigma,
            centerFraction: bumpCenterFraction
        )
    }

    /// Single-entry memo. The access pattern is "same key many times in a row,
    /// then a new key forever", so one slot is the right size — an unbounded
    /// dictionary would just leak every slider position the user passed through.
    @MainActor
    final class Memo<Key: Hashable, Value> {
        private var key: Key?
        private var stored: Value?

        func value(for key: Key, compute: () -> Value) -> Value {
            if key == self.key, let stored { return stored }
            let fresh = compute()
            self.key = key
            self.stored = fresh
            return fresh
        }
    }

    private static let levelCurveCache = Memo<FieldCacheKey, [[Point2D]]>()
    private static let metricsCache = Memo<FieldCacheKey, GeneralizedTackPath.TrajectoryMetrics>()
    private static let topologyCache = Memo<TopologyCacheKey, GMapSummary>()

    private struct TopologyCacheKey: Hashable {
        let stripCount: Int
        let startingTack: Tack
    }

    // MARK: - Metrics

    var costModel: TackingCost {
        TackingCost(
            lengthWeight: 1,
            turnPenalty: turnPenalty,
            headingChangeWeight: headingChangeWeight,
            swingPenalty: swingPenalty,
            foliationSmoothnessWeight: foliationSmoothnessWeight
        )
    }

    var costBreakdownRhumb: CostBreakdown {
        costModel.breakdown(rhumbPath)
    }

    var costBreakdownGeneralized: CostBreakdown {
        costModel.breakdown(generalizedPath, field: progressField)
    }

    /// 0 → no violations, 1 → every grid sample violates ∂s/∂s_coord > 0.
    var monotonicityViolation: Double {
        Foliation.monotonicityViolations(of: progressField)
    }

    // MARK: - G-map summary

    struct GMapSummary {
        let darts: Int
        let vertices: Int
        let edges: Int
        let faces: Int
        let euler: Int
        let valid: Bool
        let reflectiveEdges: Int
    }

    /// Cached: the G-map depends only on the strip count and tack sequence, and
    /// rebuilding it dominated redraw cost at 3.4 ms (issue #18).
    var gmapSummary: GMapSummary {
        Self.topologyCache.value(
            for: TopologyCacheKey(stripCount: stripCount, startingTack: .starboard)
        ) { Self.summarise(SailingGMapTopology(path: rhumbPath)) }
    }

    private static func summarise(_ topology: SailingGMapTopology) -> GMapSummary {
        GMapSummary(
            darts: topology.dartCount,
            vertices: topology.vertexCount,
            edges: topology.edgeCount,
            faces: topology.faceCount,
            euler: topology.eulerCharacteristic,
            valid: topology.isValid,
            reflectiveEdges: topology.reflectiveAlpha2Edges
        )
    }

    // MARK: - Optimisation

    func runUniformOptimisation() -> (count: Int, cost: Double) {
        if useWarpedField {
            let r = Optimization.uniformGeneralizedOptimum(
                field: progressField,
                tackingAngle: tackingAngleRadians,
                cost: costModel
            )
            return (r.bandCount, r.cost)
        } else {
            let r = Optimization.uniformOptimum(
                axis: axis,
                tackingAngle: tackingAngleRadians,
                cost: costModel
            )
            return (r.stripCount, r.cost)
        }
    }
}
