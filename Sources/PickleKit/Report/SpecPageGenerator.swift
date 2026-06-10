import Foundation
import Kumi

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

    /// Generate the complete living-specification HTML. The structure is built
    /// with Kumi; CSS, the theme pre-paint script, the rail, and the page JS
    /// are pre-rendered text spliced in via `.raw`.
    public func generate(from result: TestRunResult) -> String {
        Node.document(head: [
            .tag("meta", [.attr("charset", "UTF-8")]),
            .tag("meta", [.attr("name", "viewport"),
                          .attr("content", "width=device-width, initial-scale=1.0")]),
            .tag("title", [], text: title),
            .raw(ReportShared.themePrePaintScript()),
            .raw(generateCSS()),
        ], body: [
            generateHeader(from: result),
            .tag("div", [.class("page-layout")], [
                .raw(ReportShared.railHTML(from: result)),
                .tag("div", [.class("page-body")], [generateFeatures(from: result)]),
            ]),
            .raw(generateJS()),
        ]).render()
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

    private func generateHeader(from result: TestRunResult) -> Node {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let total = result.totalScenarioCount
        let allGreen = result.failedScenarioCount == 0
        // The verified line carries the SHARED COUNTS (scale of the spec) —
        // not the report's pass/fail/progress chrome, which stays report-only.
        let scale = "\(result.totalFeatureCount) features · \(total) behaviors · \(result.totalStepCount) steps"

        var sub: [Node]
        if allGreen {
            sub = [.tag("span", [.class("check")], text: "\u{2713}"),
                   .text(" \(scale) — "),
                   .tag("strong", [], text: "every one verified")]
        } else {
            sub = [.text("\(scale) — \(result.passedScenarioCount) of \(total) verified, "
                         + "\(result.failedScenarioCount) failing")]
        }
        sub.append(.text(" · \(formatter.string(from: result.endTime))"))

        var children: [Node] = [
            .tag("div", [.class("page-header-row")], [
                .tag("div", [.class("page-header-left")], [
                    .raw(ReportShared.railToggleButton()),
                    .tag("h1", [], text: title),
                ]),
                .raw(ReportShared.themeToggleButton()),
            ]),
            .tag("p", [.class("page-sub")], sub),
        ]
        if let reportLink {
            children.append(.tag("p", [.class("cross-link")], [
                .tag("a", [.href(reportLink)], text: "View the full test report \u{2197}"),
            ]))
        }
        return .tag("header", [.class("page-header")], children)
    }

    private func generateFeatures(from result: TestRunResult) -> Node {
        .fragment(result.featureResults.enumerated().map { i, feature in
            let verified = feature.allPassed
            return Node.section(.class("spec-feature"), .id(ReportShared.featureAnchor(i))) {
                Node.div(.class("feature-head")) {
                    Node.h2(text: feature.featureName)
                    Node.span([.class("verified \(verified ? "ok" : "bad")")],
                              text: verified ? "\u{2713} \(feature.scenarioResults.count) examples"
                                             : "\u{2717} \(feature.failedCount) failing")
                }
                if !feature.tags.isEmpty {
                    Node.div(.class("tags")) {
                        feature.tags.map { Node.span([.class("tag")], text: "@\($0)") }
                    }
                }
                if !feature.description.isEmpty {
                    Node.p([.class("narrative")], text: feature.description)
                }
                // Consecutive examples from one Scenario Outline collapse under a
                // single header; standalone scenarios render flat.
                for segment in ReportShared.segments(feature.scenarioResults) {
                    switch segment {
                    case .single(let j, let scenario):
                        scenarioNode(featureIndex: i, scenarioIndex: j, scenario: scenario,
                                     displayName: scenario.scenarioName)
                    case .outline(let name, let cases):
                        let status = ReportShared.groupStatus(cases)
                        // Collapsed by default — the header (name + count) is the summary.
                        Node.details(.class("outline-group"), .data("status", status)) {
                            Node.summary {
                                Node.span([.class("outline-name")], text: name)
                                Node.span([.class("outline-badge")], text: "outline \u{00B7} \(cases.count)")
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
        let status = scenario.skipped ? "skipped" : (scenario.passed ? "passed" : "failed")
        let mark = scenario.skipped ? "\u{25CB}" : (scenario.passed ? "\u{2713}" : "\u{2717}")

        return Node.details(.class("scenario \(status)")) {
            Node.summary {
                Node.span([.class("mark \(status)")], text: mark)
                Node.span([.class("scenario-name")], text: displayName)
                if let reportLink {
                    Node.a([.class("run-link"),
                            .href("\(reportLink)#\(ReportShared.scenarioAnchor(i, j))"),
                            .attr("title", "See this run in the report")], text: "run \u{2197}")
                }
            }
            Node.div(.class("steps")) {
                if scenario.stepResults.isEmpty {
                    Node.div([.class("step muted")], text: "(no steps recorded)")
                } else {
                    scenario.stepResults.map { step in
                        Node.div([.class("step")], [
                            .tag("span", [.class("kw")], text: step.keyword),
                            .text(" "),
                            .tag("span", [.class("txt")], text: step.text),
                        ])
                    }
                }
            }
        }
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
