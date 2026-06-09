import Testing
import Foundation
@testable import PickleKit

@Suite struct SpecPageGeneratorTests {

    private func makeResult(allGreen: Bool = true) -> TestRunResult {
        let steps = [
            StepResult(keyword: "Given", text: "a Person type", status: .passed, duration: 0.001, sourceLine: 1),
            StepResult(keyword: "When", text: "I construct one", status: .passed, duration: 0.001, sourceLine: 2),
            StepResult(keyword: "Then", text: "it has the fields", status: .passed, duration: 0.001, sourceLine: 3),
        ]
        let passing = ScenarioResult(
            scenarioName: "Records you declare and construct",
            passed: true, stepsExecuted: 3, tags: ["data"], stepResults: steps, duration: 0.003)
        var scenarios = [passing]
        if !allGreen {
            scenarios.append(ScenarioResult(
                scenarioName: "A broken promise", passed: false, stepsExecuted: 1,
                stepResults: [StepResult(keyword: "Then", text: "it fails", status: .failed, error: "nope", sourceLine: 4)],
                duration: 0.001))
        }
        let feature = FeatureResult(
            featureName: "Data types",
            description: "As a modeler\nI want records\nSo that data reads like what I mean",
            scenarioResults: scenarios,
            tags: ["datatypes"], sourceFile: "datatypes.feature", duration: 0.004)
        return TestRunResult(featureResults: [feature],
                             startTime: Date(timeIntervalSince1970: 1_000_000),
                             endTime: Date(timeIntervalSince1970: 1_000_001))
    }

    @Test func rendersValidThemeableHTML() {
        let html = SpecPageGenerator().generate(from: makeResult())
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("</html>"))
        // Same theming mechanism as the report.
        #expect(html.contains(":root[data-theme=\"dark\"]"))
        #expect(html.contains("#fdf6e3") && html.contains("#282a36"))
        #expect(html.contains("cycleTheme()"))
        #expect(html.contains("localStorage.getItem('pickle-theme')"))
    }

    @Test func rendersNarrativeAndStepsAsProse() {
        let html = SpecPageGenerator().generate(from: makeResult())
        // Feature name, its narrative, scenario name, and the steps as prose.
        #expect(html.contains("Data types"))
        #expect(html.contains("So that data reads like what I mean"))
        #expect(html.contains("Records you declare and construct"))
        #expect(html.contains("a Person type"))
        #expect(html.contains("class=\"kw\">Given</span>"))
    }

    @Test func showsVerifiedMarkersWhenAllGreen() {
        let html = SpecPageGenerator().generate(from: makeResult())
        #expect(html.contains("every one verified"))
        #expect(html.contains("verified ok"))
        #expect(html.contains("\u{2713}")) // check mark
    }

    @Test func showsFailureWhenNotGreen() {
        let html = SpecPageGenerator().generate(from: makeResult(allGreen: false))
        #expect(html.contains("failing"))
        #expect(html.contains("verified bad"))
    }

    @Test func standaloneByDefaultNoReportLinks() {
        // The spec is a first-class standalone document: with no reportLink
        // (the default), it carries no drill-down links.
        let html = SpecPageGenerator().generate(from: makeResult())
        #expect(!html.contains("#scenario-0-0"))
        #expect(!html.contains("View the full test report"))
    }

    @Test func deepLinksWhenReportLinkProvided() {
        // Given a report link, per-scenario "run" links and the header link
        // use it with the same anchor scheme HTMLReportGenerator emits.
        let html = SpecPageGenerator(reportLink: "pickle-report.html").generate(from: makeResult())
        #expect(html.contains("href=\"pickle-report.html#scenario-0-0\""))
        #expect(html.contains("View the full test report"))

        let custom = SpecPageGenerator(reportLink: "report.html").generate(from: makeResult())
        #expect(custom.contains("href=\"report.html#scenario-0-0\""))
    }

    @Test func titleIsConfigurable() {
        let html = SpecPageGenerator(title: "Anzan — Living Specification").generate(from: makeResult())
        #expect(html.contains("<title>Anzan &mdash; Living Specification</title>")
            || html.contains("Anzan \u{2014} Living Specification"))
    }

    @Test func escapesHTMLInContent() {
        let feature = FeatureResult(
            featureName: "Edge <cases>",
            description: "needs \"quotes\" & <brackets>",
            scenarioResults: [ScenarioResult(
                scenarioName: "Handles <script>", passed: true, stepsExecuted: 1,
                stepResults: [StepResult(keyword: "Given", text: "a & b < c", status: .passed, sourceLine: 1)],
                duration: 0.001)])
        let html = SpecPageGenerator().generate(
            from: TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date()))
        #expect(html.contains("&lt;cases&gt;"))
        #expect(html.contains("&amp;"))
        #expect(html.contains("Handles &lt;script&gt;")) // the scenario name is escaped
    }

    @Test func hasFeatureOutlineRail() {
        // Two features → a sticky TOC rail with a jump link per feature and
        // matching section ids, plus scroll-spy wiring.
        let f1 = FeatureResult(featureName: "Alpha", scenarioResults: [
            ScenarioResult(scenarioName: "a", passed: true, stepsExecuted: 1)])
        let f2 = FeatureResult(featureName: "Beta", scenarioResults: [
            ScenarioResult(scenarioName: "b", passed: true, stepsExecuted: 1)])
        let html = SpecPageGenerator().generate(
            from: TestRunResult(featureResults: [f1, f2], startTime: Date(), endTime: Date()))
        // Shared persistent rail (same component as the report).
        #expect(html.contains("<nav class=\"rail\""))
        #expect(html.contains("href=\"#feature-0\" data-target=\"feature-0\""))
        #expect(html.contains("href=\"#feature-1\" data-target=\"feature-1\""))
        #expect(html.contains("<section class=\"spec-feature\" id=\"feature-0\">"))
        #expect(html.contains("IntersectionObserver"))
    }

    @Test func writesToFile() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("pickle-spec-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try SpecPageGenerator().write(result: makeResult(), to: path)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("Data types"))
    }

    // The narrative survives the collector → TestRunResult path.
    @Test func collectorPreservesFeatureDescription() {
        let collector = ReportResultCollector()
        collector.record(
            scenarioResult: ScenarioResult(scenarioName: "S1", passed: true, stepsExecuted: 1),
            featureName: "F1", featureDescription: "As a user\nI want X")
        let result = collector.buildTestRunResult()
        #expect(result.featureResults[0].description == "As a user\nI want X")
    }

    // Consecutive examples from one Scenario Outline collapse under a single
    // header (name + count); a standalone scenario stays ungrouped.
    @Test func groupsScenarioOutlineExamples() {
        func example(_ label: String) -> ScenarioResult {
            ScenarioResult(
                scenarioName: "Precedence [\(label)]", passed: true, stepsExecuted: 1,
                stepResults: [StepResult(keyword: "Then", text: "ok", status: .passed, sourceLine: 1)],
                duration: 0.001, outlineName: "Precedence", exampleLabel: label)
        }
        let plain = ScenarioResult(
            scenarioName: "Modulo is exact", passed: true, stepsExecuted: 1,
            stepResults: [StepResult(keyword: "Then", text: "ok", status: .passed, sourceLine: 1)],
            duration: 0.001)
        let feature = FeatureResult(
            featureName: "Math",
            scenarioResults: [example("2 + 3 * 4, 14"), example("2^3^2, 512"), plain],
            sourceFile: "math.feature", duration: 0.003)
        let html = SpecPageGenerator().generate(
            from: TestRunResult(featureResults: [feature], startTime: Date(), endTime: Date()))

        // One outline group, with the outline name and the example count.
        #expect(html.components(separatedBy: "class=\"outline-group\"").count - 1 == 1)
        #expect(html.contains("class=\"outline-name\">Precedence</span>"))
        #expect(html.contains("outline \u{00B7} 2"))
        // Each example shows by its label, inside the group's case list.
        #expect(html.contains("2 + 3 * 4, 14"))
        #expect(html.contains("class=\"outline-cases\""))
        // The plain scenario renders, ungrouped.
        #expect(html.contains("Modulo is exact"))
    }
}
