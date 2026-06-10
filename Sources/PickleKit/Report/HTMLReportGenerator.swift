import Foundation
import Kumi

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

    /// Generate a complete HTML string from the test run result. Structure is
    /// built with Kumi; CSS, the theme pre-paint script, the summary, the rail,
    /// and the page JS are pre-rendered text spliced in via `.raw`.
    public func generate(from result: TestRunResult) -> String {
        Node.document(head: [
            .tag("meta", [.attr("charset", "UTF-8")]),
            .tag("meta", [.attr("name", "viewport"),
                          .attr("content", "width=device-width, initial-scale=1.0")]),
            .tag("title", [], text: "PickleKit Test Report"),
            .raw(ReportShared.themePrePaintScript()),
            .raw(generateCSS()),
        ], body: [
            generateHeader(from: result),
            .tag("div", [.class("page-layout")], [
                .raw(ReportShared.railHTML(from: result)),
                .tag("div", [.class("page-body")], [
                    .raw(ReportShared.summaryHTML(from: result)),
                    .tag("div", [.class("controls")], [
                        .tag("button", [.attr("onclick", "expandAll()")], text: "Expand All"),
                        .tag("button", [.attr("onclick", "collapseAll()")], text: "Collapse All"),
                        .tag("button", [.attr("onclick", "filterStatus('all')"), .class("active"),
                                        .data("filter", "all")], text: "All"),
                        .tag("button", [.attr("onclick", "filterStatus('passed')"),
                                        .data("filter", "passed")], text: "Passed"),
                        .tag("button", [.attr("onclick", "filterStatus('skipped')"),
                                        .data("filter", "skipped")], text: "Skipped"),
                        .tag("button", [.attr("onclick", "filterStatus('failed')"),
                                        .data("filter", "failed")], text: "Failed"),
                    ]),
                    generateFeatures(from: result),
                ]),
            ]),
            .raw(generateJS()),
        ]).render()
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
            .scenario-name { font-weight: 500; min-width: 0; overflow-wrap: anywhere; }
            .scenario-duration { font-size: 12px; color: var(--faint); margin-left: auto; }
            .status-badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
            .status-passed { background: color-mix(in srgb, var(--passed) 22%, transparent); color: var(--passed); }
            .status-failed { background: color-mix(in srgb, var(--failed) 22%, transparent); color: var(--failed); }
            .status-skipped { background: color-mix(in srgb, var(--skipped) 25%, transparent); color: var(--skipped); }
            .status-undefined { background: color-mix(in srgb, var(--undefined) 22%, transparent); color: var(--undefined); }
            .steps { padding: 0 16px 12px 16px; }
            .step-row { display: flex; align-items: baseline; padding: 4px 0; font-size: 13px; }
            .step-keyword { color: var(--accent); font-weight: 600; min-width: 60px; }
            .step-text { flex: 1; min-width: 0; overflow-wrap: anywhere; }
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

    private func generateHeader(from result: TestRunResult) -> Node {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let duration = ReportShared.formatDuration(result.duration)

        var children: [Node] = [
            .tag("div", [.class("page-header-row")], [
                .tag("div", [.class("page-header-left")], [
                    .raw(ReportShared.railToggleButton()),
                    .tag("h1", [], text: "PickleKit Test Report"),
                ]),
                .raw(ReportShared.themeToggleButton()),
            ]),
            .tag("div", [.class("page-sub")],
                 text: "\(formatter.string(from: result.startTime)) \u{2014} Duration: \(duration)"),
        ]
        if let specLink {
            children.append(.tag("p", [.class("cross-link")], [
                .tag("a", [.href(specLink)], text: "\u{2190} Read it as a specification"),
            ]))
        }
        return .tag("header", [.class("page-header")], children)
    }

    private func generateFeatures(from result: TestRunResult) -> Node {
        .fragment(result.featureResults.enumerated().map { i, feature in
            let featureStatus: String
            if feature.failedCount > 0 {
                featureStatus = "failed"
            } else if feature.scenarioResults.allSatisfy(\.skipped) {
                featureStatus = "skipped"
            } else {
                featureStatus = "passed"
            }

            let executedCount = feature.scenarioResults.count - feature.skippedCount
            var stats = "\(feature.passedCount)/\(executedCount) scenarios passed"
            if feature.skippedCount > 0 { stats += ", \(feature.skippedCount) skipped" }
            stats += " \u{00B7} \(ReportShared.formatDuration(feature.duration))"

            return Node.details(.class("feature"), .id(ReportShared.featureAnchor(i)),
                                .data("status", featureStatus), .flag("open")) {
                Node.summary([.class("feature-header")], [
                    .tag("div", [.class("feature-title")],
                         [.tag("h2", [], text: feature.featureName)]
                            + feature.tags.map { .tag("span", [.class("tag")], text: "@\($0)") }),
                    .tag("span", [.class("feature-stats")], text: stats),
                ])
                // Outline examples collapse under one group header; standalone
                // scenarios render flat. Per-scenario anchors/ids are unchanged.
                for segment in ReportShared.segments(feature.scenarioResults) {
                    switch segment {
                    case .single(let j, let scenario):
                        scenarioNode(featureIndex: i, scenarioIndex: j, scenario: scenario,
                                     displayName: scenario.scenarioName)
                    case .outline(let name, let cases):
                        let status = ReportShared.groupStatus(cases)
                        // Collapsed by default, but a group with a failure opens
                        // so the failing example stays visible.
                        Node.details(.class("outline-group"), .data("status", status),
                                     .flag("open", if: status == "failed")) {
                            Node.summary {
                                Node.span([.class("outline-name")], text: name)
                                Node.span([.class("outline-badge")], text: "outline \u{00B7} \(cases.count)")
                                Node.span([.class("status-badge status-\(status)")], text: status)
                            }
                            Node.div(.class("outline-cases")) {
                                cases.map {
                                    scenarioNode(featureIndex: i, scenarioIndex: $0.index,
                                                 scenario: $0.scenario,
                                                 displayName: $0.scenario.exampleLabel ?? $0.scenario.scenarioName)
                                }
                            }
                        }
                    }
                }
            }
        })
    }

    /// One scenario's `<details>` block. `displayName` lets a grouped outline
    /// case show just its example label (the outline name sits in the header).
    private func scenarioNode(featureIndex i: Int, scenarioIndex j: Int,
                              scenario: ScenarioResult, displayName: String) -> Node {
        let statusClass = scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")

        return Node.details(.class("scenario"), .id(ReportShared.scenarioAnchor(i, j)),
                            .data("status", statusClass),
                            .flag("open", if: !scenario.passed && !scenario.skipped)) {
            Node.summary {
                Node.span([.class("scenario-name")], text: displayName)
                Node.span([.class("status-badge status-\(statusClass)")], text: statusClass)
                for tag in scenario.tags { Node.span([.class("tag")], text: "@\(tag)") }
                Node.span([.class("scenario-duration")], text: ReportShared.formatDuration(scenario.duration))
            }
            Node.div(.class("steps")) {
                for step in scenario.stepResults {
                    Node.div([.class("step-row \(step.status.rawValue)")],
                             [.tag("span", [.class("step-keyword")], text: step.keyword),
                              .tag("span", [.class("step-text")], text: step.text)]
                                + (step.duration > 0
                                   ? [.tag("span", [.class("step-duration")],
                                          text: ReportShared.formatDuration(step.duration))]
                                   : []))
                    if let error = step.error {
                        Node.div([.class("step-error")], text: error)
                    }
                }
            }
        }
    }

    private func generateJS() -> String {
        return "<script>\n" + """
            function expandAll() {
              document.querySelectorAll('details.feature, details.outline-group').forEach(d => d.open = true);
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
                // An outline group hides when none of its examples match.
                feature.querySelectorAll('.outline-group').forEach(g => {
                  const visible = g.querySelector('.scenario:not(.hidden)');
                  g.classList.toggle('hidden', !visible);
                  if (visible) g.open = true;
                });
                feature.classList.toggle('hidden', !anyVisible);
                if (anyVisible) feature.open = true;
              });
            }
            """ + ReportShared.railNavJS() + "\n" + ReportShared.cycleThemeJS() + "\n</script>\n"
    }
}
