import Foundation

/// Produces the cohesive PAIR of views for a test run — the interactive
/// **report** (audit) and the **living specification** (documentation) — from
/// one `TestRunResult`. Owning both is what keeps them consistent: they share
/// anchors (deep links can't drift), the same summary counts, one palette,
/// and they cross-link to each other. The spec is the front door; the report
/// is the detail you open only when you want test-level results.
public struct ReportSuite: Sendable {

    /// Title for the living-specification page (e.g. "Anzan — Living Spec").
    public let specTitle: String

    public init(specTitle: String = "Living Specification") {
        self.specTitle = specTitle
    }

    /// The two rendered pages, cross-linked by the given file names.
    public func generate(
        from result: TestRunResult,
        reportFileName: String = "pickle-report.html",
        specFileName: String = "pickle-spec.html"
    ) -> (report: String, spec: String) {
        let report = HTMLReportGenerator(specLink: specFileName).generate(from: result)
        let spec = SpecPageGenerator(title: specTitle, reportLink: reportFileName).generate(from: result)
        return (report, spec)
    }

    /// Writes both pages, cross-linked by their basenames, creating
    /// directories as needed.
    public func write(
        result: TestRunResult,
        reportPath: String,
        specPath: String
    ) throws {
        let reportName = (reportPath as NSString).lastPathComponent
        let specName = (specPath as NSString).lastPathComponent
        let pages = generate(from: result, reportFileName: reportName, specFileName: specName)
        try writeString(pages.report, to: reportPath)
        try writeString(pages.spec, to: specPath)
    }

    private func writeString(_ html: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Derives a sibling spec path from a report path: `PICKLE_SPEC_PATH` if
    /// set, else the report's directory with `report`→`spec` in the name.
    public static func defaultSpecPath(forReport reportPath: String,
                                       override: String? = nil) -> String {
        if let override {
            return override.hasPrefix("/") ? override
                : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(override)
        }
        let dir = (reportPath as NSString).deletingLastPathComponent
        let reportName = (reportPath as NSString).lastPathComponent
        let specName = reportName.contains("report")
            ? reportName.replacingOccurrences(of: "report", with: "spec") : "spec-\(reportName)"
        return (dir as NSString).appendingPathComponent(specName)
    }
}
