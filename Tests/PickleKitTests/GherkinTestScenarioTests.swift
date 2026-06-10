import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import PickleKit

/// Tests for `GherkinTestScenario` — the Swift Testing bridge that loads Gherkin features
/// and executes them as parameterized test arguments.
///
/// Uses `@Suite(.serialized)` because step definition types use `nonisolated(unsafe)
/// static var` state that is reset per-scenario via `init()`.
///
/// Count-sensitive tests use a private `loadScenarios` helper that bypasses
/// `TagFilter.fromEnvironment()` to avoid cross-suite interference from
/// `TagFilterTests` (which sets `CUCUMBER_TAGS` / `CUCUMBER_EXCLUDE_TAGS` and
/// may run concurrently). The `GherkinTestScenario.scenarios()` API merges env
/// vars into the tag filter, making it unreliable for deterministic assertions
/// when env-var-mutating tests run in parallel.
@Suite(.serialized)
struct GherkinTestScenarioTests {

    // MARK: - Helpers

    /// Load scenarios from a bundle without reading `TagFilter.fromEnvironment()`.
    /// This avoids the race condition with `TagFilterTests` setting env vars.
    private func loadScenarios(
        bundle: Bundle,
        subdirectory: String?,
        tagFilter: TagFilter? = nil
    ) throws -> [GherkinTestScenario] {
        let parser = GherkinParser()
        let features = try parser.parseBundle(bundle: bundle, subdirectory: subdirectory)
        return buildScenarios(from: features, tagFilter: tagFilter)
    }

    /// Load scenarios from filesystem paths without reading `TagFilter.fromEnvironment()`.
    private func loadScenarios(
        paths: [String],
        tagFilter: TagFilter? = nil
    ) throws -> [GherkinTestScenario] {
        let parser = GherkinParser()
        let featurePaths = paths.compactMap { FeaturePath.parse($0) }
        let result = try parser.parsePaths(featurePaths)
        return buildScenarios(from: result.features, tagFilter: tagFilter)
    }

    /// Expand features into scenarios, applying tag filter without env var merge.
    private func buildScenarios(
        from features: [Feature],
        tagFilter: TagFilter?
    ) -> [GherkinTestScenario] {
        let expander = OutlineExpander()
        var results: [GherkinTestScenario] = []
        for feature in features {
            let expanded = expander.expand(feature)
            for definition in expanded.scenarios {
                guard case .scenario(let scenario) = definition else { continue }
                if let filter = tagFilter {
                    let allTags = feature.tags + scenario.tags
                    if !filter.shouldInclude(tags: allTags) { continue }
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

    /// Load a fixture file URL by name.
    private func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(
            forResource: name,
            withExtension: "feature",
            subdirectory: "Fixtures"
        ))
    }

    // MARK: - Loading from Bundle

    @Test func loadingScenariosFromBundle() throws {
        let scenarios = try loadScenarios(bundle: Bundle.module, subdirectory: "Fixtures")
        #expect(scenarios.count == 13)
    }

    @Test func tagFilterExcludesScenarios() throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(excludeTags: ["wip"])
        )
        #expect(scenarios.count == 12)
        let names = scenarios.map(\.scenario.name)
        #expect(!names.contains("Work in progress"))
    }

    @Test func tagFilterIncludesOnlyMatching() throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        #expect(scenarios.count == 1)
        #expect(scenarios[0].scenario.name == "Quick check")
    }

    @Test func invalidBundleSubdirectoryReturnsEmpty() {
        let scenarios = GherkinTestScenario.scenarios(
            bundle: Bundle.module,
            subdirectory: "NonexistentSubdirectory"
        )
        #expect(scenarios.isEmpty)
    }

    // MARK: - Loading from Filesystem Paths

    @Test func loadingFromFilesystemPaths() throws {
        let url = try fixtureURL("basic")
        let scenarios = try loadScenarios(paths: [url.path])
        #expect(scenarios.count == 2)
    }

    @Test func lineSpecificationLoadsFile() throws {
        let url = try fixtureURL("basic")
        // Line filtering is only applied by GherkinTestCase (XCTest bridge).
        // GherkinTestScenario loads the file but does not filter by line.
        let scenarios = try loadScenarios(paths: ["\(url.path):6"])
        #expect(scenarios.count == 2)
    }

    @Test func pathsWithTagFilter() throws {
        let url = try fixtureURL("with_tags")
        let scenarios = try loadScenarios(
            paths: [url.path],
            tagFilter: TagFilter(excludeTags: ["wip"])
        )
        #expect(scenarios.count == 2)
        let names = scenarios.map(\.scenario.name)
        #expect(!names.contains("Work in progress"))
    }

    // MARK: - Execution

    @Test func runReturnsPassingResult() async throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        let test = try #require(scenarios.first)
        #expect(test.scenario.name == "Quick check")

        let result = try await test.run(stepDefinitions: [TaggedSteps.self])
        #expect(result.passed)
        #expect(result.stepsExecuted == 2)
        #expect(result.stepResults.count == 2)
    }

    @Test func runWithUndefinedStepFails() async throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        let test = try #require(scenarios.first)

        // Run with no step definitions — all steps are undefined
        let result = try await test.run(stepDefinitions: [])
        #expect(!result.passed)
        #expect(result.error != nil)
    }

    @Test func reportCollectorRecordsResult() async throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        let test = try #require(scenarios.first)

        let collector = ReportResultCollector()
        try await test.run(stepDefinitions: [TaggedSteps.self], reportCollector: collector)

        let testRun = collector.buildTestRunResult()
        #expect(testRun.featureResults.count == 1)
        #expect(testRun.featureResults[0].featureName == "Tagged scenarios")
        #expect(testRun.featureResults[0].scenarioResults.count == 1)
        #expect(testRun.featureResults[0].scenarioResults[0].scenarioName == "Quick check")
    }

    // MARK: - Error Reporting via Collector

    @Test func thrownErrorFlowsToCollector() async throws {
        // Create a scenario with a step that will fail (no step definitions registered)
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        let test = try #require(scenarios.first)

        // Run with no step definitions — all steps are undefined
        let collector = ReportResultCollector()
        try await test.run(stepDefinitions: [], reportCollector: collector)

        let testRun = collector.buildTestRunResult()
        #expect(testRun.totalScenarioCount == 1)
        #expect(testRun.failedScenarioCount == 1)
        #expect(testRun.passedScenarioCount == 0)

        let scenarioResult = try #require(testRun.featureResults.first?.scenarioResults.first)
        #expect(!scenarioResult.passed)
        #expect(scenarioResult.error != nil)

        // Verify at least one step is undefined
        let undefinedSteps = scenarioResult.stepResults.filter { $0.status == .undefined }
        #expect(!undefinedSteps.isEmpty)
    }

    @Test func thrownStepErrorFlowsToCollector() async throws {
        // Use ArithmeticSteps with a scenario that has a wrong expected result
        let scenario = Scenario(
            name: "Bad arithmetic",
            steps: [
                Step(keyword: .given, text: "I have the number 5", sourceLine: 2),
                Step(keyword: .when, text: "I add 3", sourceLine: 3),
                Step(keyword: .then, text: "the result should be 99", sourceLine: 4),
            ]
        )
        let feature = Feature(name: "Arithmetic", sourceFile: "arithmetic.feature")
        let test = GherkinTestScenario(scenario: scenario, background: nil, feature: feature)

        let collector = ReportResultCollector()
        try await test.run(stepDefinitions: [ArithmeticSteps.self], reportCollector: collector)

        let testRun = collector.buildTestRunResult()
        #expect(testRun.failedScenarioCount == 1)

        let scenarioResult = try #require(testRun.featureResults.first?.scenarioResults.first)
        #expect(!scenarioResult.passed)
        #expect(scenarioResult.stepResults.count == 3)
        #expect(scenarioResult.stepResults[0].status == .passed)
        #expect(scenarioResult.stepResults[1].status == .passed)
        #expect(scenarioResult.stepResults[2].status == .failed)

        // Verify the error message appears in the step result
        let failedStep = try #require(scenarioResult.stepResults.last)
        #expect(failedStep.error != nil)
        // The error comes from StepAssertionError which is wrapped by ScenarioRunnerError.stepFailed.
        // ScenarioRunner records error.localizedDescription, which includes the underlying error.
        #expect(failedStep.error?.isEmpty == false)
    }

    // MARK: - Properties

    @Test func descriptionReturnsScenarioName() throws {
        let scenarios = try loadScenarios(bundle: Bundle.module, subdirectory: "Fixtures")
        for test in scenarios {
            #expect(test.description == test.scenario.name)
        }
    }

    @Test func backgroundIncluded() throws {
        let url = try fixtureURL("with_background")
        let scenarios = try loadScenarios(paths: [url.path])
        #expect(scenarios.count == 2)
        for test in scenarios {
            let bg = try #require(test.background)
            #expect(bg.steps.count == 2)
        }
    }

    @Test func noBackgroundWhenAbsent() throws {
        let url = try fixtureURL("basic")
        let scenarios = try loadScenarios(paths: [url.path])
        for test in scenarios {
            #expect(test.background == nil)
        }
    }

    @Test func featureTagsPreserved() throws {
        let url = try fixtureURL("with_tags")
        let scenarios = try loadScenarios(paths: [url.path])
        for test in scenarios {
            #expect(test.feature.tags.contains("smoke"))
        }
    }

    @Test func outlineExpansionProducesConcrete() throws {
        let url = try fixtureURL("with_outline")
        let scenarios = try loadScenarios(paths: [url.path])
        #expect(scenarios.count == 3)
        for test in scenarios {
            #expect(test.scenario.steps.count == 3)
        }
    }

    // MARK: - Report collection routing (PICKLE_REPORT)
    //
    // These exercise the env→flag mapping and the collector-routing DECISION as
    // pure functions with the config passed in — no process-global env mutation
    // and no assertions on the shared collector's contents. So they're safe
    // under parallel execution AND under an externally-set PICKLE_REPORT (e.g.
    // CI's report-generating run, where the env var is set for the whole
    // process and every bridge run auto-collects into the shared collector).

    @Test func reportEnabledReflectsTheEnvironment() {
        #expect(!GherkinTestScenario.reportEnabled(in: [:]))
        #expect(!GherkinTestScenario.reportEnabled(in: ["SOMETHING_ELSE": "1"]))
        #expect(GherkinTestScenario.reportEnabled(in: ["PICKLE_REPORT": "1"]))
        // Presence, not value — an empty value still enables it.
        #expect(GherkinTestScenario.reportEnabled(in: ["PICKLE_REPORT": ""]))
    }

    @Test func enabledRunWithoutExplicitCollectorRoutesToTheSharedCollector() {
        #expect(GherkinTestScenario.effectiveReportCollector(explicit: nil, reportEnabled: true)
            === GherkinTestScenario.resultCollector)
    }

    @Test func disabledRunWithoutExplicitCollectorRoutesNowhere() {
        #expect(GherkinTestScenario.effectiveReportCollector(explicit: nil, reportEnabled: false) == nil)
    }

    @Test func explicitCollectorTakesPrecedence() {
        let explicit = ReportResultCollector()
        // Wins whether or not reporting is enabled, and is never the shared one.
        #expect(GherkinTestScenario.effectiveReportCollector(explicit: explicit, reportEnabled: true) === explicit)
        #expect(GherkinTestScenario.effectiveReportCollector(explicit: explicit, reportEnabled: false) === explicit)
        #expect(explicit !== GherkinTestScenario.resultCollector)
    }

    @Test func runWithAnExplicitCollectorRecordsIntoIt() async throws {
        let scenarios = try loadScenarios(
            bundle: Bundle.module,
            subdirectory: "Fixtures",
            tagFilter: TagFilter(includeTags: ["fast"])
        )
        let test = try #require(scenarios.first)

        // An explicit (local) collector — no env, no shared global, so this is
        // robust under parallelism and a globally-set PICKLE_REPORT.
        let collector = ReportResultCollector()
        try await test.run(stepDefinitions: [TaggedSteps.self], reportCollector: collector)

        let run = collector.buildTestRunResult()
        #expect(run.featureResults.count == 1)
        #expect(run.featureResults.first?.scenarioResults.first?.scenarioName == "Quick check")
    }

    @Test func reportOutputPathReadsEnvironment() {
        unsetenv("PICKLE_REPORT_PATH")
        defer { unsetenv("PICKLE_REPORT_PATH") }

        #expect(GherkinTestScenario.reportOutputPath == "pickle-report.html")

        setenv("PICKLE_REPORT_PATH", "custom/report.html", 1)
        #expect(GherkinTestScenario.reportOutputPath == "custom/report.html")
    }
}
