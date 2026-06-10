# HTML Report Configuration

PickleKit generates Cucumber-style HTML reports with per-step results, timing, and status filtering. This document covers configuration options, xcodebuild integration, the report's interactive features, theming, and programmatic report generation.

## Interactive features

The report is a single self-contained HTML file (inline CSS + JS, no external assets) with:

- **Collapsible features** — each feature is a `<details>` (open by default); click its header to fold the whole block. Scenarios collapse independently (failed ones open automatically).
- **Scenario Outline grouping** — the examples expanded from one `Scenario Outline` collapse under a single header (the outline's name + an `outline · N` count badge), so a run of cases reads as one family instead of N look-alike rows. Groups are collapsed by default; a group containing a failing example opens automatically. The individual cases keep their own anchors, so deep links still resolve.
- **Outline rail** — a persistent sticky left rail lists every feature with a status dot and scroll-spy (the current feature highlights as you scroll); clicking jumps to it. The same rail component appears on the living-spec page, so the two read as one product.
- **Status filtering** — the All / Passed / Skipped / Failed buttons, plus Expand All / Collapse All.

### Two views: report and living specification

A `ReportSuite` renders one run as a cohesive pair — the **report** (this audit view) and a **living specification** (`SpecPageGenerator`): the same features as Given/When/Then prose, marked verified, for reading rather than auditing. They share one palette, one summary of counts, one anchor scheme, and the same outline rail, and they cross-link (the report's "Read it as a specification", the spec's "View the full test report"). When `PICKLE_REPORT` is set, both are written — the report to `PICKLE_REPORT_PATH` and the spec beside it (override with `PICKLE_SPEC_PATH`, title with `PICKLE_SPEC_TITLE`). The spec page is itself standalone-valid (a `SpecPageGenerator` with no report link omits the drill-downs).

## Theming

The report is themeable and ships **four palettes** out of the box: `light` (Solarized Light) and `dark` (Dracula) — the same palette as the [Soroban](https://github.com/alleato-llc/soroban) landing page, so a generated report can be dropped straight onto a site — plus `nord` and `gruvbox`, included to show that re-skinning is one block.

- **How it's switched:** a `data-theme` attribute on `<html>` selects a block of CSS custom properties. The **◐** button in the report header toggles between `light` and `dark`.
- **Deep-linking a palette:** append `?theme=<id>` to any report or spec URL (`report.html?theme=nord`). The pre-paint script honors it over the remembered/OS choice, so a hosted page can be pinned to a specific look — that's how the README's re-skinned screenshots are produced.
- **First paint:** an inline `<script>` in `<head>` runs before render — it resolves the theme as `?theme=` → a remembered choice in `localStorage` (`pickle-theme`) → the OS preference via `prefers-color-scheme`. So there's no flash, and a returning viewer keeps their choice.
- **The palettes** live in `ReportShared.themes` as a list of `ReportTheme` values; `paletteCSS()` renders each to a `:root[data-theme="…"]` block of variables (`--bg`, `--surface`, `--text`, `--muted`, `--faint`, `--accent`, `--error`, `--border`, `--shadow`, and status colours `--passed`/`--failed`/`--skipped`/`--undefined`). **To add a theme, append one entry** — everything else (cards, badges, progress bars, the sidebar) is expressed in terms of those tokens, so nothing else changes. To match a different design system, copy its colour tokens into a new `ReportTheme`.

> The report and spec HTML is assembled with [Kumi](https://github.com/alleato-llc/kumi), a small dependency-free HTML builder — so the markup is auto-escaped and the structure is built as a node tree rather than concatenated strings.

## Hosted demo

A live report + living spec, regenerated on every push, is published to GitHub Pages: **[alleato-llc.github.io/pickle-kit](https://alleato-llc.github.io/pickle-kit/)** (the spec is the front door; the report is one click away). It's PickleKit's own cucumber feature fixtures — run in one deterministic pass by `GherkinIntegrationTests` (`swift test --filter GherkinIntegrationTests` with `PICKLE_REPORT`) — so it shows real Given/When/Then scenarios across tags, doc strings, a data table, and a grouped scenario outline. The pipeline also publishes the report in all four palettes as **standalone theme-pinned pages** (`report-dark.html`, `report-nord.html`, `report-gruvbox.html` — copies of `report.html` with the pre-paint's `forced` value hard-set, so they ignore the query string, `localStorage`, and the OS preference), each with its own screenshot (`report{,-dark,-nord,-gruvbox}.png`). The README's showcase links those distinct pages, so each opens a genuinely different report; the images are generated here, never committed, so they always match.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `PICKLE_REPORT` | *(unset = off)* | Set to any value to enable report generation |
| `PICKLE_REPORT_PATH` | `pickle-report.html` | Output file path (ineffective for sandboxed UI test runners — see note below) |

Subclasses of `GherkinTestCase` can also override these as class properties for compile-time control:

```swift
final class MyTests: GherkinTestCase {
    override class var reportEnabled: Bool { true }
    override class var reportOutputPath: String { "build/my-report.html" }
}
```

## Reports with xcodebuild

`xcodebuild` does not pass shell environment variables to the test runner process. For Xcode projects (including the Example TodoApp), use one of these approaches:

**Subclass override (recommended for CI):**

```swift
final class MyTests: GherkinTestCase {
    override class var reportEnabled: Bool { true }
    override class var reportOutputPath: String { "pickle-report.html" }
}
```

**Scheme environment variables (Xcode GUI):**

1. Edit your scheme → Test → Arguments → Environment Variables
2. Add `PICKLE_REPORT` = `1` and optionally `PICKLE_REPORT_PATH`
3. These are stored in the `.xcscheme` file and passed to the test runner

If using xcodegen, add to `project.yml`:

```yaml
schemes:
  MyScheme:
    test:
      environmentVariables:
        - variable: PICKLE_REPORT
          value: "1"
          isEnabled: true
```

**Note:** UI test runners (`.xctrunner` bundles) are sandboxed and cannot write to arbitrary paths. `PICKLE_REPORT_PATH` is ineffective in this context — the OS blocks writes to user-specified paths regardless. PickleKit falls back to `NSTemporaryDirectory()` inside the sandbox container (`~/Library/Containers/<bundle-id>.xctrunner/Data/tmp/`). The actual path is printed to stderr.

## Programmatic Report Generation

You can generate reports without XCTest using the `HTMLReportGenerator` directly:

```swift
import PickleKit

let result = TestRunResult(
    featureResults: [featureResult],
    startTime: startTime,
    endTime: Date()
)

let generator = HTMLReportGenerator()
try generator.write(result: result, to: "report.html")
```

Or collect results incrementally with `ReportResultCollector`:

```swift
let collector = ReportResultCollector()

// After each scenario runs:
collector.record(
    scenarioResult: result,
    featureName: feature.name,
    featureTags: feature.tags,
    sourceFile: feature.sourceFile
)

// When finished:
let testRunResult = collector.buildTestRunResult()
let generator = HTMLReportGenerator()
try generator.write(result: testRunResult, to: "report.html")
```
