import Foundation

/// Generates a self-contained HTML report from test run results.
///
/// The report is themeable (light/dark, following the system by default and
/// remembered in `localStorage`) using the same palette as the Soroban
/// landing page — Solarized Light / Dracula — so a report can be dropped
/// straight onto the site. Features and scenarios are independently
/// collapsible, and a collapsible outline sidebar (collapsed by default)
/// gives quick navigation across a large run.
public struct HTMLReportGenerator: Sendable {

    public init() {}

    /// Generate a complete HTML string from the test run result.
    public func generate(from result: TestRunResult) -> String {
        var html = ""
        html += "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        html += "<meta charset=\"UTF-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        html += "<title>PickleKit Test Report</title>\n"
        // Set the theme before first paint (no flash), mirroring the site.
        html += """
            <script>
            (function () {
              var t = localStorage.getItem('pickle-theme');
              if (!t) t = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
              document.documentElement.setAttribute('data-theme', t);
            })();
            </script>

            """
        html += generateCSS()
        html += "</head>\n<body>\n"
        html += generateOutline(from: result)
        html += "<div class=\"outline-scrim\" onclick=\"toggleOutline()\"></div>\n"
        html += "<main class=\"content\">\n"
        html += generateHeader(from: result)
        html += generateSummary(from: result)
        html += "<div class=\"controls\">\n"
        html += "  <button onclick=\"expandAll()\">Expand All</button>\n"
        html += "  <button onclick=\"collapseAll()\">Collapse All</button>\n"
        html +=
            "  <button onclick=\"filterStatus('all')\" class=\"active\" data-filter=\"all\">All</button>\n"
        html +=
            "  <button onclick=\"filterStatus('passed')\" data-filter=\"passed\">Passed</button>\n"
        html +=
            "  <button onclick=\"filterStatus('skipped')\" data-filter=\"skipped\">Skipped</button>\n"
        html +=
            "  <button onclick=\"filterStatus('failed')\" data-filter=\"failed\">Failed</button>\n"
        html += "</div>\n"
        html += generateFeatures(from: result)
        html += "</main>\n"
        html += generateJS()
        html += "</body>\n</html>"
        return html
    }

    /// Write the report HTML to a file path, creating intermediate directories if needed.
    public func write(result: TestRunResult, to path: String) throws {
        let html = generate(from: result)
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try html.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Generators

    private func generateCSS() -> String {
        return """
            <style>
            /* Palette lifted from the Soroban site (Solarized Light / Dracula)
               so reports match the landing page. data-theme is set before
               paint by the inline script above. */
            :root, :root[data-theme="light"] {
              --bg: #fdf6e3; --surface: #eee8d5; --text: #073642;
              --muted: #657b83; --faint: #93a1a1; --accent: #268bd2;
              --error: #dc322f; --border: rgba(7,54,66,0.12); --shadow: rgba(7,54,66,0.06);
              --passed: #2aa198; --failed: #dc322f; --skipped: #93a1a1; --undefined: #b58900;
            }
            :root[data-theme="dark"] {
              --bg: #282a36; --surface: #343746; --text: #f8f8f2;
              --muted: #bd93f9; --faint: #6272a4; --accent: #ff79c6;
              --error: #ff5555; --border: rgba(248,248,242,0.1); --shadow: rgba(0,0,0,0.3);
              --passed: #50fa7b; --failed: #ff5555; --skipped: #6272a4; --undefined: #ffb86c;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font: 16px/1.6 system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--text); padding: 20px; transition: background 0.2s ease, color 0.2s ease; -webkit-font-smoothing: antialiased; }
            .content { max-width: 1000px; margin: 0 auto; }
            .mono, .step-row, .step-error { font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; }
            .report-header { background: var(--surface); border: 1px solid var(--border); padding: 24px; border-radius: 12px; margin-bottom: 20px; display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }
            .report-header h1 { font-size: 24px; margin-bottom: 8px; letter-spacing: -0.01em; }
            .report-header .timestamp { color: var(--faint); font-size: 14px; }
            .theme-toggle { border: 1px solid var(--border); background: var(--bg); color: var(--muted); border-radius: 8px; width: 2.2rem; height: 2.2rem; font-size: 1.05rem; cursor: pointer; line-height: 1; flex: none; }
            .theme-toggle:hover { color: var(--text); }
            .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 20px; }
            .summary-card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 16px; box-shadow: 0 1px 3px var(--shadow); }
            .summary-card h3 { font-size: 13px; text-transform: uppercase; color: var(--faint); margin-bottom: 8px; letter-spacing: 0.04em; }
            .summary-card .count { font-size: 28px; font-weight: bold; }
            .summary-card .breakdown { font-size: 13px; color: var(--muted); margin-top: 4px; }
            .progress-bar { height: 8px; background: color-mix(in srgb, var(--faint) 25%, transparent); border-radius: 4px; overflow: hidden; margin-top: 8px; display: flex; }
            .progress-bar .passed { background: var(--passed); }
            .progress-bar .failed { background: var(--failed); }
            .progress-bar .skipped { background: var(--skipped); }
            .progress-bar .undefined { background: var(--undefined); }
            .controls { margin-bottom: 20px; display: flex; gap: 8px; flex-wrap: wrap; }
            .controls button { padding: 8px 16px; border: 1px solid var(--border); background: var(--surface); color: var(--text); border-radius: 8px; cursor: pointer; font-size: 13px; }
            .controls button:hover { border-color: var(--faint); }
            .controls button.active { background: var(--accent); color: var(--bg); border-color: transparent; }
            .feature { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; margin-bottom: 16px; box-shadow: 0 1px 3px var(--shadow); overflow: hidden; }
            .feature > summary { padding: 16px; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; list-style: none; }
            .feature > summary::-webkit-details-marker { display: none; }
            .feature > summary::before { content: '\\25B6'; font-size: 10px; transition: transform 0.2s; color: var(--faint); align-self: center; }
            .feature[open] > summary::before { transform: rotate(90deg); }
            .feature > summary .feature-title { flex: 1; }
            .feature-header h2 { font-size: 18px; display: inline; }
            .feature-stats { font-size: 13px; color: var(--faint); }
            .tag { display: inline-block; background: color-mix(in srgb, var(--accent) 14%, transparent); color: var(--accent); padding: 2px 8px; border-radius: 999px; font-size: 11px; margin-right: 4px; }
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

            /* ---------- outline sidebar (collapsed by default) ---------- */
            .outline-toggle { position: fixed; top: 20px; left: 20px; z-index: 30; width: 2.4rem; height: 2.4rem; border: 1px solid var(--border); background: var(--surface); color: var(--text); border-radius: 8px; font-size: 1.1rem; cursor: pointer; box-shadow: 0 1px 3px var(--shadow); }
            .outline-toggle:hover { border-color: var(--faint); }
            .outline { position: fixed; top: 0; left: 0; bottom: 0; width: 300px; z-index: 40; background: var(--surface); border-right: 1px solid var(--border); box-shadow: 0 0 40px var(--shadow); padding: 1.25rem 0.5rem 1.25rem 1.25rem; overflow-y: auto; transform: translateX(-100%); transition: transform 0.22s ease; }
            .outline.open { transform: translateX(0); }
            .outline h2 { font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--faint); margin-bottom: 0.75rem; }
            .outline ul { list-style: none; }
            .outline .feature-link { display: block; padding: 0.35rem 0; color: var(--text); font-weight: 600; font-size: 0.92rem; text-decoration: none; }
            .outline .scenario-link { display: flex; align-items: center; gap: 0.4rem; padding: 0.2rem 0 0.2rem 0.9rem; color: var(--muted); font-size: 0.85rem; text-decoration: none; border-left: 2px solid var(--border); margin-left: 2px; }
            .outline a:hover { color: var(--accent); }
            .outline .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
            .outline .dot.passed { background: var(--passed); }
            .outline .dot.failed { background: var(--failed); }
            .outline .dot.skipped { background: var(--skipped); }
            .outline-scrim { position: fixed; inset: 0; z-index: 35; background: rgba(0,0,0,0.25); opacity: 0; pointer-events: none; transition: opacity 0.22s ease; }
            .outline-scrim.show { opacity: 1; pointer-events: auto; }
            :is(.feature, .scenario) { scroll-margin-top: 16px; }
            </style>

            """
    }

    private func generateHeader(from result: TestRunResult) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let duration = formatDuration(result.duration)

        var html = "<div class=\"report-header\">\n"
        html += "  <div>\n"
        html += "    <h1>PickleKit Test Report</h1>\n"
        html +=
            "    <div class=\"timestamp\">\(esc(formatter.string(from: result.startTime))) &mdash; Duration: \(duration)</div>\n"
        html += "  </div>\n"
        html += "  <button class=\"theme-toggle\" onclick=\"cycleTheme()\" aria-label=\"Toggle theme\" title=\"Toggle light/dark\">\u{25D0}</button>\n"
        html += "</div>\n"
        return html
    }

    private func generateSummary(from result: TestRunResult) -> String {
        var html = "<div class=\"summary\">\n"

        // Features card
        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Features</h3>\n"
        html += "    <div class=\"count\">\(result.totalFeatureCount)</div>\n"
        html +=
            "    <div class=\"breakdown\">\(result.passedFeatureCount) passed, \(result.failedFeatureCount) failed</div>\n"
        html += progressBar(
            passed: result.passedFeatureCount, failed: result.failedFeatureCount, skipped: 0,
            undefined: 0, total: result.totalFeatureCount)
        html += "  </div>\n"

        // Scenarios card
        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Scenarios</h3>\n"
        html += "    <div class=\"count\">\(result.totalScenarioCount)</div>\n"
        html +=
            "    <div class=\"breakdown\">\(result.passedScenarioCount) passed, \(result.failedScenarioCount) failed"
        if result.skippedScenarioCount > 0 {
            html += ", \(result.skippedScenarioCount) skipped"
        }
        html += "</div>\n"
        html += progressBar(
            passed: result.passedScenarioCount, failed: result.failedScenarioCount,
            skipped: result.skippedScenarioCount, undefined: 0, total: result.totalScenarioCount)
        html += "  </div>\n"

        // Steps card
        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Steps</h3>\n"
        html += "    <div class=\"count\">\(result.totalStepCount)</div>\n"
        html +=
            "    <div class=\"breakdown\">\(result.passedStepCount) passed, \(result.failedStepCount) failed, \(result.skippedStepCount) skipped"
        if result.undefinedStepCount > 0 {
            html += ", \(result.undefinedStepCount) undefined"
        }
        html += "</div>\n"
        html += progressBar(
            passed: result.passedStepCount, failed: result.failedStepCount,
            skipped: result.skippedStepCount, undefined: result.undefinedStepCount,
            total: result.totalStepCount)
        html += "  </div>\n"

        html += "</div>\n"
        return html
    }

    /// The collapsible outline: each feature, with its scenarios as jump
    /// links (status dot + name). Collapsed by default — toggled by the
    /// floating button.
    private func generateOutline(from result: TestRunResult) -> String {
        var html = "<button class=\"outline-toggle\" onclick=\"toggleOutline()\" aria-label=\"Toggle outline\" title=\"Outline\">\u{2630}</button>\n"
        html += "<nav class=\"outline\" id=\"outline\">\n"
        html += "  <h2>Outline</h2>\n"
        html += "  <ul>\n"
        for (i, feature) in result.featureResults.enumerated() {
            let featureID = "feature-\(i)"
            html += "    <li>\n"
            html += "      <a class=\"feature-link\" href=\"#\(featureID)\" onclick=\"jumpTo('\(featureID)'); return false;\">\(esc(feature.featureName))</a>\n"
            html += "      <ul>\n"
            for (j, scenario) in feature.scenarioResults.enumerated() {
                let scenarioID = "scenario-\(i)-\(j)"
                let statusClass =
                    scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")
                html += "        <li><a class=\"scenario-link\" href=\"#\(scenarioID)\" onclick=\"jumpTo('\(scenarioID)'); return false;\">"
                html += "<span class=\"dot \(statusClass)\"></span>\(esc(scenario.scenarioName))</a></li>\n"
            }
            html += "      </ul>\n"
            html += "    </li>\n"
        }
        html += "  </ul>\n"
        html += "</nav>\n"
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
            // The feature is its own collapsible <details> (open by default);
            // the header is its <summary>. data-status drives status filtering.
            html += "<details class=\"feature\" id=\"feature-\(i)\" data-status=\"\(featureStatus)\" open>\n"
            html += "  <summary class=\"feature-header\">\n"
            html += "    <div class=\"feature-title\">\n"
            html += "      <h2>\(esc(feature.featureName))</h2>\n"
            if !feature.tags.isEmpty {
                html += " "
                for tag in feature.tags {
                    html += "<span class=\"tag\">@\(esc(tag))</span>"
                }
            }
            html += "\n    </div>\n"
            html += "    <span class=\"feature-stats\">"
            let executedCount = feature.scenarioResults.count - feature.skippedCount
            html += "\(feature.passedCount)/\(executedCount) scenarios passed"
            if feature.skippedCount > 0 {
                html += ", \(feature.skippedCount) skipped"
            }
            html += " &middot; \(formatDuration(feature.duration))"
            html += "</span>\n"
            html += "  </summary>\n"

            for (j, scenario) in feature.scenarioResults.enumerated() {
                let statusClass =
                    scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")
                let openAttr = (!scenario.passed && !scenario.skipped) ? " open" : ""
                html += "  <details class=\"scenario\" id=\"scenario-\(i)-\(j)\" data-status=\"\(statusClass)\"\(openAttr)>\n"
                html += "    <summary>\n"
                html += "      <span class=\"scenario-name\">\(esc(scenario.scenarioName))</span>\n"
                html +=
                    "      <span class=\"status-badge status-\(statusClass)\">\(statusClass)</span>\n"
                if !scenario.tags.isEmpty {
                    for tag in scenario.tags {
                        html += "      <span class=\"tag\">@\(esc(tag))</span>\n"
                    }
                }
                html +=
                    "      <span class=\"scenario-duration\">\(formatDuration(scenario.duration))</span>\n"
                html += "    </summary>\n"
                html += "    <div class=\"steps\">\n"

                for stepResult in scenario.stepResults {
                    let stepClass = stepResult.status.rawValue
                    html += "      <div class=\"step-row \(stepClass)\">\n"
                    html +=
                        "        <span class=\"step-keyword\">\(esc(stepResult.keyword))</span>\n"
                    html += "        <span class=\"step-text\">\(esc(stepResult.text))</span>\n"
                    if stepResult.duration > 0 {
                        html +=
                            "        <span class=\"step-duration\">\(formatDuration(stepResult.duration))</span>\n"
                    }
                    html += "      </div>\n"
                    if let error = stepResult.error {
                        html += "      <div class=\"step-error\">\(esc(error))</div>\n"
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
        return """
            <script>
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
            function toggleOutline() {
              const open = document.getElementById('outline').classList.toggle('open');
              document.querySelector('.outline-scrim').classList.toggle('show', open);
            }
            function jumpTo(id) {
              const el = document.getElementById(id);
              if (!el) return;
              if (el.tagName === 'DETAILS') el.open = true;
              // Open the enclosing feature so a scenario target is visible.
              const feature = el.closest('details.feature');
              if (feature) feature.open = true;
              el.classList.remove('hidden');
              el.scrollIntoView({ behavior: 'smooth', block: 'start' });
              toggleOutline();
            }
            function cycleTheme() {
              const root = document.documentElement;
              const next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
              root.setAttribute('data-theme', next);
              localStorage.setItem('pickle-theme', next);
            }
            </script>

            """
    }

    // MARK: - Helpers

    private func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.0f\u{00B5}s", seconds * 1_000_000)
        } else if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.2fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = seconds - Double(mins * 60)
            return String(format: "%dm %.1fs", mins, secs)
        }
    }

    private func progressBar(passed: Int, failed: Int, skipped: Int, undefined: Int, total: Int)
        -> String
    {
        guard total > 0 else { return "" }
        let pPct = Double(passed) / Double(total) * 100
        let fPct = Double(failed) / Double(total) * 100
        let sPct = Double(skipped) / Double(total) * 100
        let uPct = Double(undefined) / Double(total) * 100

        var html = "    <div class=\"progress-bar\">"
        if passed > 0 { html += "<div class=\"passed\" style=\"width:\(pPct)%\"></div>" }
        if failed > 0 { html += "<div class=\"failed\" style=\"width:\(fPct)%\"></div>" }
        if skipped > 0 { html += "<div class=\"skipped\" style=\"width:\(sPct)%\"></div>" }
        if undefined > 0 { html += "<div class=\"undefined\" style=\"width:\(uPct)%\"></div>" }
        html += "</div>\n"
        return html
    }
}
