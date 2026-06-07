import Foundation

// MARK: - Runner Errors

public enum ScenarioRunnerError: Error, LocalizedError {
    case undefinedStep(step: Step, feature: String?, file: String?)
    case stepFailed(step: Step, feature: String?, scenario: String?, underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case .undefinedStep(let step, let feature, let file):
            let location = [file, feature].compactMap { $0 }.joined(separator: " / ")
            return "Undefined step at line \(step.sourceLine): \(step.keyword.rawValue) \(step.text)"
                + (location.isEmpty ? "" : " (\(location))")
        case .stepFailed(let step, _, let scenario, let error):
            return "Step failed at line \(step.sourceLine) in '\(scenario ?? "unknown")': "
                + "\(step.keyword.rawValue) \(step.text) — \(error.localizedDescription)"
        }
    }
}

// MARK: - Scenario Result

public struct ScenarioResult: Sendable {
    public let scenarioName: String
    public let passed: Bool
    public let skipped: Bool
    public let error: (any Error)?
    public let stepsExecuted: Int
    public let tags: [String]
    public let stepResults: [StepResult]
    public let duration: TimeInterval

    public init(
        scenarioName: String,
        passed: Bool,
        skipped: Bool = false,
        error: (any Error)? = nil,
        stepsExecuted: Int = 0,
        tags: [String] = [],
        stepResults: [StepResult] = [],
        duration: TimeInterval = 0
    ) {
        self.scenarioName = scenarioName
        self.passed = passed
        self.skipped = skipped
        self.error = error
        self.stepsExecuted = stepsExecuted
        self.tags = tags
        self.stepResults = stepResults
        self.duration = duration
    }
}

// MARK: - Feature Result

public struct FeatureResult: Sendable {
    public let featureName: String
    /// The feature's narrative (`As a / I want / So that`), preserved from
    /// the source so the living-specification view can render intent.
    public let description: String
    public let scenarioResults: [ScenarioResult]
    public let tags: [String]
    public let sourceFile: String?
    public let duration: TimeInterval

    public init(
        featureName: String,
        description: String = "",
        scenarioResults: [ScenarioResult],
        tags: [String] = [],
        sourceFile: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.featureName = featureName
        self.description = description
        self.scenarioResults = scenarioResults
        self.tags = tags
        self.sourceFile = sourceFile
        self.duration = duration
    }

    public var passedCount: Int { scenarioResults.filter { $0.passed && !$0.skipped }.count }
    public var failedCount: Int { scenarioResults.filter { !$0.passed && !$0.skipped }.count }
    public var skippedCount: Int { scenarioResults.filter(\.skipped).count }
    public var allPassed: Bool { scenarioResults.filter { !$0.skipped }.allSatisfy(\.passed) }

    public var totalStepCount: Int {
        scenarioResults.reduce(0) { $0 + $1.stepResults.count }
    }

    public var passedStepCount: Int {
        scenarioResults.reduce(0) { $0 + $1.stepResults.filter { $0.status == .passed }.count }
    }

    public var failedStepCount: Int {
        scenarioResults.reduce(0) { $0 + $1.stepResults.filter { $0.status == .failed }.count }
    }

    public var skippedStepCount: Int {
        scenarioResults.reduce(0) { $0 + $1.stepResults.filter { $0.status == .skipped }.count }
    }

    public var undefinedStepCount: Int {
        scenarioResults.reduce(0) { $0 + $1.stepResults.filter { $0.status == .undefined }.count }
    }
}

// MARK: - Scenario Runner

/// Executes scenarios against a step registry.
public final class ScenarioRunner: Sendable {

    private let registry: StepRegistry

    public init(registry: StepRegistry) {
        self.registry = registry
    }

    // MARK: - Run Single Scenario

    /// Run a single scenario, optionally with background steps.
    public func run(
        scenario: Scenario,
        background: Background? = nil,
        feature: Feature? = nil
    ) async throws -> ScenarioResult {
        var stepsExecuted = 0
        var stepResults: [StepResult] = []
        let allSteps = (background?.steps ?? []) + scenario.steps
        let scenarioStart = ContinuousClock.now

        do {
            // Run background steps first
            if let background = background {
                for step in background.steps {
                    let stepStart = ContinuousClock.now
                    try await executeStep(step, feature: feature, scenarioName: scenario.name)
                    let stepDuration = stepStart.duration(to: .now)
                    stepsExecuted += 1
                    stepResults.append(StepResult(
                        keyword: step.keyword.rawValue,
                        text: step.text,
                        status: .passed,
                        duration: stepDuration.timeInterval,
                        sourceLine: step.sourceLine
                    ))
                }
            }

            // Run scenario steps
            for step in scenario.steps {
                let stepStart = ContinuousClock.now
                try await executeStep(step, feature: feature, scenarioName: scenario.name)
                let stepDuration = stepStart.duration(to: .now)
                stepsExecuted += 1
                stepResults.append(StepResult(
                    keyword: step.keyword.rawValue,
                    text: step.text,
                    status: .passed,
                    duration: stepDuration.timeInterval,
                    sourceLine: step.sourceLine
                ))
            }

            let scenarioDuration = scenarioStart.duration(to: .now)
            return ScenarioResult(
                scenarioName: scenario.name,
                passed: true,
                stepsExecuted: stepsExecuted,
                tags: scenario.tags,
                stepResults: stepResults,
                duration: scenarioDuration.timeInterval
            )
        } catch {
            // Mark the failing step
            let failedStepIndex = stepsExecuted
            if failedStepIndex < allSteps.count {
                let failedStep = allSteps[failedStepIndex]
                let isUndefined: Bool
                if let runnerError = error as? ScenarioRunnerError,
                   case .undefinedStep = runnerError {
                    isUndefined = true
                } else {
                    isUndefined = false
                }
                stepResults.append(StepResult(
                    keyword: failedStep.keyword.rawValue,
                    text: failedStep.text,
                    status: isUndefined ? .undefined : .failed,
                    error: error.localizedDescription,
                    sourceLine: failedStep.sourceLine
                ))
            }

            // Mark remaining steps as skipped
            for i in (failedStepIndex + 1)..<allSteps.count {
                let skippedStep = allSteps[i]
                stepResults.append(StepResult(
                    keyword: skippedStep.keyword.rawValue,
                    text: skippedStep.text,
                    status: .skipped,
                    sourceLine: skippedStep.sourceLine
                ))
            }

            let scenarioDuration = scenarioStart.duration(to: .now)
            return ScenarioResult(
                scenarioName: scenario.name,
                passed: false,
                error: error,
                stepsExecuted: stepsExecuted,
                tags: scenario.tags,
                stepResults: stepResults,
                duration: scenarioDuration.timeInterval
            )
        }
    }

    // MARK: - Run Feature

    /// Run all scenarios in a feature, expanding outlines first.
    public func run(feature: Feature, tagFilter: TagFilter? = nil) async throws -> FeatureResult {
        let expander = OutlineExpander()
        let expandedFeature = expander.expand(feature)
        let featureStart = ContinuousClock.now

        var results: [ScenarioResult] = []

        for definition in expandedFeature.scenarios {
            guard case .scenario(let scenario) = definition else { continue }

            // Apply tag filter (combine feature + scenario tags)
            if let filter = tagFilter {
                let allTags = feature.tags + scenario.tags
                if !filter.shouldInclude(tags: allTags) {
                    results.append(ScenarioResult(
                        scenarioName: scenario.name,
                        passed: true,
                        skipped: true,
                        tags: scenario.tags
                    ))
                    continue
                }
            }

            let result = await (try run(
                scenario: scenario,
                background: expandedFeature.background,
                feature: feature
            ))
            results.append(result)
        }

        let featureDuration = featureStart.duration(to: .now)
        return FeatureResult(
            featureName: feature.name,
            scenarioResults: results,
            tags: feature.tags,
            sourceFile: feature.sourceFile,
            duration: featureDuration.timeInterval
        )
    }

    // MARK: - Private

    private func executeStep(_ step: Step, feature: Feature?, scenarioName: String?) async throws {
        guard let (handler, match) = try registry.match(step) else {
            throw ScenarioRunnerError.undefinedStep(
                step: step,
                feature: feature?.name,
                file: feature?.sourceFile
            )
        }

        do {
            try await handler(match)
        } catch {
            throw ScenarioRunnerError.stepFailed(
                step: step,
                feature: feature?.name,
                scenario: scenarioName,
                underlyingError: error
            )
        }
    }
}

// MARK: - Duration Extension

internal extension Duration {
    /// Convert a Swift `Duration` to `TimeInterval` (seconds as Double).
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
