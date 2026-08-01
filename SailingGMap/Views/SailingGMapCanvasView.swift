//
//  SailingGMapCanvasView.swift
//  Sailing
//
//  Two views in one:
//    .courseFrame  — the (s, n) frame plus strip boundaries (straight
//                     vertical lines for the linear field, level curves
//                     of s for the warped field).  The rhumb-line zig-zag
//                     and, when the warped field is active, the integrated
//                     trajectory γ(t) are both drawn here.
//    .unfolded     — the same rhumb-line path after billiard-style
//                     unfolding by horizontal reflections; should appear
//                     as a single straight line of slope tan θ.
//

import SailingCore
import SwiftUI

struct SailingGMapCanvasView: View {
    enum Mode { case courseFrame, unfolded }

    @ObservedObject var vm: SailingGMapViewModel
    let mode: Mode

    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 24
            let drawRect = CGRect(
                x: pad, y: pad,
                width: size.width - 2 * pad,
                height: size.height - 2 * pad
            )
            let title =
                (mode == .courseFrame)
                ? (vm.useWarpedField
                    ? "Course frame — warped foliation + integrated γ(t)"
                    : "Course frame (s, n) — rhumb-line zig-zag")
                : "Covering frame — unfolded straight line"
            drawTitle(title, in: ctx, at: CGPoint(x: pad, y: 4))

            switch mode {
            case .courseFrame: drawCourseFrame(ctx, in: drawRect)
            case .unfolded: drawUnfolded(ctx, in: drawRect)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Drawing

    private func drawTitle(_ s: String, in ctx: GraphicsContext, at p: CGPoint) {
        ctx.draw(
            Text(s).font(.caption).foregroundColor(.secondary),
            at: p, anchor: .topLeading
        )
    }

    private func drawCourseFrame(_ ctx: GraphicsContext, in rect: CGRect) {
        let L = vm.courseLength
        let W = vm.halfWidth

        let nRange = ClosedRange(uncheckedBounds: (-W * 1.05, W * 1.05))
        let sRange = ClosedRange(uncheckedBounds: (-0.02 * L, 1.02 * L))

        let xform = makeTransform(
            domainX: sRange,
            domainY: nRange,
            range: rect)

        // 1. Band shading using level curves (linear ⇒ rectangles).
        drawBandShading(ctx, xform: xform, halfWidth: W)

        // 2. AB axis.
        var axisPath = Path()
        axisPath.move(to: xform(.init(x: 0, y: 0)))
        axisPath.addLine(to: xform(.init(x: L, y: 0)))
        ctx.stroke(
            axisPath, with: .color(.gray.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 3. Level curves (interior strip boundaries).
        let curves = vm.foliationLevelCurves
        for curve in curves {
            var path = Path()
            for (i, p) in curve.enumerated() {
                let q = xform(CGPoint(x: p.x, y: p.y))
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            ctx.stroke(
                path, with: .color(.gray.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1))
        }

        // 4. Rhumb-line zig-zag (always shown as the reference path).
        let rhumbVerts = vm.courseVertices
        var rhumb = Path()
        for (i, v) in rhumbVerts.enumerated() {
            let p = xform(CGPoint(x: v.x, y: v.y))
            if i == 0 { rhumb.move(to: p) } else { rhumb.addLine(to: p) }
        }
        let rhumbColor: Color =
            vm.useWarpedField
            ? Color.accentColor.opacity(0.35) : .accentColor
        ctx.stroke(
            rhumb, with: .color(rhumbColor),
            style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        for (i, v) in rhumbVerts.enumerated() {
            let p = xform(CGPoint(x: v.x, y: v.y))
            let r = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            let dotColor: Color =
                (i == 0 || i == rhumbVerts.count - 1)
                ? .orange : rhumbColor
            ctx.fill(Path(ellipseIn: r), with: .color(dotColor))
        }

        // 5. Integrated trajectory γ(t) on the warped foliation.
        if vm.useWarpedField {
            let pts = vm.integratedTrajectoryCourse
            var path = Path()
            for (i, p) in pts.enumerated() {
                let q = xform(CGPoint(x: p.x, y: p.y))
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            ctx.stroke(
                path, with: .color(.pink),
                style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }

        // 6. Endpoints labels.
        if let a = rhumbVerts.first {
            let p = xform(CGPoint(x: a.x, y: a.y))
            ctx.draw(
                Text("A").font(.caption2).bold(),
                at: CGPoint(x: p.x - 10, y: p.y), anchor: .trailing)
        }
        let bWorld = CGPoint(x: L, y: 0)
        let pB = xform(bWorld)
        ctx.draw(
            Text("B").font(.caption2).bold(),
            at: CGPoint(x: pB.x + 10, y: pB.y), anchor: .leading)
    }

    /// Shade the alternating bands between consecutive level curves.
    /// For a linear field these collapse to vertical rectangles; for a
    /// warped field they are bowed slabs.
    private func drawBandShading(
        _ ctx: GraphicsContext,
        xform: (CGPoint) -> CGPoint,
        halfWidth W: Double
    ) {
        let path = vm.generalizedPath
        let field = vm.progressField
        let bandCount = path.tacks.count
        // Build the left and right boundary polylines for each band.
        // Boundary at c = 0 is the line s = 0 (the A-edge); boundary at
        // c = 1 is s = L (the B-edge).  Interior boundaries are level
        // curves of `field`.
        let interior = Foliation.levelCurves(
            of: field,
            count: bandCount - 1,
            samples: 48)
        // Synthesize the two end-curves as straight vertical lines so
        // every band is bounded by two polylines of the same length.
        let nSamples = 48
        func verticalBoundary(at s: Double) -> [Point2D] {
            (0..<nSamples).map { k in
                let t = Double(k) / Double(nSamples - 1)
                let n = -W + 2 * W * t
                return Point2D(x: s, y: n)
            }
        }
        var boundaries: [[Point2D]] = []
        boundaries.append(verticalBoundary(at: field.axis.length * 0))
        boundaries.append(contentsOf: interior)
        boundaries.append(verticalBoundary(at: field.axis.length))

        for i in 0..<bandCount {
            let left = boundaries[i]
            let right = boundaries[i + 1]
            var poly = Path()
            // Walk left bottom→top, then right top→bottom.
            for (k, p) in left.enumerated() {
                let q = xform(CGPoint(x: p.x, y: p.y))
                if k == 0 { poly.move(to: q) } else { poly.addLine(to: q) }
            }
            for p in right.reversed() {
                let q = xform(CGPoint(x: p.x, y: p.y))
                poly.addLine(to: q)
            }
            poly.closeSubpath()
            let tack = path.tacks[i]
            let fill: Color =
                (tack == .starboard)
                ? Color.green.opacity(0.07)
                : Color.red.opacity(0.07)
            ctx.fill(poly, with: .color(fill))
        }
    }

    private func drawUnfolded(_ ctx: GraphicsContext, in rect: CGRect) {
        let verts = vm.unfoldedVertices
        guard let last = verts.last else { return }
        let xMax = max(last.x, 1e-3)
        let yMax = max(last.y, 1e-3) * 1.15

        let xform = makeTransform(
            domainX: ClosedRange(uncheckedBounds: (0, xMax)),
            domainY: ClosedRange(uncheckedBounds: (0, yMax)),
            range: rect
        )

        // The expected straight line from (0,0) to last.
        var ideal = Path()
        ideal.move(to: xform(.init(x: 0, y: 0)))
        ideal.addLine(to: xform(.init(x: last.x, y: last.y)))
        ctx.stroke(
            ideal, with: .color(.gray.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        // Polyline of unfolded vertices (should overlay the ideal line).
        var poly = Path()
        for (i, v) in verts.enumerated() {
            let p = xform(CGPoint(x: v.x, y: v.y))
            if i == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
        }
        ctx.stroke(
            poly, with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2.5))

        for v in verts {
            let p = xform(CGPoint(x: v.x, y: v.y))
            let r = CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: r), with: .color(.accentColor))
        }

        // Slope label
        let θ = vm.tackingAngleRadians
        let label = String(format: "slope = tan θ = %.3f", tan(θ))
        ctx.draw(
            Text(label).font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: rect.maxX - 8, y: rect.minY + 4),
            anchor: .topTrailing)
    }

    // MARK: - 2D affine map from world rectangle to screen rectangle

    private func makeTransform(
        domainX: ClosedRange<Double>,
        domainY: ClosedRange<Double>,
        range: CGRect
    ) -> (CGPoint) -> CGPoint {
        let dx = max(domainX.upperBound - domainX.lowerBound, 1e-9)
        let dy = max(domainY.upperBound - domainY.lowerBound, 1e-9)
        let sx = range.width / dx
        let sy = range.height / dy
        let originX = range.minX
        let originY = range.maxY  // flip Y (screen y goes down)
        let dxLo = domainX.lowerBound
        let dyLo = domainY.lowerBound
        return { p in
            CGPoint(
                x: originX + sx * (p.x - dxLo),
                y: originY - sy * (p.y - dyLo)
            )
        }
    }
}
