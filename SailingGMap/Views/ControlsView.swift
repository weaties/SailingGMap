//
//  ControlsView.swift
//  Sailing
//

import SailingCore
import SwiftUI

struct ControlsView: View {
    @ObservedObject var vm: SailingGMapViewModel
    @State private var optimResult: (count: Int, cost: Double)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Tacking Path")
                    .font(.title3).bold()

                Group {
                    LabeledControl("Strips / bands", value: "\(vm.stripCount)") {
                        Slider(value: stripCountBinding, in: 2...32, step: 2)
                    }

                    LabeledControl(
                        "Tacking angle θ",
                        value: String(
                            format: "%.1f°",
                            vm.effectiveTackingAngleDegrees)
                    ) {
                        Slider(value: $vm.tackingAngleDegrees, in: 5...80)
                            .disabled(vm.deriveAngleFromWind)
                    }

                    LabeledControl(
                        "Course length L",
                        value: String(format: "%.0f", vm.courseLength)
                    ) {
                        Slider(value: $vm.courseLength, in: 20...400)
                    }
                }

                Divider()
                Text("Wind").font(.headline)

                LabeledControl(
                    "Wind from",
                    value: String(format: "%.0f°", vm.windFromDegrees)
                ) {
                    Slider(value: $vm.windFromDegrees, in: 0...180)
                }
                LabeledControl(
                    "No-go half-angle",
                    value: String(format: "%.0f°", vm.noGoHalfAngleDegrees)
                ) {
                    Slider(value: $vm.noGoHalfAngleDegrees, in: 25...60)
                }
                Toggle("Derive θ from wind", isOn: $vm.deriveAngleFromWind)
                    .toggleStyle(.switch)

                MetricRow(
                    "Course vs no-go zone",
                    vm.courseIsInNoGoZone ? "inside — must tack" : "clear — sail direct")
                MetricRow(
                    "Minimum sailable θ",
                    vm.courseIsInNoGoZone
                        ? String(format: "%.1f°", vm.derivedTackingAngleDegrees) : "—")

                if vm.handSetAngleIsUnsailable {
                    Label(
                        String(
                            format:
                                "θ = %.1f° puts a leg inside the no-go zone; %.1f° is the minimum.",
                            vm.tackingAngleDegrees, vm.derivedTackingAngleDegrees),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                Text("Progress field s(x, y)").font(.headline)
                Toggle("Warped (Gaussian bump)", isOn: $vm.useWarpedField)
                    .toggleStyle(.switch)

                Group {
                    LabeledControl(
                        "Bump amplitude",
                        value: String(
                            format: "%+.3f",
                            vm.bumpAmplitude)
                    ) {
                        Slider(value: $vm.bumpAmplitude, in: -0.30...0.30)
                    }
                    LabeledControl(
                        "Bump σ",
                        value: String(format: "%.1f", vm.bumpSigma)
                    ) {
                        Slider(value: $vm.bumpSigma, in: 4...60)
                    }
                    LabeledControl(
                        "Bump centre s/L",
                        value: String(
                            format: "%.2f",
                            vm.bumpCenterFraction)
                    ) {
                        Slider(value: $vm.bumpCenterFraction, in: 0.05...0.95)
                    }
                }
                .disabled(!vm.useWarpedField)
                .opacity(vm.useWarpedField ? 1.0 : 0.45)

                let vio = vm.monotonicityViolation
                MetricRow(
                    "Monotonicity violations",
                    String(format: "%.0f%%", vio * 100))

                Divider()
                Text("Cost weights").font(.headline)
                LabeledControl(
                    "Turn penalty λ",
                    value: String(format: "%.2f", vm.turnPenalty)
                ) {
                    Slider(value: $vm.turnPenalty, in: 0...20)
                }
                LabeledControl(
                    "Heading-change μ (×|Δθ|²)",
                    value: String(
                        format: "%.2f",
                        vm.headingChangeWeight)
                ) {
                    Slider(value: $vm.headingChangeWeight, in: 0...10)
                }
                LabeledControl(
                    "Swing penalty",
                    value: String(format: "%.2f", vm.swingPenalty)
                ) {
                    Slider(value: $vm.swingPenalty, in: 0...5)
                }
                LabeledControl(
                    "Foliation ν (×∫|Δs|²)",
                    value: String(
                        format: "%.2f",
                        vm.foliationSmoothnessWeight)
                ) {
                    Slider(value: $vm.foliationSmoothnessWeight, in: 0...100)
                }

                Divider()
                Text("Cost breakdown").font(.headline)
                let cb =
                    vm.useWarpedField
                    ? vm.costBreakdownGeneralized
                    : vm.costBreakdownRhumb
                MetricRow("· length", String(format: "%.3f", cb.length))
                MetricRow("· turns", String(format: "%.3f", cb.turns))
                MetricRow("· heading-change", String(format: "%.3f", cb.headingChange))
                MetricRow("· swing", String(format: "%.3f", cb.swing))
                MetricRow("· foliation smooth.", String(format: "%.3f", cb.foliationSmoothness))
                MetricRow("total J", String(format: "%.3f", cb.total))

                Divider()
                Text("GeneralizedMap topology").font(.headline)
                let s = vm.gmapSummary
                MetricRow("Darts", "\(s.darts)")
                MetricRow("Vertices", "\(s.vertices)")
                MetricRow("Edges", "\(s.edges)")
                MetricRow("Faces", "\(s.faces)")
                MetricRow("χ = V−E+F", "\(s.euler)")
                MetricRow("Reflective α₂-edges", "\(s.reflectiveEdges)")
                MetricRow("Involution check", s.valid ? "✓ valid" : "✗ broken")

                Divider()
                Text("Optimisation").font(.headline)
                Button {
                    optimResult = vm.runUniformOptimisation()
                } label: {
                    Text("Search uniform optimum")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                if let r = optimResult {
                    MetricRow("Best N", "\(r.count)")
                    MetricRow("Best J", String(format: "%.3f", r.cost))
                }

                Spacer(minLength: 12)
            }
            .padding(16)
        }
    }

    private var stripCountBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(vm.stripCount) },
            set: { vm.stripCount = Int($0) }
        )
    }
}

// MARK: - Small helpers

private struct LabeledControl<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder var content: () -> Content

    init(
        _ title: String, value: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.value = value
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(value)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }
}
