import Foundation

/// Renders a test run as a **living specification** — the companion to the
/// report. Where the report is a pass/fail dashboard for auditing, the spec
/// page reads as documentation: the shared summary, then each feature's
/// narrative and its scenarios as Given/When/Then prose, marked verified,
/// with a sticky outline rail.
///
/// It shares chrome (palette, summary, anchors, theme) with the report via
/// `ReportShared`, so a `ReportSuite` emits a cohesive pair. `reportLink` is
/// the optional drill-down into the full report (nil = a standalone spec —
/// the spec is a first-class document on its own); the suite wires it.
public struct SpecPageGenerator: Sendable {

    public let title: String
    public let reportLink: String?

    public init(title: String = "Living Specification", reportLink: String? = nil) {
        self.title = title
        self.reportLink = reportLink
    }

    /// Generate the complete living-specification HTML.
    public func generate(from result: TestRunResult) -> String {
        var html = ""
        html += "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        html += "<meta charset=\"UTF-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        html += "<title>\(ReportShared.esc(title))</title>\n"
        html += ReportShared.themePrePaintScript()
        html += generateCSS()
        html += "</head>\n<body>\n"
        html += generateHeader(from: result)
        html += "<div class=\"page-layout\">\n"
        html += ReportShared.railHTML(from: result)
        html += "<div class=\"page-body\">\n"
        html += generateFeatures(from: result)
        html += "</div>\n</div>\n"
        html += generateJS()
        html += "</body>\n</html>"
        return html
    }

    /// Write the living-specification HTML to a path, creating directories.
    public func write(result: TestRunResult, to path: String) throws {
        let html = generate(from: result)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Generators

    private func generateHeader(from result: TestRunResult) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let total = result.totalScenarioCount
        let allGreen = result.failedScenarioCount == 0

        var html = "<header class=\"page-header\">\n"
        html += "  <div class=\"page-header-row\">\n"
        html += "    <div class=\"page-header-left\">\(ReportShared.railToggleButton())<h1>\(ReportShared.esc(title))</h1></div>\n"
        html += "    \(ReportShared.themeToggleButton())\n"
        html += "  </div>\n"
        // The verified line carries the SHARED COUNTS (scale of the spec) —
        // not the report's pass/fail/progress chrome, which stays report-only.
        let scale = "\(result.totalFeatureCount) features · \(total) behaviors · \(result.totalStepCount) steps"
        html += "  <p class=\"page-sub\">"
        if allGreen {
            html += "<span class=\"check\">\u{2713}</span> \(scale) — <strong>every one verified</strong>"
        } else {
            html += "\(scale) — \(result.passedScenarioCount) of \(total) verified, \(result.failedScenarioCount) failing"
        }
        html += " · \(ReportShared.esc(formatter.string(from: result.endTime)))</p>\n"
        if let reportLink {
            html += "  <p class=\"cross-link\"><a href=\"\(ReportShared.esc(reportLink))\">View the full test report \u{2197}</a></p>\n"
        }
        html += "</header>\n"
        return html
    }

    private func generateFeatures(from result: TestRunResult) -> String {
        var html = ""
        for (i, feature) in result.featureResults.enumerated() {
            let verified = feature.allPassed
            html += "<section class=\"spec-feature\" id=\"\(ReportShared.featureAnchor(i))\">\n"
            html += "  <div class=\"feature-head\">\n"
            html += "    <h2>\(ReportShared.esc(feature.featureName))</h2>\n"
            html += "    <span class=\"verified \(verified ? "ok" : "bad")\">"
            html += verified ? "\u{2713} \(feature.scenarioResults.count) examples" : "\u{2717} \(feature.failedCount) failing"
            html += "</span>\n"
            html += "  </div>\n"
            if !feature.tags.isEmpty {
                html += "  <div class=\"tags\">"
                for tag in feature.tags { html += "<span class=\"tag\">@\(ReportShared.esc(tag))</span>" }
                html += "</div>\n"
            }
            if !feature.description.isEmpty {
                html += "  <p class=\"narrative\">\(ReportShared.esc(feature.description))</p>\n"
            }

            for (j, scenario) in feature.scenarioResults.enumerated() {
                let status = scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")
                let mark = scenario.skipped ? "\u{25CB}" : (scenario.passed ? "\u{2713}" : "\u{2717}")
                html += "  <details class=\"scenario \(status)\">\n"
                html += "    <summary>\n"
                html += "      <span class=\"mark \(status)\">\(mark)</span>\n"
                html += "      <span class=\"scenario-name\">\(ReportShared.esc(scenario.scenarioName))</span>\n"
                if let reportLink {
                    let anchor = "\(reportLink)#\(ReportShared.scenarioAnchor(i, j))"
                    html += "      <a class=\"run-link\" href=\"\(ReportShared.esc(anchor))\" title=\"See this run in the report\">run \u{2197}</a>\n"
                }
                html += "    </summary>\n"
                html += "    <div class=\"steps\">\n"
                for step in scenario.stepResults {
                    html += "      <div class=\"step\"><span class=\"kw\">\(ReportShared.esc(step.keyword))</span> "
                    html += "<span class=\"txt\">\(ReportShared.esc(step.text))</span></div>\n"
                }
                if scenario.stepResults.isEmpty {
                    html += "      <div class=\"step muted\">(no steps recorded)</div>\n"
                }
                html += "    </div>\n"
                html += "  </details>\n"
            }
            html += "</section>\n"
        }
        return html
    }

    private func generateCSS() -> String {
        return "<style>\n" + ReportShared.commonCSS() + """

            /* Layout + rail are shared (ReportShared.commonCSS); only the
               document body's prose styling is spec-specific. The card is
               edge-to-edge; the head/narrative pad themselves, and scenario
               rows get full-width dividers like the report. */
            .spec-feature { scroll-margin-top: 16px; }
            .feature-head { display: flex; align-items: baseline; justify-content: space-between; gap: 0.75rem; padding: 0.9rem 1.1rem 0.6rem; }
            .feature-head h2 { font-size: 1.15rem; letter-spacing: -0.01em; }
            .verified { font-size: 0.8rem; font-weight: 600; white-space: nowrap; }
            .verified.ok { color: var(--passed); }
            .verified.bad { color: var(--failed); }
            .tags { padding: 0 1.1rem 0.4rem; }
            .narrative { color: var(--faint); font-style: italic; margin: 0 1.1rem 0.8rem; white-space: pre-line; }
            .scenario { border-top: 1px solid var(--border); }
            .scenario summary { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 1.1rem; cursor: pointer; list-style: none; }
            .scenario summary:hover { background: color-mix(in srgb, var(--faint) 8%, transparent); }
            .scenario summary::-webkit-details-marker { display: none; }
            .mark { font-weight: 700; font-size: 0.85rem; flex: none; }
            .mark.passed { color: var(--passed); }
            .mark.failed { color: var(--failed); }
            .mark.skipped { color: var(--skipped); }
            .scenario-name { flex: 1; min-width: 0; overflow-wrap: anywhere; }
            .scenario.failed > summary { color: var(--failed); }
            .run-link { font-size: 0.72rem; color: var(--faint); white-space: nowrap; }
            .run-link:hover { color: var(--accent); }
            .steps { padding: 0.2rem 1.1rem 0.7rem 2.1rem; font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size: 0.85rem; line-height: 1.7; }
            .step { overflow-wrap: anywhere; }
            .step .kw { color: var(--accent); font-weight: 600; }
            .step .txt { color: var(--text); }
            .step.muted { color: var(--faint); font-style: italic; }
            </style>

            """
    }

    private func generateJS() -> String {
        return "<script>\n" + ReportShared.railNavJS() + "\n" + ReportShared.cycleThemeJS() + "\n</script>\n"
    }
}
