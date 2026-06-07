import Foundation

/// A lightweight scenario wrapper for use with Swift Testing's `@Test(arguments:)`.
///
/// `GherkinTestScenario` loads and expands Gherkin feature files into individual
/// scenario test cases, each of which can be executed against step definition types.
///
/// Usage with Swift Testing:
/// ```swift
/// import Testing
/// import PickleKit
///
/// @Suite struct MyTests {
///     @Test(arguments: GherkinTestScenario.scenarios(
///         bundle: .module, subdirectory: "Features"
///     ))
///     func scenario(_ test: GherkinTestScenario) async throws {
///         let result = try await test.run(stepDefinitions: [MySteps.self])
///         #expect(result.passed)
///     }
/// }
/// ```
public struct GherkinTestScenario: Sendable, CustomStringConvertible {

    /// The concrete scenario to execute.
    public let scenario: Scenario

    /// Optional background steps to run before the scenario.
    public let background: Background?

    /// The feature this scenario belongs to.
    public let feature: Feature

    /// Display name for Swift Testing's parameterized test labels.
    public var description: String { scenario.name }

    public init(scenario: Scenario, background: Background?, feature: Feature) {
        self.scenario = scenario
        self.background = background
        self.feature = feature
    }

    // MARK: - Loading from Bundle

    /// Load scenarios from a bundle directory, expanding outlines and applying tag filters.
    ///
    /// - Parameters:
    ///   - bundle: The bundle containing `.feature` files.
    ///   - subdirectory: Optional subdirectory within the bundle.
    ///   - tagFilter: Optional tag filter to include/exclude scenarios.
    /// - Returns: An array of test scenarios ready for `@Test(arguments:)`.
    public static func scenarios(
        bundle: Bundle,
        subdirectory: String? = nil,
        tagFilter: TagFilter? = nil,
        scenarioNameFilter: ScenarioNameFilter? = nil
    ) -> [GherkinTestScenario] {
        let parser = GherkinParser()
        let features: [Feature]
        do {
            features = try parser.parseBundle(bundle: bundle, subdirectory: subdirectory)
        } catch {
            return []
        }
        return buildScenarios(from: features, tagFilter: tagFilter, scenarioNameFilter: scenarioNameFilter)
    }

    // MARK: - Loading from Filesystem Paths

    /// Load scenarios from filesystem paths, expanding outlines and applying tag filters.
    ///
    /// - Parameters:
    ///   - paths: Array of path specification strings (files, directories, or `file:line` syntax).
    ///   - tagFilter: Optional tag filter to include/exclude scenarios.
    /// - Returns: An array of test scenarios ready for `@Test(arguments:)`.
    public static func scenarios(
        paths: [String],
        tagFilter: TagFilter? = nil,
        scenarioNameFilter: ScenarioNameFilter? = nil
    ) -> [GherkinTestScenario] {
        let parser = GherkinParser()
        let featurePaths = paths.compactMap { FeaturePath.parse($0) }
        let features: [Feature]
        do {
            let result = try parser.parsePaths(featurePaths)
            features = result.features
        } catch {
            return []
        }
        return buildScenarios(from: features, tagFilter: tagFilter, scenarioNameFilter: scenarioNameFilter)
    }

    // MARK: - Report Collection

    /// Shared result collector for HTML report generation across all `GherkinTestScenario` runs.
    nonisolated(unsafe) private static var _resultCollector = ReportResultCollector()
    nonisolated(unsafe) private static var _atexitRegistered = false

    /// The shared result collector. Accessible for programmatic use.
    public static var resultCollector: ReportResultCollector { _resultCollector }

    /// Whether HTML report generation is enabled. Reads `PICKLE_REPORT` env var.
    public static var reportEnabled: Bool {
        ProcessInfo.processInfo.environment["PICKLE_REPORT"] != nil
    }

    /// Output path for the HTML report. Reads `PICKLE_REPORT_PATH` env var.
    public static var reportOutputPath: String {
        ProcessInfo.processInfo.environment["PICKLE_REPORT_PATH"] ?? "pickle-report.html"
    }

    /// Write the collected report to disk.
    private static func writeReportIfNeeded() {
        let result = _resultCollector.buildTestRunResult()
        guard !result.featureResults.isEmpty else { return }
        let rawPath = ProcessInfo.processInfo.environment["PICKLE_REPORT_PATH"] ?? "pickle-report.html"
        let absolutePath: String
        if rawPath.hasPrefix("/") {
            absolutePath = rawPath
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            absolutePath = (cwd as NSString).appendingPathComponent(rawPath)
        }
        let env = ProcessInfo.processInfo.environment
        let suite = ReportSuite(specTitle: env["PICKLE_SPEC_TITLE"] ?? "Living Specification")
        let specPath = ReportSuite.defaultSpecPath(forReport: absolutePath, override: env["PICKLE_SPEC_PATH"])
        do {
            try suite.write(result: result, reportPath: absolutePath, specPath: specPath)
            fputs("PickleKit: report + living spec written to \(absolutePath), \(specPath)\n", stderr)
        } catch {
            // Sandboxed runners can't write arbitrary paths — fall back to temp.
            let fallbackReport = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent((rawPath as NSString).lastPathComponent)
            let fallbackSpec = ReportSuite.defaultSpecPath(forReport: fallbackReport)
            do {
                try suite.write(result: result, reportPath: fallbackReport, specPath: fallbackSpec)
                fputs("PickleKit: report + living spec written to \(fallbackReport), \(fallbackSpec)\n", stderr)
            } catch {
                fputs("PickleKit: Failed to write report: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private static func ensureAtexitRegistered() {
        guard !_atexitRegistered else { return }
        _atexitRegistered = true
        atexit {
            GherkinTestScenario.writeReportIfNeeded()
        }
    }

    // MARK: - Execution

    /// Execute this scenario against the given step definition types.
    ///
    /// - Parameters:
    ///   - stepDefinitions: Step definition types to instantiate and register.
    ///   - reportCollector: Optional collector for HTML report generation.
    ///     When `nil` and `PICKLE_REPORT` env var is set, results are automatically
    ///     collected into the shared `resultCollector` and written on process exit.
    /// - Returns: The scenario result.
    @discardableResult
    public func run(
        stepDefinitions: [any StepDefinitions.Type],
        reportCollector: ReportResultCollector? = nil
    ) async throws -> ScenarioResult {
        let registry = StepRegistry()

        var stepTypes = stepDefinitions
        if let envFilter = StepDefinitionFilter.fromEnvironment() {
            stepTypes = stepTypes.filter { envFilter.contains(String(describing: $0)) }
        }
        for stepType in stepTypes {
            let provider = stepType.init()
            provider.register(in: registry)
        }

        let runner = ScenarioRunner(registry: registry)
        let result = try await runner.run(
            scenario: scenario,
            background: background,
            feature: feature
        )

        let effectiveCollector: ReportResultCollector?
        if let collector = reportCollector {
            effectiveCollector = collector
        } else if Self.reportEnabled {
            Self.ensureAtexitRegistered()
            effectiveCollector = Self._resultCollector
        } else {
            effectiveCollector = nil
        }

        if let collector = effectiveCollector {
            collector.record(
                scenarioResult: result,
                featureName: feature.name,
                featureDescription: feature.description,
                featureTags: feature.tags,
                sourceFile: feature.sourceFile
            )
        }

        return result
    }

    // MARK: - Private

    /// Record a skipped scenario into the shared report collector when reporting is enabled.
    private static func recordSkippedIfNeeded(
        scenario: Scenario,
        feature: Feature
    ) {
        guard reportEnabled else { return }
        ensureAtexitRegistered()
        let skippedResult = ScenarioResult(
            scenarioName: scenario.name,
            passed: true,
            skipped: true,
            tags: scenario.tags
        )
        _resultCollector.record(
            scenarioResult: skippedResult,
            featureName: feature.name,
            featureDescription: feature.description,
            featureTags: feature.tags,
            sourceFile: feature.sourceFile
        )
    }

    private static func buildScenarios(
        from features: [Feature],
        tagFilter: TagFilter?,
        scenarioNameFilter: ScenarioNameFilter?
    ) -> [GherkinTestScenario] {
        let expander = OutlineExpander()
        let envFilter = TagFilter.fromEnvironment()

        let mergedFilter: TagFilter?
        switch (tagFilter, envFilter) {
        case let (compileTime?, env?):
            mergedFilter = compileTime.merging(env)
        case let (compileTime?, nil):
            mergedFilter = compileTime
        case let (nil, env?):
            mergedFilter = env
        case (nil, nil):
            mergedFilter = nil
        }

        let envNameFilter = ScenarioNameFilter.fromEnvironment()
        let mergedNameFilter: ScenarioNameFilter?
        switch (scenarioNameFilter, envNameFilter) {
        case let (compileTime?, env?):
            mergedNameFilter = compileTime.merging(env)
        case let (compileTime?, nil):
            mergedNameFilter = compileTime
        case let (nil, env?):
            mergedNameFilter = env
        case (nil, nil):
            mergedNameFilter = nil
        }

        var results: [GherkinTestScenario] = []

        for feature in features {
            let expanded = expander.expand(feature)

            for definition in expanded.scenarios {
                guard case .scenario(let scenario) = definition else { continue }

                if let filter = mergedFilter {
                    let allTags = feature.tags + scenario.tags
                    if !filter.shouldInclude(tags: allTags) {
                        recordSkippedIfNeeded(scenario: scenario, feature: feature)
                        continue
                    }
                }

                if let nameFilter = mergedNameFilter {
                    if !nameFilter.shouldInclude(name: scenario.name) {
                        recordSkippedIfNeeded(scenario: scenario, feature: feature)
                        continue
                    }
                }

                results.append(GherkinTestScenario(
                    scenario: scenario,
                    background: expanded.background,
                    feature: feature
                ))
            }
        }

        return results
    }
}
