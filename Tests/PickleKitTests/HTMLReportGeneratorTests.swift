import Testing
import Foundation
@testable import PickleKit

@Suite struct HTMLReportGeneratorTests {

    private let generator: HTMLReportGenerator

    init() {
        generator = HTMLReportGenerator()
    }

    // MARK: - Helpers

    private func makeSampleResult() -> TestRunResult {
        let passingSteps = [
            StepResult(keyword: "Given", text: "a setup", status: .passed, duration: 0.001, sourceLine: 1),
            StepResult(keyword: "When", text: "an action", status: .passed, duration: 0.002, sourceLine: 2),
            StepResult(keyword: "Then", text: "a result", status: .passed, duration: 0.001, sourceLine: 3),
        ]

        let failingSteps = [
            StepResult(keyword: "Given", text: "a precondition", status: .passed, duration: 0.001, sourceLine: 5),
            StepResult(keyword: "When", text: "something breaks", status: .failed, duration: 0.003, error: "Expected 5 but got 3", sourceLine: 6),
            StepResult(keyword: "Then", text: "never reached", status: .skipped, sourceLine: 7),
        ]

        let passingScenario = ScenarioResult(
            scenarioName: "Happy Path",
            passed: true,
            stepsExecuted: 3,
            tags: ["smoke"],
            stepResults: passingSteps,
            duration: 0.004
        )

        let failingScenario = ScenarioResult(
            scenarioName: "Error Case",
            passed: false,
            error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test failed"]),
            stepsExecuted: 1,
            tags: ["regression"],
            stepResults: failingSteps,
            duration: 0.004
        )

        let feature = FeatureResult(
            featureName: "User Login",
            scenarioResults: [passingScenario, failingScenario],
            tags: ["auth"],
            sourceFile: "login.feature",
            duration: 0.008
        )

        return TestRunResult(
            featureResults: [feature],
            startTime: Date(timeIntervalSince1970: 1000000),
            endTime: Date(timeIntervalSince1970: 1000001)
        )
    }

    // MARK: - HTML Structure

    @Test func generatesValidHTMLStructure() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<html lang=\"en\">"))
        #expect(html.contains("</html>"))
        #expect(html.contains("<head>"))
        #expect(html.contains("</head>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("</body>"))
    }

    @Test func containsInlineCSS() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("<style>"))
        #expect(html.contains("</style>"))
    }

    @Test func containsInlineJS() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("<script>"))
        #expect(html.contains("expandAll"))
        #expect(html.contains("collapseAll"))
        #expect(html.contains("filterStatus"))
    }

    // MARK: - Feature and Scenario Content

    @Test func containsFeatureName() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("User Login"))
    }

    @Test func containsScenarioNames() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("Happy Path"))
        #expect(html.contains("Error Case"))
    }

    @Test func containsStepText() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("a setup"))
        #expect(html.contains("an action"))
        #expect(html.contains("something breaks"))
    }

    @Test func containsErrorMessages() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("Expected 5 but got 3"))
    }

    // MARK: - Summary Counts

    @Test func summaryShowsFeatureCount() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("Features"))
        #expect(html.contains("Scenarios"))
        #expect(html.contains("Steps"))
    }

    @Test func summaryShowsCorrectScenarioCounts() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("1 passed, 1 failed"))
    }

    // MARK: - CSS Classes for Statuses

    @Test func containsStatusCSSClasses() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("status-passed"))
        #expect(html.contains("status-failed"))
        #expect(html.contains("class=\"step-row passed\""))
        #expect(html.contains("class=\"step-row failed\""))
        #expect(html.contains("class=\"step-row skipped\""))
    }

    @Test func failedScenarioRowHighlightCSS() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("scenario[data-status=\"failed\"] summary { background:"))
    }

    @Test func failedScenarioIsOpenByDefault() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("data-status=\"failed\" open"))
    }

    @Test func passingScenarioIsClosedByDefault() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("data-status=\"passed\">"))
    }

    // MARK: - Tags

    @Test func containsFeatureTags() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("@auth"))
    }

    @Test func containsScenarioTags() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("@smoke"))
        #expect(html.contains("@regression"))
    }

    // MARK: - HTML Escaping

    @Test func htmlEscapesSpecialCharacters() {
        let feature = FeatureResult(
            featureName: "Test <script>alert('xss')</script>",
            scenarioResults: [
                ScenarioResult(
                    scenarioName: "Scenario with \"quotes\" & <brackets>",
                    passed: true,
                    stepsExecuted: 1,
                    stepResults: [
                        StepResult(keyword: "Given", text: "a step with <html> & \"entities\"", status: .passed, duration: 0.001, sourceLine: 1)
                    ],
                    duration: 0.001
                )
            ]
        )

        let result = TestRunResult(
            featureResults: [feature],
            startTime: Date(),
            endTime: Date()
        )

        let html = generator.generate(from: result)

        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&amp;"))
        // Quotes in TEXT content are left literal (only attribute values escape
        // them) — the HTML-correct rule, now that Kumi does the escaping.
        #expect(html.contains("\"quotes\""))
        #expect(!html.contains("<script>alert"))
    }

    // MARK: - Write to File

    @Test func writeReportToFile() throws {
        let result = makeSampleResult()
        let tempDir = NSTemporaryDirectory()
        let path = (tempDir as NSString).appendingPathComponent("pickle-test-report-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try generator.write(result: result, to: path)

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("<!DOCTYPE html>"))
        #expect(contents.contains("User Login"))
    }

    @Test func writeCreatesIntermediateDirectories() throws {
        let result = makeSampleResult()
        let tempDir = NSTemporaryDirectory()
        let nestedDir = (tempDir as NSString).appendingPathComponent("pickle-test-\(UUID().uuidString)/build")
        let path = (nestedDir as NSString).appendingPathComponent("report.html")
        defer { try? FileManager.default.removeItem(atPath: (nestedDir as NSString).deletingLastPathComponent) }

        #expect(!FileManager.default.fileExists(atPath: nestedDir))

        try generator.write(result: result, to: path)

        #expect(FileManager.default.fileExists(atPath: path))
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("<!DOCTYPE html>"))
    }

    @Test func writeToDeeplyNestedPath() throws {
        let result = makeSampleResult()
        let tempDir = NSTemporaryDirectory()
        let uuid = UUID().uuidString
        let path = (tempDir as NSString).appendingPathComponent("pickle-\(uuid)/a/b/c/report.html")
        defer { try? FileManager.default.removeItem(atPath: (tempDir as NSString).appendingPathComponent("pickle-\(uuid)")) }

        try generator.write(result: result, to: path)

        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Empty Result

    @Test func emptyResultGeneratesValidHTML() {
        let result = TestRunResult(featureResults: [], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("</html>"))
        #expect(html.contains("Features"))
    }

    // MARK: - Skipped Scenario Status

    @Test func skippedScenarioRendersWithSkippedStatus() {
        let feature = FeatureResult(
            featureName: "Filtered Feature",
            scenarioResults: [
                ScenarioResult(
                    scenarioName: "Included Scenario",
                    passed: true,
                    stepsExecuted: 1,
                    stepResults: [
                        StepResult(keyword: "Given", text: "a step", status: .passed, duration: 0.001, sourceLine: 1)
                    ],
                    duration: 0.001
                ),
                ScenarioResult(
                    scenarioName: "Skipped Scenario",
                    passed: true,
                    skipped: true,
                    tags: ["wip"]
                ),
            ]
        )

        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        #expect(html.contains("data-status=\"skipped\""))
        #expect(html.contains("status-badge status-skipped"))
        #expect(html.contains("Skipped Scenario"))
    }

    @Test func skippedFilterButtonPresent() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)

        #expect(html.contains("filterStatus('skipped')"))
        #expect(html.contains("data-filter=\"skipped\""))
    }

    @Test func skippedScenarioSummaryBreakdown() {
        let feature = FeatureResult(
            featureName: "Mixed Feature",
            scenarioResults: [
                ScenarioResult(scenarioName: "Passing", passed: true, stepsExecuted: 1),
                ScenarioResult(scenarioName: "Skipped", passed: true, skipped: true),
            ]
        )

        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        #expect(html.contains("1 passed, 0 failed, 1 skipped"))
    }

    @Test func allSkippedFeatureGetsSkippedDataStatus() {
        let feature = FeatureResult(
            featureName: "All Skipped Feature",
            scenarioResults: [
                ScenarioResult(scenarioName: "S1", passed: true, skipped: true),
                ScenarioResult(scenarioName: "S2", passed: true, skipped: true),
            ]
        )

        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        #expect(html.contains("data-status=\"skipped\""))
    }

    @Test func featureStatsShowSkippedCount() {
        let feature = FeatureResult(
            featureName: "Partial Feature",
            scenarioResults: [
                ScenarioResult(scenarioName: "Passing", passed: true, stepsExecuted: 1),
                ScenarioResult(scenarioName: "Skipped", passed: true, skipped: true),
            ]
        )

        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        // Feature stats should show "1/1 scenarios passed, 1 skipped"
        #expect(html.contains("1/1 scenarios passed"))
        #expect(html.contains("1 skipped"))
    }

    // MARK: - Collapsible features, outline sidebar, theming

    @Test func featureIsCollapsibleDetails() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)
        // The feature is its own <details> (open by default) with the header
        // as its <summary> — independently collapsible from its scenarios.
        #expect(html.contains("<details class=\"feature\""))
        #expect(html.contains("<summary class=\"feature-header\">"))
        #expect(html.contains("id=\"feature-0\""))
    }

    @Test func hasPersistentOutlineRail() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)
        // A persistent sticky rail (the SAME component as the spec) in a
        // two-column layout — not the old overlay drawer.
        #expect(html.contains("class=\"rail\""))
        #expect(html.contains("class=\"page-layout\""))
        #expect(html.contains("href=\"#feature-0\" data-target=\"feature-0\""))
        #expect(html.contains("<span class=\"dot failed\">")) // sample feature failed
        #expect(html.contains("jumpTo"))
        // The drawer machinery is gone.
        #expect(!html.contains("outline-toggle"))
        #expect(!html.contains("toggleOutline"))
    }

    @Test func isThemeableMatchingTheSite() {
        let result = makeSampleResult()
        let html = generator.generate(from: result)
        // Light = Solarized, dark = Dracula, switched via data-theme — the
        // same palette and mechanism as the landing page.
        #expect(html.contains(":root[data-theme=\"dark\"]"))
        #expect(html.contains("#fdf6e3")) // Solarized base3 (light bg)
        #expect(html.contains("#282a36")) // Dracula bg
        #expect(html.contains("--accent"))
        // A theme toggle and a pre-paint script that honors the system + a
        // remembered choice.
        #expect(html.contains("cycleTheme()"))
        #expect(html.contains("localStorage.getItem('pickle-theme')"))
        #expect(html.contains("prefers-color-scheme: dark"))
    }

    @Test func shipsExtraNamedThemesReachableByQueryParam() {
        let html = generator.generate(from: makeSampleResult())
        // Beyond the light/dark pair, two more palettes ship so a generated
        // report can demonstrate that re-skinning is one CSS block.
        #expect(html.contains(":root[data-theme=\"nord\"]"))
        #expect(html.contains(":root[data-theme=\"gruvbox\"]"))
        #expect(html.contains("#2e3440")) // Nord polar-night base
        #expect(html.contains("#fe8019")) // Gruvbox orange accent
        // Every built-in theme emits a block, and the showcase deep-links via
        // ?theme=<id>, which the pre-paint script honors over the OS default.
        for theme in ReportShared.themes {
            #expect(html.contains("data-theme=\"\(theme.id)\""))
        }
        #expect(html.contains("URLSearchParams(location.search).get('theme')"))
    }

    @Test func scenarioAndFeatureAnchorsAreUnique() {
        // Two features, two scenarios each → distinct, stable anchor ids.
        let feature1 = FeatureResult(featureName: "F1", scenarioResults: [
            ScenarioResult(scenarioName: "A", passed: true, stepsExecuted: 1),
            ScenarioResult(scenarioName: "B", passed: true, stepsExecuted: 1),
        ])
        let feature2 = FeatureResult(featureName: "F2", scenarioResults: [
            ScenarioResult(scenarioName: "C", passed: true, stepsExecuted: 1),
        ])
        let result = TestRunResult(featureResults: [feature1, feature2],
                                   startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)
        #expect(html.contains("id=\"feature-0\""))
        #expect(html.contains("id=\"feature-1\""))
        #expect(html.contains("id=\"scenario-0-1\""))
        #expect(html.contains("id=\"scenario-1-0\""))
    }

    // MARK: - Undefined Step Status

    @Test func undefinedStepCSSClass() {
        let feature = FeatureResult(
            featureName: "Undefined Feature",
            scenarioResults: [
                ScenarioResult(
                    scenarioName: "Undefined Scenario",
                    passed: false,
                    stepsExecuted: 0,
                    stepResults: [
                        StepResult(keyword: "Given", text: "undefined step", status: .undefined, error: "No matching step definition", sourceLine: 1)
                    ],
                    duration: 0.001
                )
            ]
        )

        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = generator.generate(from: result)

        #expect(html.contains("class=\"step-row undefined\""))
    }

    // MARK: - Report Result Collector

    @Test func collectorGroupsByFeature() {
        let collector = ReportResultCollector()

        let scenario1 = ScenarioResult(scenarioName: "S1", passed: true, stepsExecuted: 1)
        let scenario2 = ScenarioResult(scenarioName: "S2", passed: true, stepsExecuted: 1)
        let scenario3 = ScenarioResult(scenarioName: "S3", passed: false, stepsExecuted: 0)

        collector.record(scenarioResult: scenario1, featureName: "Feature A", featureTags: ["tag1"])
        collector.record(scenarioResult: scenario2, featureName: "Feature A", featureTags: ["tag1"])
        collector.record(scenarioResult: scenario3, featureName: "Feature B", featureTags: ["tag2"])

        let result = collector.buildTestRunResult()

        #expect(result.featureResults.count == 2)
        #expect(result.featureResults[0].featureName == "Feature A")
        #expect(result.featureResults[0].scenarioResults.count == 2)
        #expect(result.featureResults[1].featureName == "Feature B")
        #expect(result.featureResults[1].scenarioResults.count == 1)
    }

    @Test func collectorPreservesFeatureOrder() {
        let collector = ReportResultCollector()

        collector.record(scenarioResult: ScenarioResult(scenarioName: "S1", passed: true), featureName: "Zebra")
        collector.record(scenarioResult: ScenarioResult(scenarioName: "S2", passed: true), featureName: "Alpha")
        collector.record(scenarioResult: ScenarioResult(scenarioName: "S3", passed: true), featureName: "Zebra")

        let result = collector.buildTestRunResult()

        #expect(result.featureResults.count == 2)
        #expect(result.featureResults[0].featureName == "Zebra")
        #expect(result.featureResults[1].featureName == "Alpha")
    }

    @Test func collectorReset() {
        let collector = ReportResultCollector()

        collector.record(scenarioResult: ScenarioResult(scenarioName: "S1", passed: true), featureName: "F1")
        collector.reset()

        let result = collector.buildTestRunResult()
        #expect(result.featureResults.count == 0)
    }

    // MARK: - TestRunResult Aggregations

    @Test func testRunResultAggregations() {
        let feature1 = FeatureResult(
            featureName: "F1",
            scenarioResults: [
                ScenarioResult(scenarioName: "S1", passed: true, stepsExecuted: 2,
                    stepResults: [
                        StepResult(keyword: "Given", text: "a", status: .passed, sourceLine: 1),
                        StepResult(keyword: "Then", text: "b", status: .passed, sourceLine: 2),
                    ]),
                ScenarioResult(scenarioName: "S2", passed: false, stepsExecuted: 1,
                    stepResults: [
                        StepResult(keyword: "Given", text: "c", status: .passed, sourceLine: 3),
                        StepResult(keyword: "When", text: "d", status: .failed, error: "err", sourceLine: 4),
                        StepResult(keyword: "Then", text: "e", status: .skipped, sourceLine: 5),
                    ]),
            ]
        )

        let feature2 = FeatureResult(
            featureName: "F2",
            scenarioResults: [
                ScenarioResult(scenarioName: "S3", passed: true, stepsExecuted: 1,
                    stepResults: [
                        StepResult(keyword: "Given", text: "f", status: .passed, sourceLine: 1),
                    ]),
            ]
        )

        let result = TestRunResult(
            featureResults: [feature1, feature2],
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 105)
        )

        #expect(result.totalFeatureCount == 2)
        #expect(result.passedFeatureCount == 1)
        #expect(result.failedFeatureCount == 1)

        #expect(result.totalScenarioCount == 3)
        #expect(result.passedScenarioCount == 2)
        #expect(result.failedScenarioCount == 1)
        #expect(result.skippedScenarioCount == 0)

        #expect(result.totalStepCount == 6)
        #expect(result.passedStepCount == 4)
        #expect(result.failedStepCount == 1)
        #expect(result.skippedStepCount == 1)

        #expect(abs(result.duration - 5.0) < 0.001)
    }

    @Test func testRunResultSkippedScenarioAggregation() {
        let feature = FeatureResult(
            featureName: "F1",
            scenarioResults: [
                ScenarioResult(scenarioName: "S1", passed: true, stepsExecuted: 1),
                ScenarioResult(scenarioName: "S2", passed: true, skipped: true),
                ScenarioResult(scenarioName: "S3", passed: false, stepsExecuted: 0),
            ]
        )

        let result = TestRunResult(
            featureResults: [feature],
            startTime: Date(),
            endTime: Date()
        )

        #expect(result.totalScenarioCount == 3)
        #expect(result.passedScenarioCount == 1)
        #expect(result.failedScenarioCount == 1)
        #expect(result.skippedScenarioCount == 1)
    }

    // MARK: - Scenario Outline grouping

    @Test func groupsScenarioOutlineExamplesPreservingAnchors() {
        func example(_ label: String, _ idx: Int) -> ScenarioResult {
            ScenarioResult(
                scenarioName: "Precedence [\(label)]", passed: true, stepsExecuted: 1,
                stepResults: [StepResult(keyword: "Then", text: "ok", status: .passed, sourceLine: 1)],
                duration: 0.001, outlineName: "Precedence", exampleLabel: label)
        }
        let feature = FeatureResult(
            featureName: "Math",
            scenarioResults: [
                example("2 + 3 * 4, 14", 0),
                example("2^3^2, 512", 1),
                ScenarioResult(scenarioName: "Modulo is exact", passed: true, stepsExecuted: 1,
                    stepResults: [StepResult(keyword: "Then", text: "ok", status: .passed, sourceLine: 1)]),
            ],
            sourceFile: "math.feature")
        let result = TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date())
        let html = HTMLReportGenerator().generate(from: result)

        // One group, with the outline name and example count.
        #expect(html.components(separatedBy: "class=\"outline-group\"").count - 1 == 1)
        #expect(html.contains("class=\"outline-name\">Precedence</span>"))
        #expect(html.contains("outline \u{00B7} 2"))
        // Per-scenario anchors are unchanged — deep links still resolve.
        #expect(html.contains("id=\"scenario-0-0\""))
        #expect(html.contains("id=\"scenario-0-1\""))
        #expect(html.contains("id=\"scenario-0-2\"")) // the ungrouped one
        // Filter/expand JS knows about groups.
        #expect(html.contains("details.feature, details.outline-group"))
        // An all-passing group is collapsed by default (no ` open`).
        #expect(html.contains("class=\"outline-group\" data-status=\"passed\">"))
    }

    @Test func failingOutlineGroupStaysOpen() {
        func example(_ label: String, _ pass: Bool) -> ScenarioResult {
            ScenarioResult(
                scenarioName: "Precedence [\(label)]", passed: pass, stepsExecuted: 1,
                stepResults: [StepResult(keyword: "Then", text: "ok",
                                         status: pass ? .passed : .failed, sourceLine: 1)],
                duration: 0.001, outlineName: "Precedence", exampleLabel: label)
        }
        let feature = FeatureResult(
            featureName: "Math",
            scenarioResults: [example("ok row", true), example("bad row", false)],
            sourceFile: "math.feature")
        let html = HTMLReportGenerator().generate(
            from: TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date()))
        // A group containing a failure opens so the failing example shows.
        #expect(html.contains("class=\"outline-group\" data-status=\"failed\" open>"))
    }
}
