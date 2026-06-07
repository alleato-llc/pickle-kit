#if canImport(XCTest) && canImport(ObjectiveC)
import XCTest
import ObjectiveC
import Foundation

/// Error type representing XCTest assertion failures detected during scenario execution.
/// Used when step handlers call XCTAssert* (which records failures on the test case
/// but does not throw), causing ScenarioRunner to see the step as passing.
public struct XCTestAssertionError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) {
        self.message = message
    }
}

/// Base class for Gherkin-driven XCTest suites.
///
/// Subclass this in your test target and override `registerStepDefinitions()`
/// and `featureBundle` / `featureSubdirectory` to configure which feature files
/// are loaded and how steps are matched.
///
/// Each scenario becomes a separate test method in the Xcode test navigator.
///
/// Example:
/// ```swift
/// final class MyFeatureTests: GherkinTestCase {
///     override class var featureSubdirectory: String? { "Features" }
///
///     override func registerStepDefinitions() {
///         given("I have (\\d+) apples") { match in
///             let count = Int(match.captures[0])!
///             // ...
///         }
///     }
/// }
/// ```
open class GherkinTestCase: XCTestCase {

    // MARK: - Configuration (Override in Subclasses)

    /// The bundle containing .feature files. Defaults to the test bundle.
    open class var featureBundle: Bundle { Bundle(for: self) }

    /// Subdirectory within the bundle to search for .feature files.
    open class var featureSubdirectory: String? { nil }

    /// Optional tag filter. Override to include/exclude scenarios by tags.
    open class var tagFilter: TagFilter? { nil }

    /// Optional scenario name filter. Override to include only scenarios with matching names.
    /// Combined with `CUCUMBER_SCENARIOS` env var (comma-separated, case-insensitive).
    open class var scenarioNameFilter: ScenarioNameFilter? { nil }

    /// Feature file paths to load (filesystem paths).
    /// Supports file paths, directory paths, and `file:line` syntax.
    /// When non-nil, overrides `featureBundle`/`featureSubdirectory`.
    /// Set `CUCUMBER_FEATURES` env var for runtime control (space-separated).
    open class var featurePaths: [String]? { nil }

    /// Step definition types to instantiate and register for each scenario.
    /// These are registered before `registerStepDefinitions()` is called,
    /// enabling both approaches to coexist.
    open class var stepDefinitionTypes: [any StepDefinitions.Type] { [] }

    /// Whether HTML report generation is enabled. Reads `PICKLE_REPORT` env var.
    /// Override in subclass for compile-time control.
    open class var reportEnabled: Bool {
        ProcessInfo.processInfo.environment["PICKLE_REPORT"] != nil
    }

    /// Output path for the HTML report. Reads `PICKLE_REPORT_PATH` env var.
    /// Override in subclass for compile-time control.
    open class var reportOutputPath: String {
        ProcessInfo.processInfo.environment["PICKLE_REPORT_PATH"] ?? "pickle-report.html"
    }

    /// Override to register step definitions before scenarios run.
    open func registerStepDefinitions() {
        // Subclasses override this
    }

    // MARK: - Registry Access

    /// The step registry for this test case instance.
    public let registry = StepRegistry()

    /// Convenience: register a Given step.
    public func given(_ pattern: String, handler: @escaping StepHandler) {
        registry.given(pattern, handler: handler)
    }

    /// Convenience: register a When step.
    public func when(_ pattern: String, handler: @escaping StepHandler) {
        registry.when(pattern, handler: handler)
    }

    /// Convenience: register a Then step.
    public func then(_ pattern: String, handler: @escaping StepHandler) {
        registry.then(pattern, handler: handler)
    }

    /// Convenience: register a step (keyword-agnostic).
    public func step(_ pattern: String, handler: @escaping StepHandler) {
        registry.step(pattern, handler: handler)
    }

    // MARK: - Report Collection

    /// Shared result collector for HTML report generation across all GherkinTestCase subclasses.
    nonisolated(unsafe) private static var _resultCollector = ReportResultCollector()
    nonisolated(unsafe) private static var _atexitRegistered = false

    /// The shared result collector. Accessible for programmatic use.
    public static var resultCollector: ReportResultCollector { _resultCollector }

    /// Write the collected report to disk. Called from both `atexit` (for `swift test`)
    /// and `class func tearDown()` (for `xcodebuild` where the process may be killed
    /// before `atexit` handlers fire).
    private static func writeReportIfNeeded() {
        let result = _resultCollector.buildTestRunResult()
        guard !result.featureResults.isEmpty else { return }
        let rawPath = ProcessInfo.processInfo.environment["PICKLE_REPORT_PATH"] ?? "pickle-report.html"
        // Resolve to absolute path so the output location is unambiguous,
        // especially under xcodebuild where the working directory may differ.
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
            // Fall back to the sandbox-writable temp directory (common when
            // running UI tests via xcodebuild, where the runner is sandboxed).
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
            GherkinTestCase.writeReportIfNeeded()
        }
    }

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

    /// Write an incremental report after each test class finishes.
    /// This ensures reports are generated even when the test runner process
    /// is terminated (e.g., by xcodebuild) before `atexit` handlers fire.
    override open class func tearDown() {
        if _atexitRegistered {
            writeReportIfNeeded()
        }
        super.tearDown()
    }

    // MARK: - Dynamic Test Suite

    /// Parsed and expanded scenarios mapped by sanitized method name, keyed per class.
    /// Each GherkinTestCase subclass gets its own scenario map so that multiple
    /// subclasses (or the base class itself) don't overwrite each other's data.
    nonisolated(unsafe) private static var scenarioMaps: [ObjectIdentifier: [String: (scenario: Scenario, background: Background?, feature: Feature)]] = [:]

    override open class var defaultTestSuite: XCTestSuite {
        let classId = ObjectIdentifier(self)

        // Parse features
        let parser = GherkinParser()
        let expander = OutlineExpander()

        let features: [Feature]
        var lineFilters: [String: Set<Int>] = [:]
        do {
            // Priority: env var > class property > bundle
            if let envPaths = FeaturePath.fromEnvironment() {
                let result = try parser.parsePaths(envPaths)
                features = result.features
                lineFilters = result.lineFilters
            } else if let pathSpecs = featurePaths {
                let featurePathValues = pathSpecs.compactMap { FeaturePath.parse($0) }
                let result = try parser.parsePaths(featurePathValues)
                features = result.features
                lineFilters = result.lineFilters
            } else {
                features = try parser.parseBundle(bundle: featureBundle, subdirectory: featureSubdirectory)
            }
        } catch {
            // Create a single failing test to report the parse error
            let errorSuite = XCTestSuite(name: String(describing: self))
            let sel = #selector(reportParseError)
            if let testCase = makeTestCase(for: self, selector: sel) {
                errorSuite.addTest(testCase)
            }
            parseErrors[classId] = error
            return errorSuite
        }

        let envFilter = TagFilter.fromEnvironment()
        let filter: TagFilter?
        switch (tagFilter, envFilter) {
        case let (compileTime?, env?):
            filter = compileTime.merging(env)
        case let (compileTime?, nil):
            filter = compileTime
        case let (nil, env?):
            filter = env
        case (nil, nil):
            filter = nil
        }
        let envNameFilter = ScenarioNameFilter.fromEnvironment()
        let nameFilter: ScenarioNameFilter?
        switch (scenarioNameFilter, envNameFilter) {
        case let (compileTime?, env?):
            nameFilter = compileTime.merging(env)
        case let (compileTime?, nil):
            nameFilter = compileTime
        case let (nil, env?):
            nameFilter = env
        case (nil, nil):
            nameFilter = nil
        }

        scenarioMaps[classId] = [:]

        for feature in features {
            let expanded = expander.expand(feature)

            for definition in expanded.scenarios {
                guard case .scenario(let scenario) = definition else { continue }

                // Apply tag filter
                if let filter = filter {
                    let allTags = feature.tags + scenario.tags
                    if !filter.shouldInclude(tags: allTags) {
                        recordSkippedIfNeeded(scenario: scenario, feature: feature)
                        continue
                    }
                }

                // Apply name filter
                if let nameFilter = nameFilter {
                    if !nameFilter.shouldInclude(name: scenario.name) {
                        recordSkippedIfNeeded(scenario: scenario, feature: feature)
                        continue
                    }
                }

                // Apply line filter
                if let sourceFile = expanded.sourceFile,
                   let allowedLines = lineFilters[sourceFile],
                   !scenarioMatchesLines(scenario, allowedLines: allowedLines, feature: expanded) {
                    continue
                }

                let methodName = sanitizeMethodName(scenario.name)
                let selectorName = "test_\(methodName)"

                scenarioMaps[classId]?[selectorName] = (scenario, expanded.background, feature)

                // Add dynamic test method to the class. class_addMethod is a no-op
                // if the selector already exists, so repeated calls are safe.
                let sel = NSSelectorFromString(selectorName)
                let block: @convention(block) (GherkinTestCase) -> Void = { testCase in
                    testCase.executeScenario(named: selectorName)
                }
                let imp = imp_implementationWithBlock(block)
                // "v@:" means void return, object self, selector _cmd
                class_addMethod(self, sel, imp, "v@:")
            }
        }

        // Create suite AFTER all dynamic methods are added to the class.
        // XCTestSuite(forTestCaseClass:) discovers test_* methods via ObjC
        // reflection, so it will find all dynamically added methods.
        // This avoids duplicate test entries that can crash Xcode's result
        // bundle builder when defaultTestSuite is called multiple times.
        let suite = XCTestSuite(forTestCaseClass: self)
        return suite
    }

    /// Create an XCTestCase instance via the ObjC runtime, bypassing Swift's
    /// unavailability of `init(selector:)`.
    private static func makeTestCase(for cls: AnyClass, selector: Selector) -> XCTestCase? {
        typealias Factory = @convention(c) (AnyClass, Selector, Selector) -> XCTestCase?
        let factorySel = NSSelectorFromString("testCaseWithSelector:")
        guard let method = class_getClassMethod(cls, factorySel) else { return nil }
        let imp = method_getImplementation(method)
        let factory = unsafeBitCast(imp, to: Factory.self)
        return factory(cls, factorySel, selector)
    }

    // MARK: - Error Reporting

    nonisolated(unsafe) private static var parseErrors: [ObjectIdentifier: Error] = [:]

    @objc private func reportParseError() {
        let classId = ObjectIdentifier(type(of: self))
        let error = Self.parseErrors[classId]
        XCTFail("Failed to parse feature files: \(error?.localizedDescription ?? "unknown error")")
    }

    // MARK: - Scenario Execution

    private func executeScenario(named selectorName: String) {
        let classId = ObjectIdentifier(type(of: self))
        guard let entry = Self.scenarioMaps[classId]?[selectorName] else {
            XCTFail("No scenario found for \(selectorName)")
            return
        }

        let (scenario, background, feature) = entry

        // Runtime scenario name filter — catches CUCUMBER_SCENARIOS env var
        // that may not be available during defaultTestSuite construction
        // (e.g., xcodebuild's TEST_RUNNER_ prefix forwarding).
        if let envNameFilter = ScenarioNameFilter.fromEnvironment() {
            let mergedFilter: ScenarioNameFilter
            if let compileTimeFilter = type(of: self).scenarioNameFilter {
                mergedFilter = compileTimeFilter.merging(envNameFilter)
            } else {
                mergedFilter = envNameFilter
            }
            if !mergedFilter.shouldInclude(name: scenario.name) {
                return
            }
        }

        let reportingEnabled = type(of: self).reportEnabled

        if reportingEnabled {
            Self.ensureAtexitRegistered()
        }

        // Register step definitions
        registry.reset()

        // Register steps from type-based providers
        var stepTypes = type(of: self).stepDefinitionTypes
        if let envFilter = StepDefinitionFilter.fromEnvironment() {
            stepTypes = stepTypes.filter { envFilter.contains(String(describing: $0)) }
        }
        for stepType in stepTypes {
            let provider = stepType.init()
            provider.register(in: registry)
        }

        // Then register inline steps (backward compatibility)
        registerStepDefinitions()

        if !registry.registrationErrors.isEmpty {
            for error in registry.registrationErrors {
                XCTFail(error.localizedDescription)
            }
            return
        }

        let runner = ScenarioRunner(registry: registry)
        let collector = Self._resultCollector

        // Use XCTest async support.
        // XCTest runs test methods on the main thread, so we know we're
        // on MainActor. We use nonisolated(unsafe) to bridge the gap between
        // XCTest's sync test methods and Swift 6's strict concurrency.
        nonisolated(unsafe) let testCase = self
        let expectation = testCase.expectation(description: "Scenario: \(scenario.name)")

        Task { @MainActor in
            do {
                // Snapshot XCTest failure count before running the scenario.
                // Step handlers may call XCTAssert* which records failures on the
                // test case but does NOT throw — ScenarioRunner sees the step as passing.
                let failureCountBefore = testCase.testRun?.totalFailureCount ?? 0

                let result = try await runner.run(
                    scenario: scenario,
                    background: background,
                    feature: feature
                )

                // Detect XCTAssert failures that didn't throw
                let failureCountAfter = testCase.testRun?.totalFailureCount ?? 0
                let hasNewXCTestFailures = failureCountAfter > failureCountBefore

                if reportingEnabled {
                    if result.passed && hasNewXCTestFailures {
                        // XCTAssert failed but didn't throw — record as failed in the report
                        let correctedResult = ScenarioResult(
                            scenarioName: result.scenarioName,
                            passed: false,
                            error: ScenarioRunnerError.stepFailed(
                                step: scenario.steps.first ?? Step(keyword: .then, text: "unknown"),
                                feature: feature.name,
                                scenario: scenario.name,
                                underlyingError: XCTestAssertionError(
                                    message: "XCTest recorded \(failureCountAfter - failureCountBefore) assertion failure(s) during scenario execution"
                                )
                            ),
                            stepsExecuted: result.stepsExecuted,
                            tags: result.tags,
                            stepResults: result.stepResults,
                            duration: result.duration
                        )
                        collector.record(
                            scenarioResult: correctedResult,
                            featureName: feature.name,
                            featureDescription: feature.description,
                            featureTags: feature.tags,
                            sourceFile: feature.sourceFile
                        )
                    } else {
                        collector.record(
                            scenarioResult: result,
                            featureName: feature.name,
                            featureDescription: feature.description,
                            featureTags: feature.tags,
                            sourceFile: feature.sourceFile
                        )
                    }
                }

                if !result.passed, let error = result.error {
                    let message = Self.formatError(error, scenario: scenario, feature: feature)
                    XCTFail(message)
                }
            } catch {
                XCTFail("Scenario '\(scenario.name)' threw an unexpected error: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }

        testCase.waitForExpectations(timeout: 60)
    }

    // MARK: - Helpers

    private static func formatError(_ error: Error, scenario: Scenario, feature: Feature) -> String {
        if let runnerError = error as? ScenarioRunnerError {
            switch runnerError {
            case .undefinedStep(let step, _, _):
                return "Undefined step at \(feature.sourceFile ?? "?"):\(step.sourceLine) — "
                    + "\(step.keyword.rawValue) \(step.text)"
            case .stepFailed(let step, _, _, let underlying):
                return "Step failed at \(feature.sourceFile ?? "?"):\(step.sourceLine) — "
                    + "\(step.keyword.rawValue) \(step.text)\n"
                    + "Error: \(underlying.localizedDescription)"
            }
        }
        return "Scenario '\(scenario.name)' failed: \(error.localizedDescription)"
    }

    /// Determines whether a scenario matches any of the allowed line numbers.
    ///
    /// A scenario matches a line if the line falls within its definition range.
    /// The range is from the scenario's `sourceLine` to just before the next
    /// scenario's `sourceLine` (or end of file). This handles exact scenario
    /// lines, step lines within the scenario, and tag lines above it.
    ///
    /// For Scenario Outlines, all expanded scenarios share the original outline's
    /// `sourceLine`, so `file:line` pointing at an outline selects all expanded rows.
    private static func scenarioMatchesLines(
        _ scenario: Scenario,
        allowedLines: Set<Int>,
        feature: Feature
    ) -> Bool {
        // Collect all scenario source lines from the feature, sorted.
        let allSourceLines = feature.scenarios.map(\.sourceLine).sorted()

        for line in allowedLines {
            // Find the scenario whose sourceLine is the largest value <= line
            if let matchedLine = allSourceLines.last(where: { $0 <= line }) {
                if matchedLine == scenario.sourceLine {
                    return true
                }
            }
        }
        return false
    }

    private static func sanitizeMethodName(_ name: String) -> String {
        // Replace non-alphanumeric characters with underscores
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
#endif
