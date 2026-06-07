import Testing
import Foundation
@testable import PickleKit

@Suite struct ReportSuiteTests {

    private func makeResult() -> TestRunResult {
        let feature = FeatureResult(
            featureName: "Login",
            description: "As a user\nI want to sign in\nSo that I reach my account",
            scenarioResults: [
                ScenarioResult(scenarioName: "Happy path", passed: true, stepsExecuted: 2,
                    stepResults: [
                        StepResult(keyword: "Given", text: "an account", status: .passed, sourceLine: 1),
                        StepResult(keyword: "Then", text: "I'm in", status: .passed, sourceLine: 2),
                    ], duration: 0.002),
            ], tags: ["auth"], duration: 0.002)
        return TestRunResult(featureResults: [feature],
                             startTime: Date(timeIntervalSince1970: 1_000_000),
                             endTime: Date(timeIntervalSince1970: 1_000_001))
    }

    @Test func generatesBothPages() {
        let pages = ReportSuite().generate(from: makeResult())
        #expect(pages.report.contains("PickleKit Test Report"))
        #expect(pages.spec.contains("Login"))
        #expect(pages.report.contains("<!DOCTYPE html>"))
        #expect(pages.spec.contains("<!DOCTYPE html>"))
    }

    @Test func pagesCrossLinkEachOther() {
        let pages = ReportSuite().generate(
            from: makeResult(), reportFileName: "report.html", specFileName: "spec.html")
        // Spec → report (drill into results); report → spec (zoom to intent).
        #expect(pages.spec.contains("href=\"report.html#scenario-0-0\""))
        #expect(pages.spec.contains("View the full test report"))
        #expect(pages.report.contains("href=\"spec.html\""))
        #expect(pages.report.contains("Read it as a specification"))
    }

    @Test func bothShareTheSameCountsButNotTestDetail() {
        let pages = ReportSuite().generate(from: makeResult())
        // The report carries the full audit summary (pass/fail breakdowns).
        #expect(pages.report.contains("<h3>Features</h3>"))
        #expect(pages.report.contains("<h3>Scenarios</h3>"))
        #expect(pages.report.contains("1 passed, 0 failed"))
        // The spec shares the COUNTS (the scale of the spec) without the
        // test-result chrome — no summary cards, progress bars, or pass/fail
        // breakdowns render on it.
        #expect(pages.spec.contains("1 features · 1 behaviors · 2 steps"))
        #expect(!pages.spec.contains("<div class=\"summary\">"))
        #expect(!pages.spec.contains("class=\"progress-bar\""))
        #expect(!pages.spec.contains("passed, 0 failed"))
    }

    @Test func bothShareTheSameAnchorScheme() {
        let pages = ReportSuite().generate(
            from: makeResult(), reportFileName: "report.html", specFileName: "spec.html")
        // The report's scenario id and the spec's deep link must agree.
        #expect(pages.report.contains("id=\"scenario-0-0\""))
        #expect(pages.spec.contains("#scenario-0-0"))
    }

    @Test func sidebarIsPersistentButCollapsible() {
        let pages = ReportSuite().generate(from: makeResult())
        // Both pages: a sidebar toggle, the collapse machinery, and remembered
        // state — persistent by default, collapsible on demand.
        for page in [pages.report, pages.spec] {
            #expect(page.contains("onclick=\"toggleRail()\""))
            #expect(page.contains("function toggleRail()"))
            #expect(page.contains("localStorage.setItem('pickle-rail'"))
            #expect(page.contains("html[data-rail=\"collapsed\"] .rail { display: none; }"))
            // Default render is NOT collapsed (persistent by default).
            #expect(!page.contains("data-rail=\"collapsed\">"))
        }
    }

    @Test func specTitleFlowsThrough() {
        let pages = ReportSuite(specTitle: "Anzan — Living Spec").generate(from: makeResult())
        #expect(pages.spec.contains("Anzan \u{2014} Living Spec"))
    }

    @Test func writesBothFilesCrossLinkedByBasename() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("pickle-suite-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let reportPath = (dir as NSString).appendingPathComponent("pickle-report.html")
        let specPath = (dir as NSString).appendingPathComponent("pickle-spec.html")

        try ReportSuite().write(result: makeResult(), reportPath: reportPath, specPath: specPath)

        let report = try String(contentsOfFile: reportPath, encoding: .utf8)
        let spec = try String(contentsOfFile: specPath, encoding: .utf8)
        #expect(report.contains("href=\"pickle-spec.html\""))
        #expect(spec.contains("href=\"pickle-report.html#scenario-0-0\""))
    }

    @Test func defaultSpecPathDerivesFromReport() {
        #expect(ReportSuite.defaultSpecPath(forReport: "/x/pickle-report.html") == "/x/pickle-spec.html")
        #expect(ReportSuite.defaultSpecPath(forReport: "/x/out.html") == "/x/spec-out.html")
        #expect(ReportSuite.defaultSpecPath(forReport: "/x/r.html", override: "/y/s.html") == "/y/s.html")
    }
}
