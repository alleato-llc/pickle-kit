import Foundation

/// Generates a self-contained, interactive HTML **report** from a test run —
/// the audit view (summary, filtering, collapsible features/scenarios,
/// per-step timing, the outline drawer). It renders the shared chrome
/// (palette, summary, anchors, theme) through `ReportShared`, so it stays
/// cohesive with the living-spec view a `ReportSuite` emits beside it.
///
/// `specLink` (optional) adds a header link back to the living specification;
/// `ReportSuite` wires it. Used alone, the report stands on its own.
public struct HTMLReportGenerator: Sendable {

    /// Relative link to the companion living-spec page (nil = standalone).
    public let specLink: String?

    public init(specLink: String? = nil) {
        self.specLink = specLink
    }

    /// Generate a complete HTML string from the test run result.
    public func generate(from result: TestRunResult) -> String {
        var html = ""
        html += "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        html += "<meta charset=\"UTF-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        html += "<title>PickleKit Test Report</title>\n"
        html += ReportShared.themePrePaintScript()
        html += generateCSS()
        html += "</head>\n<body>\n"
        html += generateHeader(from: result)
        html += "<div class=\"page-layout\">\n"
        html += ReportShared.railHTML(from: result)
        html += "<div class=\"page-body\">\n"
        html += ReportShared.summaryHTML(from: result)
        html += "<div class=\"controls\">\n"
        html += "  <button onclick=\"expandAll()\">Expand All</button>\n"
        html += "  <button onclick=\"collapseAll()\">Collapse All</button>\n"
        html += "  <button onclick=\"filterStatus('all')\" class=\"active\" data-filter=\"all\">All</button>\n"
        html += "  <button onclick=\"filterStatus('passed')\" data-filter=\"passed\">Passed</button>\n"
        html += "  <button onclick=\"filterStatus('skipped')\" data-filter=\"skipped\">Skipped</button>\n"
        html += "  <button onclick=\"filterStatus('failed')\" data-filter=\"failed\">Failed</button>\n"
        html += "</div>\n"
        html += generateFeatures(from: result)
        html += "</div>\n</div>\n"
        html += generateJS()
        html += "</body>\n</html>"
        return html
    }

    /// Write the report HTML to a file path, creating intermediate directories if needed.
    public func write(result: TestRunResult, to path: String) throws {
        let html = generate(from: result)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Generators

    private func generateCSS() -> String {
        return "<style>\n" + ReportShared.commonCSS() + "\n" + ReportShared.summaryCSS() + """

            .mono, .step-row, .step-error { font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; }
            .controls { margin-bottom: 20px; display: flex; gap: 8px; flex-wrap: wrap; }
            .controls button { padding: 8px 16px; border: 1px solid var(--border); background: transparent; color: var(--text); border-radius: 8px; cursor: pointer; font-size: 13px; }
            .controls button:hover { border-color: var(--faint); }
            .controls button.active { background: var(--accent); color: var(--bg); border-color: transparent; }
            .feature > summary { padding: 16px; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; list-style: none; }
            .feature > summary::-webkit-details-marker { display: none; }
            .feature > summary::before { content: '\\25B6'; font-size: 10px; transition: transform 0.2s; color: var(--faint); align-self: center; }
            .feature[open] > summary::before { transform: rotate(90deg); }
            .feature > summary .feature-title { flex: 1; }
            .feature-header h2 { font-size: 1.15rem; display: inline; letter-spacing: -0.01em; }
            .feature-stats { font-size: 13px; color: var(--faint); }
            .scenario { border-top: 1px solid var(--border); }
            .scenario summary { padding: 12px 16px; cursor: pointer; display: flex; align-items: center; gap: 8px; list-style: none; }
            .scenario[data-status="failed"] summary { background: color-mix(in srgb, var(--error) 8%, transparent); }
            .scenario summary::-webkit-details-marker { display: none; }
            .scenario summary::before { content: '\\25B6'; font-size: 10px; transition: transform 0.2s; color: var(--faint); }
            .scenario[open] summary::before { transform: rotate(90deg); }
            .scenario-name { font-weight: 500; }
            .scenario-duration { font-size: 12px; color: var(--faint); margin-left: auto; }
            .status-badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
            .status-passed { background: color-mix(in srgb, var(--passed) 22%, transparent); color: var(--passed); }
            .status-failed { background: color-mix(in srgb, var(--failed) 22%, transparent); color: var(--failed); }
            .status-skipped { background: color-mix(in srgb, var(--skipped) 25%, transparent); color: var(--skipped); }
            .status-undefined { background: color-mix(in srgb, var(--undefined) 22%, transparent); color: var(--undefined); }
            .steps { padding: 0 16px 12px 16px; }
            .step-row { display: flex; align-items: baseline; padding: 4px 0; font-size: 13px; }
            .step-keyword { color: var(--accent); font-weight: 600; min-width: 60px; }
            .step-text { flex: 1; }
            .step-duration { color: var(--faint); font-size: 11px; min-width: 70px; text-align: right; }
            .step-row.passed .step-text { color: var(--text); }
            .step-row.failed .step-text { color: var(--failed); }
            .step-row.skipped .step-text { color: var(--skipped); }
            .step-row.undefined .step-text { color: var(--undefined); }
            .step-error { background: color-mix(in srgb, var(--error) 8%, transparent); border-left: 3px solid var(--error); padding: 8px 12px; margin: 4px 0 4px 60px; font-size: 12px; color: var(--error); white-space: pre-wrap; word-break: break-word; }
            .hidden { display: none !important; }
            :is(.feature, .scenario) { scroll-margin-top: 16px; }
            </style>

            """
    }

    private func generateHeader(from result: TestRunResult) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let duration = ReportShared.formatDuration(result.duration)

        var html = "<header class=\"page-header\">\n"
        html += "  <div class=\"page-header-row\">\n"
        html += "    <div class=\"page-header-left\">\(ReportShared.railToggleButton())<h1>PickleKit Test Report</h1></div>\n"
        html += "    \(ReportShared.themeToggleButton())\n"
        html += "  </div>\n"
        html += "  <div class=\"page-sub\">\(ReportShared.esc(formatter.string(from: result.startTime))) &mdash; Duration: \(duration)</div>\n"
        if let specLink {
            html += "  <p class=\"cross-link\"><a href=\"\(ReportShared.esc(specLink))\">\u{2190} Read it as a specification</a></p>\n"
        }
        html += "</header>\n"
        return html
    }

    private func generateFeatures(from result: TestRunResult) -> String {
        var html = ""
        for (i, feature) in result.featureResults.enumerated() {
            let featureStatus: String
            if feature.failedCount > 0 {
                featureStatus = "failed"
            } else if feature.scenarioResults.allSatisfy(\.skipped) {
                featureStatus = "skipped"
            } else {
                featureStatus = "passed"
            }
            html += "<details class=\"feature\" id=\"\(ReportShared.featureAnchor(i))\" data-status=\"\(featureStatus)\" open>\n"
            html += "  <summary class=\"feature-header\">\n"
            html += "    <div class=\"feature-title\">\n"
            html += "      <h2>\(ReportShared.esc(feature.featureName))</h2>\n"
            if !feature.tags.isEmpty {
                html += " "
                for tag in feature.tags { html += "<span class=\"tag\">@\(ReportShared.esc(tag))</span>" }
            }
            html += "\n    </div>\n"
            html += "    <span class=\"feature-stats\">"
            let executedCount = feature.scenarioResults.count - feature.skippedCount
            html += "\(feature.passedCount)/\(executedCount) scenarios passed"
            if feature.skippedCount > 0 { html += ", \(feature.skippedCount) skipped" }
            html += " &middot; \(ReportShared.formatDuration(feature.duration))"
            html += "</span>\n"
            html += "  </summary>\n"

            for (j, scenario) in feature.scenarioResults.enumerated() {
                let statusClass = scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")
                let openAttr = (!scenario.passed && !scenario.skipped) ? " open" : ""
                html += "  <details class=\"scenario\" id=\"\(ReportShared.scenarioAnchor(i, j))\" data-status=\"\(statusClass)\"\(openAttr)>\n"
                html += "    <summary>\n"
                html += "      <span class=\"scenario-name\">\(ReportShared.esc(scenario.scenarioName))</span>\n"
                html += "      <span class=\"status-badge status-\(statusClass)\">\(statusClass)</span>\n"
                if !scenario.tags.isEmpty {
                    for tag in scenario.tags { html += "      <span class=\"tag\">@\(ReportShared.esc(tag))</span>\n" }
                }
                html += "      <span class=\"scenario-duration\">\(ReportShared.formatDuration(scenario.duration))</span>\n"
                html += "    </summary>\n"
                html += "    <div class=\"steps\">\n"
                for stepResult in scenario.stepResults {
                    let stepClass = stepResult.status.rawValue
                    html += "      <div class=\"step-row \(stepClass)\">\n"
                    html += "        <span class=\"step-keyword\">\(ReportShared.esc(stepResult.keyword))</span>\n"
                    html += "        <span class=\"step-text\">\(ReportShared.esc(stepResult.text))</span>\n"
                    if stepResult.duration > 0 {
                        html += "        <span class=\"step-duration\">\(ReportShared.formatDuration(stepResult.duration))</span>\n"
                    }
                    html += "      </div>\n"
                    if let error = stepResult.error {
                        html += "      <div class=\"step-error\">\(ReportShared.esc(error))</div>\n"
                    }
                }
                html += "    </div>\n"
                html += "  </details>\n"
            }
            html += "</details>\n"
        }
        return html
    }

    private func generateJS() -> String {
        return "<script>\n" + """
            function expandAll() {
              document.querySelectorAll('details.feature').forEach(d => d.open = true);
              document.querySelectorAll('details.scenario:not(.hidden)').forEach(d => d.open = true);
            }
            function collapseAll() {
              document.querySelectorAll('details.scenario').forEach(d => d.open = false);
            }
            function filterStatus(status) {
              document.querySelectorAll('.controls button[data-filter]').forEach(b => b.classList.remove('active'));
              document.querySelector('.controls button[data-filter="' + status + '"]').classList.add('active');
              document.querySelectorAll('.feature').forEach(feature => {
                const scenarios = feature.querySelectorAll('.scenario');
                let anyVisible = false;
                scenarios.forEach(s => {
                  if (status === 'all' || s.dataset.status === status) {
                    s.classList.remove('hidden');
                    anyVisible = true;
                  } else {
                    s.classList.add('hidden');
                  }
                });
                feature.classList.toggle('hidden', !anyVisible);
                if (anyVisible) feature.open = true;
              });
            }
            """ + ReportShared.railNavJS() + "\n" + ReportShared.cycleThemeJS() + "\n</script>\n"
    }
}
