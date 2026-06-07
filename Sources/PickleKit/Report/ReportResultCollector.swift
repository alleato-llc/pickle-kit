import Foundation
import os

/// Thread-safe accumulator for scenario results during a test run.
///
/// Call `record(scenarioResult:featureName:featureTags:sourceFile:)` after each scenario
/// completes, then call `buildTestRunResult()` to get the aggregated result grouped by feature.
public final class ReportResultCollector: Sendable {

    private struct CollectedScenario: Sendable {
        let scenarioResult: ScenarioResult
        let featureName: String
        let featureDescription: String
        let featureTags: [String]
        let sourceFile: String?
        let order: Int
    }

    private struct State: Sendable {
        var scenarios: [CollectedScenario] = []
        var startTime: Date = Date()
        var counter: Int = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    public init() {
        self.state = OSAllocatedUnfairLock(initialState: State())
    }

    /// Record a completed scenario result.
    public func record(
        scenarioResult: ScenarioResult,
        featureName: String,
        featureDescription: String = "",
        featureTags: [String] = [],
        sourceFile: String? = nil
    ) {
        state.withLock { state in
            let entry = CollectedScenario(
                scenarioResult: scenarioResult,
                featureName: featureName,
                featureDescription: featureDescription,
                featureTags: featureTags,
                sourceFile: sourceFile,
                order: state.counter
            )
            state.scenarios.append(entry)
            state.counter += 1
        }
    }

    /// Build the aggregated `TestRunResult`, grouping scenarios by feature name.
    /// Features are ordered by the first scenario recorded for each feature.
    public func buildTestRunResult() -> TestRunResult {
        let (scenarios, startTime) = state.withLock { state in
            (state.scenarios, state.startTime)
        }

        // Group by feature, preserving insertion order
        var featureOrder: [String] = []
        var featureGroups: [String: (description: String, tags: [String], sourceFile: String?, scenarios: [ScenarioResult])] = [:]

        for entry in scenarios.sorted(by: { $0.order < $1.order }) {
            if featureGroups[entry.featureName] == nil {
                featureOrder.append(entry.featureName)
                featureGroups[entry.featureName] = (
                    description: entry.featureDescription,
                    tags: entry.featureTags,
                    sourceFile: entry.sourceFile,
                    scenarios: []
                )
            }
            featureGroups[entry.featureName]?.scenarios.append(entry.scenarioResult)
        }

        let featureResults = featureOrder.compactMap { name -> FeatureResult? in
            guard let group = featureGroups[name] else { return nil }
            return FeatureResult(
                featureName: name,
                description: group.description,
                scenarioResults: group.scenarios,
                tags: group.tags,
                sourceFile: group.sourceFile
            )
        }

        return TestRunResult(
            featureResults: featureResults,
            startTime: startTime,
            endTime: Date()
        )
    }

    /// Reset all collected state.
    public func reset() {
        state.withLock { state in
            state.scenarios.removeAll()
            state.startTime = Date()
            state.counter = 0
        }
    }
}
