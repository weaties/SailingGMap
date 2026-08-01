//
//  IntegrationBudgetTests.swift
//  SailingCoreTests
//
//  Issue #18. A caching or consolidation layer that silently misses is worse
//  than none — it looks fast in review and is slow in practice. These tests
//  count the actual work done rather than trusting that it was avoided.
//
//  The counter lives in the progress field because every integration step
//  calls `gradient` exactly once, making it an exact proxy for step count.
//

import Foundation
import Testing

@testable import SailingCore

/// A `ProgressField` that counts how many times it has been sampled.
///
/// Reference-typed counter so copies of the (value-typed) field share it —
/// `AnyProgressField` boxes the field in closures, so a struct-local counter
/// would be invisible from the test.
private final class SampleCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _gradient = 0

    var gradientCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _gradient
    }

    func recordGradient() {
        lock.lock()
        _gradient += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _gradient = 0
        lock.unlock()
    }
}

private struct CountingField: ProgressField {
    let counter: SampleCounter
    let inner: LinearProgressField

    var axis: CourseAxis { inner.axis }
    var halfWidth: Double { inner.halfWidth }

    func value(sCoord: Double, nCoord: Double) -> Double {
        inner.value(sCoord: sCoord, nCoord: nCoord)
    }

    func gradient(sCoord: Double, nCoord: Double) -> Vector2D {
        counter.recordGradient()
        return inner.gradient(sCoord: sCoord, nCoord: nCoord)
    }

    func laplacian(sCoord: Double, nCoord: Double) -> Double {
        inner.laplacian(sCoord: sCoord, nCoord: nCoord)
    }
}

@Suite("Integration budget")
struct IntegrationBudgetTests {

    private func makePath() -> (GeneralizedTackPath, AnyProgressField, SampleCounter) {
        let counter = SampleCounter()
        let axis = CourseAxis.canonical(length: 100)
        let field = AnyProgressField(
            CountingField(counter: counter, inner: LinearProgressField(axis: axis, halfWidth: 50)))
        let path = GeneralizedTackPath.uniformAlternating(
            field: field, bandCount: 8, tackingAngle: .pi / 4)
        return (path, field, counter)
    }

    @Test("a single integration is the unit of work")
    func singleIntegrationBaseline() {
        let (path, _, counter) = makePath()
        _ = path.integrate()
        // Every step samples the gradient exactly once, so this is the step count.
        #expect(counter.gradientCalls > 100)
    }

    @Test("metrics() integrates exactly once, not three times")
    func metricsIntegratesOnce() {
        let (path, _, counter) = makePath()

        _ = path.integrate()
        let oneIntegration = counter.gradientCalls

        counter.reset()
        let m = path.metrics()
        let viaMetrics = counter.gradientCalls

        // All three metrics come out of one pass.
        #expect(viaMetrics == oneIntegration)
        #expect(m.sailedLength > 0)
        #expect(m.crossTrackPeak > 0)
        #expect(m.headingChanges.count == 7)
    }

    @Test("a cost breakdown integrates exactly once")
    func costBreakdownIntegratesOnce() {
        let (path, field, counter) = makePath()

        _ = path.integrate()
        let oneIntegration = counter.gradientCalls

        counter.reset()
        _ = TackingCost(
            lengthWeight: 1, turnPenalty: 1, headingChangeWeight: 1, swingPenalty: 1
        ).breakdown(path, field: field)

        // Before #18 this was 3x: sailedLength, headingChangesAtTurns and
        // crossTrackPeak each integrated independently.
        #expect(counter.gradientCalls == oneIntegration)
    }

    @Test("NEGATIVE CONTROL: asking for three metrics separately really does cost three passes")
    func separateAccessorsStillCostThreePasses() {
        // The control that gives the previous test meaning. If the individual
        // accessors were also somehow free, `costBreakdownIntegratesOnce` would
        // pass trivially and prove nothing about the consolidation.
        let (path, _, counter) = makePath()

        _ = path.integrate()
        let oneIntegration = counter.gradientCalls

        counter.reset()
        _ = path.sailedLength()
        _ = path.crossTrackPeak()
        _ = path.headingChangesAtTurns()

        #expect(counter.gradientCalls == 3 * oneIntegration)
    }

    @Test("metrics agree with the individual accessors")
    func metricsAgreeWithAccessors() {
        // Consolidation must not change the answers.
        let (path, _, _) = makePath()
        let m = path.metrics()

        #expect(isApprox(m.sailedLength, path.sailedLength(), relative: 1e-12))
        #expect(isApprox(m.crossTrackPeak, path.crossTrackPeak(), relative: 1e-12))
        let separate = path.headingChangesAtTurns()
        #expect(m.headingChanges.count == separate.count)
        #expect(
            zip(m.headingChanges, separate).allSatisfy { isApprox($0, $1, absolute: 1e-12) })
    }
}
