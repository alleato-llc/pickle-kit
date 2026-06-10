# Claude Code Instructions for PickleKit

## Project Overview

PickleKit is a standalone Swift Cucumber/BDD testing framework. It provides a Gherkin parser, step registry, scenario runner, and bridges for both Swift Testing and XCTest. The report/spec markup is assembled with [Kumi](https://github.com/alleato-llc/kumi), a tiny dependency-free HTML builder. Requires Swift 6.2+ (swift-tools-version 6.2).

## Architecture

### Package Structure

```
Sources/PickleKit/
├── AST/
│   └── GherkinAST.swift          # All model types (Feature, Scenario, Step, etc.)
├── Parser/
│   ├── GherkinParser.swift       # Line-by-line state machine Gherkin parser
│   └── OutlineExpander.swift     # Scenario Outline → concrete Scenario expansion
├── Report/
│   ├── StepResult.swift          # StepStatus enum + StepResult per-step execution data
│   ├── TestRunResult.swift       # Aggregated test run results with computed counts
│   ├── HTMLReportGenerator.swift # Self-contained HTML report (built with Kumi)
│   ├── SpecPageGenerator.swift   # The living-specification page (Given/When/Then prose)
│   ├── ReportSuite.swift         # Renders/writes the report + spec pair, cross-linked
│   ├── ReportShared.swift        # Shared chrome: palette, rail, summary, outline grouping
│   └── ReportResultCollector.swift # Thread-safe result accumulator (OSAllocatedUnfairLock)
├── Runner/
│   ├── StepRegistry.swift        # Regex pattern → async closure mapping
│   ├── StepDefinitions.swift     # StepDefinition struct, StepDefinitions protocol, StepDefinitionFilter
│   ├── ScenarioRunner.swift      # Executes scenarios against registry
│   ├── TagFilter.swift           # Include/exclude tag filtering
│   └── ScenarioNameFilter.swift  # Filter scenarios by name (CUCUMBER_SCENARIOS env var)
├── SwiftTestingBridge/
│   └── GherkinTestScenario.swift # Swift Testing bridge via @Test(arguments:)
└── XCTestBridge/
    └── GherkinTestCase.swift     # XCTestCase subclass with dynamic test generation
```

### Key Design Decisions

- **Dependencies** — Foundation, Testing (Swift Testing), XCTest (implicit for test targets), and [Kumi](https://github.com/alleato-llc/kumi), a tiny HTML builder. The report/spec generators assemble markup as a Kumi node tree (auto-escaped, auto-closed) rather than concatenated strings. Because the XCTest bridge lives in the same module, the generators can't be used from a plain executable (it'd fail to load `libXCTestSwiftSupport`) — generate reports via `swift test` + `PICKLE_REPORT`, which is the supported path.
- **Scenario Outline grouping in reports** — `OutlineExpander` tags each expanded `Scenario` with `outlineName`/`exampleLabel`, threaded into `ScenarioResult`. The report/spec fold consecutive same-outline cases under one collapsible header (name + `outline · N`), via `ReportShared.segments(_:)`. Collapsed by default; a group with a failure opens; per-scenario anchors are preserved. `.github/workflows/pages.yml` generates the report+spec on every push from the cucumber feature fixtures — run by `GherkinIntegrationTests` in one deterministic pass (`swift test --filter GherkinIntegrationTests` with `PICKLE_REPORT`), NOT as a side effect of the whole 253-test suite (which would capture an arbitrary auto-collected slice). Those scenarios all pass, so the step is honestly gated (no `|| true`). It then screenshots the pages — the spec, plus the report in three of its palettes via `?theme=` (`report{,-nord,-gruvbox}.png`) — and deploys to GitHub Pages ([alleato-llc.github.io/pickle-kit](https://alleato-llc.github.io/pickle-kit/)); the README's report screenshots are produced there, never committed.
- **Report theming** — `ReportShared.themes` is a list of `ReportTheme` (id, label, CSS-variable body); `paletteCSS()` emits one `:root[data-theme="…"]` block each. Ships `light`/`dark` (the ◐-toggle + OS-preference pair) plus `nord`/`gruvbox` (re-skinning showcase). The pre-paint script resolves `?theme=<id>` → `localStorage` → `prefers-color-scheme`, so a hosted page can be pinned to a palette. Add a theme = append one entry; every component reads the tokens.
- **All AST types are `Sendable` and `Equatable`** — value types throughout
- **`StepRegistry` is instance-based** (not singleton) for testability
- **`StepHandler` is `@MainActor @Sendable (StepMatch) async throws -> Void`** — async/await compatible, isolated to `@MainActor` so handlers safely use XCTest assertions and UI frameworks
- **`GherkinTestCase` uses ObjC runtime** (`class_addMethod`, `unsafeBitCast`) to create dynamic test methods since `XCTestCase.init(selector:)` is unavailable in Swift. **Important:** `XCTestSuite(forTestCaseClass:)` must be called *after* all `class_addMethod` calls — it discovers `test_*` methods via ObjC reflection. Creating the suite first and then adding methods produces duplicate entries that can crash Xcode's result bundle builder.
- **`DataTable.dataRows` always drops the first row** — it assumes the first row is a header. All data tables used with `dataRows` must include an explicit header row (e.g., `| title |`). Tables without a header will silently lose the first data row.
- **Per-class scenario maps** — `GherkinTestCase` stores scenario data in a dictionary keyed by `ObjectIdentifier(self)` so multiple subclasses (and the base class itself when discovered by XCTest) don't overwrite each other's data
- **`GherkinParser` is a line-by-line state machine** with states: idle → inFeature → inBackground/inScenario/inOutline/inExamples/inDocString
- **Conditional compilation** — `GherkinTestCase` is wrapped in `#if canImport(XCTest) && canImport(ObjectiveC)`
- **Reflection-based step registration** — `StepDefinitions` protocol uses `Mirror` to auto-discover stored `StepDefinition` properties. `GherkinTestCase.stepDefinitionTypes` enables declaring step providers per subclass. Type-based providers are registered before `registerStepDefinitions()`, so both approaches coexist.
- **Two test bridges** — `GherkinTestScenario` for Swift Testing (`@Test(arguments:)`), `GherkinTestCase` for XCTest (UI tests, legacy). Both use the same `StepDefinitions` types. `ScenarioDefinition` has `asScenario`/`asOutline` convenience accessors for cleaner pattern matching in tests.
- **XCTAssert failure detection** — `GherkinTestCase.executeScenario()` snapshots `testRun.totalFailureCount` before running each scenario. If `ScenarioRunner` reports the scenario as passing but XCTest recorded new assertion failures (from `XCTAssert*` calls in step handlers), the result is corrected to `passed: false` before recording to the `ReportResultCollector`. This bridges the gap where XCTAssert failures don't throw and are invisible to `ScenarioRunner`. The `XCTestAssertionError` type wraps the failure count for error reporting.
- **Skipped scenario tracking** — `ScenarioResult` has a `skipped: Bool` property (default `false`). When tag or name filters exclude a scenario, all three filtering locations (`ScenarioRunner.run(feature:)`, `GherkinTestScenario.buildScenarios()`, `GherkinTestCase.defaultTestSuite`) record a `ScenarioResult(passed: true, skipped: true)` instead of silently omitting it. `FeatureResult.passedCount`/`failedCount`/`allPassed` exclude skipped scenarios; `skippedCount` counts them. The HTML report renders skipped scenarios with a `status-skipped` badge and provides a "Skipped" filter button.

### Platforms

macOS 14+, iOS 17+, tvOS 17+, watchOS 10+

## Code Organization

| File | Purpose |
|------|---------|
| `GherkinAST.swift` | Feature, ScenarioDefinition, Scenario, ScenarioOutline, Background, Step, StepKeyword, DataTable, ExamplesTable |
| `GherkinParser.swift` | Parses Gherkin source text/files/bundles into Feature AST |
| `OutlineExpander.swift` | Expands ScenarioOutline + Examples into concrete Scenarios |
| `StepRegistry.swift` | StepMatch, StepHandler, StepRegistryError, StepRegistry |
| `StepDefinitions.swift` | StepDefinition (declarative step), StepDefinitions protocol (Mirror-based discovery), StepDefinitionFilter (env var filtering) |
| `ScenarioRunner.swift` | ScenarioRunnerError, ScenarioResult, FeatureResult, ScenarioRunner |
| `TagFilter.swift` | Include/exclude filtering on tag arrays |
| `ScenarioNameFilter.swift` | Filter scenarios by name via `CUCUMBER_SCENARIOS` env var |
| `GherkinTestScenario.swift` | Swift Testing bridge: `@Test(arguments:)` parameterized scenarios, auto-report via `PICKLE_REPORT` |
| `GherkinTestCase.swift` | XCTestCase subclass, dynamic test suite via ObjC runtime, report integration, XCTAssert failure detection |
| `StepResult.swift` | StepStatus enum, StepResult per-step execution data |
| `TestRunResult.swift` | Aggregated test run result with feature/scenario/step counts |
| `HTMLReportGenerator.swift` | Self-contained HTML report generator with inline CSS/JS |
| `ReportResultCollector.swift` | Thread-safe result accumulator using OSAllocatedUnfairLock |
| `GherkinIntegrationTests.swift` | Swift Testing suite using `GherkinTestScenario` to run all fixture features |
| `GherkinTestScenarioTests.swift` | Swift Testing bridge tests: loading, filtering, execution, properties, error reporting |
| `GherkinTestCaseTests.swift` | XCTest bridge tests: dynamic suites, tag filtering, isolation, registry, XCTAssert failure detection |
| `ReportIntegrationTests.swift` | End-to-end reporting: runner → collector → HTML, tag filtering in reports |

## Testing

See [docs/TESTING.md](docs/TESTING.md) for test design philosophy, the BDD rationale, testing trophy guidance, and UI test best practices. See [docs/BDD_GUIDE.md](docs/BDD_GUIDE.md) for conventions on writing feature files, step definitions, and runners. See [docs/SETUP.md](docs/SETUP.md) for adopting these conventions in other projects.

```bash
# PickleKit library tests
swift test                                     # Run all tests
swift test --filter ParserTests                # Parser tests only
swift test --filter StepRegistryTests          # Registry tests only
swift test --filter ScenarioRunnerTests        # Runner tests only
swift test --filter StepResultTests            # Step result/timing tests
swift test --filter HTMLReportGeneratorTests    # Report generation tests
swift test --filter StepDefinitionsTests        # Step definitions struct/protocol/filter tests
swift test --filter ScenarioNameFilterTests     # Scenario name filter tests
swift test --filter GherkinIntegrationTests    # Full pipeline integration tests
swift test --filter GherkinTestScenarioTests   # Swift Testing bridge tests
swift test --filter GherkinTestCaseTests        # XCTest bridge tests
swift test --filter ReportIntegrationTests      # End-to-end reporting tests
PICKLE_REPORT=1 swift test                     # Run tests + generate HTML report

# TodoApp tests (from Example/TodoApp/, requires xcodegen generate first)
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppTests 2>&1 | xcbeautify      # Unit tests
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppUITests 2>&1 | xcbeautify     # UI tests
```

### Test Structure

```
Tests/PickleKitTests/
├── ParserTests.swift                  # Gherkin parsing: features, scenarios, steps, tables, doc strings, tags, errors
├── OutlineExpanderTests.swift         # Outline expansion: substitution, naming, tag combination, edge cases
├── StepRegistryTests.swift            # Pattern matching: regex captures, ambiguity, anchoring, data passthrough
├── ScenarioRunnerTests.swift          # Execution: passing/failing scenarios, backgrounds, tag filtering, captures
├── TagFilterTests.swift               # Include/exclude logic, priority, edge cases
├── ScenarioNameFilterTests.swift     # Scenario name filtering, env var parsing, merging
├── StepResultTests.swift              # Step-level results: status, timing, tags, undefined/skipped, backward compat
├── StepDefinitionsTests.swift         # StepDefinition struct, StepDefinitions protocol, Mirror discovery, filter
├── HTMLReportGeneratorTests.swift     # HTML generation: structure, counts, CSS classes, escaping, collector, aggregations
├── GherkinIntegrationTests.swift      # Full pipeline: domain step types + GherkinTestScenario
├── GherkinTestScenarioTests.swift     # Swift Testing bridge: loading, filtering, execution, properties, auto-report, error reporting
├── GherkinTestCaseTests.swift         # XCTest bridge: dynamic suites, tag filtering, isolation, registry, XCTAssert failure detection
├── ReportIntegrationTests.swift       # End-to-end: runner → collector → HTML, tag filtering, error/undefined/mixed scenarios
└── Fixtures/                          # .feature files loaded via Bundle.module
    ├── basic.feature
    ├── with_background.feature
    ├── with_outline.feature
    ├── with_tables.feature
    ├── with_docstrings.feature
    └── with_tags.feature
```

Fixtures are copied into the test bundle via `resources: [.copy("Fixtures")]` in Package.swift. Access them with `Bundle.module.url(forResource:withExtension:subdirectory:"Fixtures")`.

### Test Patterns

All library tests use Swift Testing (`import Testing`). Tests use `@Suite struct`, `@Test func`, `#expect()`, and `try #require()`. `GherkinTestCaseTests` additionally imports `XCTest` for type access and defines `GherkinTestCase` helper subclasses that are auto-discovered by XCTest at runtime (wrapped in `#if canImport(XCTest) && canImport(ObjectiveC)`).

```swift
// Parser tests load fixtures
private func loadFixture(_ name: String) throws -> Feature {
    let url = Bundle.module.url(forResource: name, withExtension: "feature", subdirectory: "Fixtures")!
    let source = try String(contentsOf: url, encoding: .utf8)
    return try parser.parse(source: source, fileName: "\(name).feature")
}

// Runner tests use mock step handlers
registry.given("a setup") { _ in log.value.append("given") }
let result = try await runner.run(scenario: scenario)
#expect(result.passed)

// Registry tests check matching
let result = try registry.match(step)
#expect(result?.match.captures == ["42", "apples"])

// Unwrapping ScenarioDefinition with convenience accessors
let scenario = try #require(feature.scenarios[0].asScenario)
let outline = try #require(feature.scenarios[0].asOutline)

// Mutable state in @Sendable closures uses TestBox (class-based, @unchecked Sendable)
let box = TestBox(false)
registry.given("I do something") { _ in box.value = true }
// ... run scenario ...
#expect(box.value)

// Tests that modify environment variables use @Suite(.serialized) + defer cleanup

// Bridge tests: GherkinTestScenario (Swift Testing bridge)
// Count-sensitive tests parse features directly to bypass TagFilter.fromEnvironment(),
// which races with TagFilterTests setting CUCUMBER_TAGS concurrently.
let parser = GherkinParser()
let features = try parser.parseBundle(bundle: Bundle.module, subdirectory: "Fixtures")
let expander = OutlineExpander()
var scenarios: [GherkinTestScenario] = []
for feature in features {
    let expanded = expander.expand(feature)
    for definition in expanded.scenarios {
        guard case .scenario(let scenario) = definition else { continue }
        scenarios.append(GherkinTestScenario(scenario: scenario, background: expanded.background, feature: feature))
    }
}
#expect(scenarios.count == 13)
let result = try await scenarios[0].run(stepDefinitions: [ArithmeticSteps.self])
#expect(result.passed)

// Bridge tests: GherkinTestCase (XCTest bridge) via helper subclasses
// Helper subclasses defined at file scope are auto-discovered by XCTest,
// providing implicit integration testing for the XCTest bridge pipeline.
// Count assertions use direct parsing (not defaultTestSuite) to avoid
// the same env var race condition.
final class BasicBridgeTestCase: GherkinTestCase {
    override class var featurePaths: [String]? { fixturePath("basic").map { [$0] } }
    override class var stepDefinitionTypes: [any StepDefinitions.Type] { [ArithmeticSteps.self] }
}
#expect(BasicBridgeTestCase.stepDefinitionTypes.count == 1)
#expect(BasicBridgeTestCase.featurePaths?.count == 1)
```

## Common Tasks

### Adding a new Gherkin keyword

1. If it's a step keyword, add to `StepKeyword` enum in `GherkinAST.swift`
2. Update `parseStepKeyword()` in `GherkinParser.swift`
3. Add test coverage in `ParserTests.swift`

### Adding a new AST node type

1. Add the struct/enum to `GherkinAST.swift` — make it `public`, `Sendable`, `Equatable`
2. Update `GherkinParser` to populate it during parsing
3. Update `OutlineExpander` if it participates in outline expansion
4. Add tests

### Adding parser support for a new construct

1. Add a new `ParseMode` case if it requires state tracking
2. Add a handler method (`handleXxxKeyword`)
3. Update `processLine()` to detect the keyword
4. Update `finalizeCurrentScenario()` / `finalizeState()` if needed
5. Create a fixture `.feature` file and add parser tests

### Adding a step definition type

1. Create a struct conforming to `StepDefinitions` in a test file
2. Declare steps as stored `let` properties using `StepDefinition.given/when/then/step`
3. Own static state in `nonisolated(unsafe) static var` properties, reset in `init()`
4. Add the type to `stepDefinitions` in `GherkinTestScenario.run()` (Swift Testing) or `stepDefinitionTypes` in a `GherkinTestCase` subclass (XCTest)
5. Error types thrown from step handlers should conform to `LocalizedError` (not just `CustomStringConvertible`), so `localizedDescription` returns the human-readable message in CLI output and HTML reports
6. Test with `StepDefinitionsTests` patterns

### Modifying step matching behavior

1. Changes go in `StepRegistry.swift`
2. The `match(_ step:)` method does full-string anchored regex matching
3. Patterns are stored as `^pattern$` — modify `register()` to change anchoring
4. Test with `StepRegistryTests`

## Key Patterns

```swift
// Parse from string
let parser = GherkinParser()
let feature = try parser.parse(source: gherkinText, fileName: "test.feature")

// Parse from bundle
let features = try parser.parseBundle(bundle: .module, subdirectory: "Features")

// Expand outlines
let expander = OutlineExpander()
let expanded = expander.expand(feature)

// Register and run
let registry = StepRegistry()
registry.given("pattern with (\\d+) captures") { match in
    let value = match.captures[0]
    let table = match.dataTable     // Optional DataTable
    let doc = match.docString       // Optional String
}

let runner = ScenarioRunner(registry: registry)
let result = try await runner.run(feature: expanded, tagFilter: TagFilter(excludeTags: ["wip"]))

// CLI tag filtering via environment variables (merged with compile-time tagFilter)
// CUCUMBER_TAGS=smoke,critical swift test
// CUCUMBER_EXCLUDE_TAGS=wip,slow swift test
let envFilter = TagFilter.fromEnvironment()        // reads CUCUMBER_TAGS / CUCUMBER_EXCLUDE_TAGS
let merged = existingFilter.merging(envFilter!)     // unions include and exclude sets

// CLI scenario name filtering (case-insensitive, comma-separated)
// CUCUMBER_SCENARIOS="Addition,Subtraction" swift test
// With xcodebuild, use TEST_RUNNER_ prefix:
// TEST_RUNNER_CUCUMBER_SCENARIOS="Addition" xcodebuild test ...
let nameFilter = ScenarioNameFilter.fromEnvironment()  // reads CUCUMBER_SCENARIOS

// Declarative step definitions (type-based, Mirror-discovered)
struct ArithmeticSteps: StepDefinitions {
    nonisolated(unsafe) static var number: Int = 0
    init() { Self.number = 0 }  // reset per-scenario

    let givenNumber = StepDefinition.given("I have the number (\\d+)") { match in
        Self.number = Int(match.captures[0])!
    }
    let addNumber = StepDefinition.when("I add (\\d+)") { match in
        Self.number += Int(match.captures[0])!
    }
}

// Swift Testing bridge (preferred for library/unit tests)
// PICKLE_REPORT=1 auto-collects results when no explicit reportCollector is passed.
import Testing
import PickleKit

@Suite(.serialized) struct MyTests {
    static let allScenarios = GherkinTestScenario.scenarios(
        bundle: .module, subdirectory: "Features"
    )

    @Test(arguments: MyTests.allScenarios)
    func scenario(_ test: GherkinTestScenario) async throws {
        let result = try await test.run(stepDefinitions: [ArithmeticSteps.self])
        #expect(result.passed)
    }
}

// XCTest bridge (for UI tests with XCUITest)
final class MyUITests: GherkinTestCase {
    override class var stepDefinitionTypes: [any StepDefinitions.Type] {
        [ArithmeticSteps.self]
    }
}

// Compile-time scenario name filter (XCTest bridge)
final class MyFilteredUITests: GherkinTestCase {
    override class var scenarioNameFilter: ScenarioNameFilter? {
        ScenarioNameFilter(names: ["My specific scenario"])
    }
}

// Filter step definition types via environment variable
// CUCUMBER_STEP_DEFINITIONS="ArithmeticSteps,CartSteps" swift test
```

## HTML Report Generation

PickleKit generates Cucumber-style HTML reports with step-level results, timing, and interactive filtering.

### How It Works

1. `ScenarioRunner.run()` captures per-step timing and builds `[StepResult]` arrays — each step gets `.passed`, `.failed`, `.undefined`, or `.skipped` status. Error messages include the scenario name for traceability.
2. Both bridges auto-collect results when `PICKLE_REPORT` is set:
   - **XCTest bridge:** `GherkinTestCase.executeScenario()` records each `ScenarioResult` into a shared `ReportResultCollector`. It also detects XCTAssert failures that didn't throw (see Key Design Decisions) and corrects the result to `passed: false` before recording.
   - **Swift Testing bridge:** `GherkinTestScenario.run()` auto-collects into its own shared `resultCollector` when no explicit collector is passed
3. Reports are written via `atexit` handlers (both bridges). `GherkinTestCase` additionally writes from `class func tearDown()` — this ensures reports work under `xcodebuild` where the test runner may be killed before `atexit` fires
4. `HTMLReportGenerator.write(result:to:)` creates intermediate directories automatically — `build/report.html` works even if `build/` doesn't exist
5. Each bridge maintains its own `ReportResultCollector`. When both bridges run in the same process, each writes its report (last write wins for the same output path)

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `PICKLE_REPORT` | *(unset = off)* | Set to any value to enable |
| `PICKLE_REPORT_PATH` | `pickle-report.html` | Output file path (ineffective for sandboxed UI test runners) |

Both bridges (`GherkinTestCase` and `GherkinTestScenario`) honor these env vars. `swift test` passes env vars to the test process directly, so this works for both XCTest and Swift Testing suites:

```bash
PICKLE_REPORT=1 swift test
PICKLE_REPORT=1 PICKLE_REPORT_PATH=build/report.html swift test
```

`GherkinTestCase` subclasses can override `reportEnabled` / `reportOutputPath` class properties for compile-time control. `GherkinTestScenario` exposes `reportEnabled` and `reportOutputPath` as static read-only properties.

### Key Types

| Type | Purpose |
|------|---------|
| `StepStatus` | Enum: `.passed`, `.failed`, `.skipped`, `.undefined` |
| `StepResult` | Per-step data: keyword, text, status, duration, error, sourceLine |
| `TestRunResult` | Aggregated results with computed counts for features/scenarios/steps |
| `HTMLReportGenerator` | Generates self-contained HTML with inline CSS/JS |
| `ReportResultCollector` | Thread-safe accumulator using `OSAllocatedUnfairLock` |
| `XCTestAssertionError` | Error wrapping XCTAssert failures detected by `GherkinTestCase` (XCTest bridge only) |

### Enriched Result Types

`ScenarioResult` and `FeatureResult` have additional fields (all with defaults for backward compatibility):

- **ScenarioResult**: `skipped: Bool` (default `false`), `tags: [String]`, `stepResults: [StepResult]`, `duration: TimeInterval`
- **FeatureResult**: `tags: [String]`, `sourceFile: String?`, `duration: TimeInterval`, plus computed scenario counts (`passedCount`, `failedCount`, `skippedCount` — skipped excluded from passed/failed), and computed step counts (`totalStepCount`, `passedStepCount`, `failedStepCount`, `skippedStepCount`, `undefinedStepCount`)

### Programmatic Usage

```swift
// Direct generation from known results
let result = TestRunResult(featureResults: [...], startTime: start, endTime: Date())
let generator = HTMLReportGenerator()
try generator.write(result: result, to: "report.html")

// Incremental collection (explicit)
let collector = ReportResultCollector()
collector.record(scenarioResult: result, featureName: "Login", featureTags: ["auth"])
let testRun = collector.buildTestRunResult()

// Auto-collection via PICKLE_REPORT env var (Swift Testing bridge)
// When PICKLE_REPORT is set and no explicit collector is passed,
// GherkinTestScenario.run() auto-collects into the shared collector.
let result = try await test.run(stepDefinitions: [MySteps.self])
// Access shared collector programmatically:
let sharedRun = GherkinTestScenario.resultCollector.buildTestRunResult()
```

## CI/CD

### GitHub Actions

- **ci.yml** — Runs on push to `main`/`feature/*` and PRs to `main`. Three jobs:
  - **unit-tests**: Runs PickleKit `swift test` (with coverage) and TodoApp `xcodebuild -only-testing:TodoAppTests`. Publishes JUnit report via dorny/test-reporter.
  - **ui-tests**: Depends on `unit-tests`. Runs TodoApp `xcodebuild -only-testing:TodoAppUITests` (requires GUI session).
  - **build**: Depends on `unit-tests`. Validates release build (`swift build -c release`).
  - Dependency graph: `unit-tests` gates both `ui-tests` and `build` (which run in parallel).
  - Requires `permissions: checks: write` for test reporting.
- **release.yml** — Triggered after successful CI on `main`. Uses release-please for changelog and version tagging.

### Test Reporting

CI generates `junit.xml` via `swift test --xunit-output junit.xml`. The report is published by `dorny/test-reporter@v1` with `fail-on-error: false`.

### Release Process

See [docs/RELEASE.md](docs/RELEASE.md) for full documentation on conventional commits, release-please, and troubleshooting.

### Running CI locally

```bash
# PickleKit library
swift build                                            # Debug build
swift test                                             # Run tests
swift build -c release                                 # Release build
PICKLE_REPORT=1 swift test                             # Run tests + generate HTML report
PICKLE_REPORT=1 PICKLE_REPORT_PATH=build/report.html swift test  # Custom report path

# TodoApp (from Example/TodoApp/)
xcodegen generate                                      # Generate .xcodeproj
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppTests 2>&1 | xcbeautify      # Unit tests
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppUITests 2>&1 | xcbeautify     # UI tests
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' 2>&1 | xcbeautify                                  # All tests
```

## Example App

The `Example/TodoApp/` directory contains a macOS SwiftUI todo app demonstrating PickleKit with XCUITest.

### Structure

```
Example/TodoApp/
├── project.yml                    # xcodegen spec (generates .xcodeproj)
├── Sources/TodoApp/               # SwiftUI app
│   ├── TodoApp.swift              # @main entry, Window scene, onOpenURL handler
│   ├── ContentView.swift          # Todo list UI with accessibility identifiers
│   ├── TodoItem.swift             # Identifiable model struct
│   ├── TodoStore.swift            # @Observable store: add, remove, update, clear, toggle
│   └── Info.plist                 # App configuration (URL scheme: todoapp://)
├── Tests/
│   └── TodoStoreTests.swift       # Unit tests for TodoStore (no UI dependency)
└── UITests/
    ├── Features/                  # 3 Gherkin feature files
    ├── Steps/
    │   ├── TodoSetupSteps.swift       # Given steps (app launch, empty list, seed data)
    │   ├── TodoActionSteps.swift      # When steps (enter text, tap, edit, delete, toggle)
    │   └── TodoVerificationSteps.swift # Then steps (assertions on text, count, state)
    ├── TodoWindow.swift               # Page object: element accessors + UI actions
    └── TodoUITests.swift              # GherkinTestCase subclass (config only)
```

### Running

```bash
cd Example/TodoApp
xcodegen generate
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' 2>&1 | xcbeautify              # All tests
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppTests 2>&1 | xcbeautify       # Unit tests only
xcodebuild test -project TodoApp.xcodeproj -scheme TodoApp -destination 'platform=macOS' -only-testing:TodoAppUITests 2>&1 | xcbeautify     # UI tests only
```

### HTML Reports with xcodebuild

`xcodebuild` does **not** pass shell environment variables (like `PICKLE_REPORT=1`) to the test runner process. Use one of these approaches instead:

1. **Subclass override** (most reliable): override `reportEnabled` / `reportOutputPath` in `TodoUITests.swift`
2. **Scheme env vars**: `project.yml` includes `PICKLE_REPORT` and `PICKLE_REPORT_PATH` variables. Set `isEnabled: true`/`false` in `project.yml` and re-run `xcodegen generate`, or toggle in Xcode's scheme editor

**Sandbox limitation:** UI test runners (`.xctrunner`) are sandboxed and cannot write to arbitrary paths. `PICKLE_REPORT_PATH` is ineffective in this context — the OS blocks all user-specified paths. PickleKit falls back to `NSTemporaryDirectory()` (the sandbox's temp dir). The actual output path is printed to stderr.

**TodoApp sandbox report path:**
```
~/Library/Containers/com.picklekit.example.todoapp.uitests.xctrunner/Data/tmp/pickle-report.html
```

```bash
# Open the report after running tests
open ~/Library/Containers/com.picklekit.example.todoapp.uitests.xctrunner/Data/tmp/pickle-report.html

# Full sandbox cleanup
rm -rf ~/Library/Containers/com.picklekit.example.todoapp.uitests.xctrunner/
```

**Report writing mechanism:** Reports are written from both `class func tearDown()` (after each `GherkinTestCase` subclass finishes) and an `atexit` handler. The `class func tearDown()` ensures reports are generated even when `xcodebuild` terminates the test runner before `atexit` fires.

### Test Framework Split

- **`TodoStoreTests`** uses Swift Testing (`import Testing`, `@Suite struct`, `@Test func`, `#expect`). Unit tests have no UI dependency and work with Swift Testing.
- **`TodoAppUITests`** uses XCTest (`import XCTest`, `GherkinTestCase`). Xcode blocks `import Testing` in `bundle.ui-testing` targets via `TESTING_FRAMEWORK_MODULE_ALIAS_FLAGS = -module-alias Testing=_Testing_Unavailable`. This is an Xcode-imposed limitation — UI test bundles cannot use the Swift Testing framework.
- **Step handler assertions** use `XCTAssertTrue`, `XCTAssertEqual`, `XCTAssertFalse` directly (not `guard/throw`). This works because `StepHandler` is `@MainActor` and XCTest is the active test runtime in the UI test bundle. XCTest assertion failures are recorded on the current `XCTestCase` instance automatically. `GherkinTestCase` detects these non-throwing failures via `testRun.totalFailureCount` and corrects the `ScenarioResult` for accurate HTML reports.

### Key Patterns

- **`@Observable TodoStore`** — Extracted store for testability. `@State` in `App`, plain `var` in `ContentView`. Enables `TodoStoreTests` without UI.
- **`Window` instead of `WindowGroup`** — Prevents duplicate windows from URL handling. `WindowGroup` creates a new window per `onOpenURL` event.
- **`todoapp://seed` URL scheme** — Bypasses UI for fast, deterministic test setup. `onOpenURL` handler calls `store.clear()` + `store.add(titles:)` from JSON query parameter.
- **`nonisolated(unsafe) static var app: XCUIApplication!`** — XCUIApplication isn't Sendable, but StepHandler requires @Sendable closures. Safe because XCUITest runs sequentially. Stored on `TodoWindow` (the page object) rather than on the test class.
- **Page Object pattern** — `TodoWindow` encapsulates all element accessors and UI actions. Step definitions delegate to `TodoWindow` methods, keeping step handler bodies minimal.
- **`StepDefinitions` types** — Step handlers are organized into `TodoSetupSteps`, `TodoActionSteps`, and `TodoVerificationSteps`, registered via `stepDefinitionTypes`. The test class (`TodoUITests`) contains only configuration.
- **App reuse across scenarios** — `setUp()` launches only once (`app == nil`), then reuses via `activate()`. Each scenario starts with a clean state via the "the todo list is empty" background step (clicks "Clear All").
- **Index-based accessibility identifiers** (`todoText_0`, `deleteButton_1`, `editButton_0`, `editTextField_0`) — deterministic IDs for ForEach with enumerated array.
- **`waitForExistence(timeout: 5)`** — all element queries use this to avoid flakiness.
- **Local package dependency** — `project.yml` references PickleKit via `path: ../..`.
- **Tag filtering** — `tagFilter` override excludes `@wip`; `CUCUMBER_TAGS` env var for CLI filtering.
- **Scenario name filtering** — `scenarioNameFilter` override or `CUCUMBER_SCENARIOS` env var for name-based filtering. With xcodebuild, use `TEST_RUNNER_CUCUMBER_SCENARIOS` (the `TEST_RUNNER_` prefix is stripped by xcodebuild).

## Concurrency Notes

- All AST types are `Sendable` value types
- `StepHandler` is `@MainActor @Sendable ... async throws` — handlers run on the main thread, safe for XCTest assertions and UI frameworks
- `StepRegistry` is `@unchecked Sendable` — not thread-safe for concurrent registration, but safe for concurrent matching after setup
- `ScenarioRunner` is `Sendable` — safe to use from any context. When it calls `await handler(match)`, the runtime hops to the main actor because `StepHandler` is `@MainActor`
- `GherkinTestCase` runs scenarios with `Task { @MainActor in }` + `waitForExpectations` to bridge XCTest's sync test methods with async step handlers. Uses `nonisolated(unsafe)` for the `self` reference to satisfy Swift 6 strict concurrency
- `GherkinTestScenario` is `Sendable` — safe for Swift Testing's concurrent test execution. Use `@Suite(.serialized)` when step definitions use shared mutable static state
- Test files use `TestBox<T>` (`final class: @unchecked Sendable`) to share mutable state between `@MainActor` step handler closures and nonisolated test assertions
