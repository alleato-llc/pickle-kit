---
name: picklekit
description: Use when writing or running Cucumber/Gherkin BDD tests in Swift with the PickleKit library — authoring .feature files, defining step definitions, wiring them to Swift Testing (@Test) or XCTest/XCUITest, filtering by tags, and generating the HTML report. Apply whenever a target depends on PickleKit, a .feature file is involved, or a request asks for behavior-driven/Gherkin specs in Swift.
---

# Writing BDD tests with PickleKit

PickleKit is a Swift-native Cucumber framework: parse Gherkin `.feature` files,
register step definitions with regex patterns, and run scenarios through **Swift
Testing** or **XCTest/XCUITest**. No Ruby, no Podfile — just a Swift package.

## Install

```swift
.package(url: "https://github.com/alleato-llc/pickle-kit.git", from: "0.1.0"),
// test target — bundle the features as resources:
.testTarget(name: "MyTests", dependencies: ["PickleKit"], resources: [.copy("Features")]),
```

The three pieces: a **`.feature` file** (the spec), a **`StepDefinitions` type**
(glue), and a **test** that runs the scenarios.

## 1. Feature file (`Tests/MyTests/Features/calculator.feature`)

```gherkin
Feature: Calculator

  Scenario: Addition
    Given I have the number 5
    When I add 3
    Then the result should be 8
```

Supported: `Feature`, `Background`, `Scenario`, `Scenario Outline` + `Examples`,
`Given/When/Then/And/But`, `@tags` (feature + scenario level), pipe **data
tables**, triple-quoted **doc strings**, and `#` comments.

## 2. Step definitions

Conform to `StepDefinitions`. **Every stored `let` property of type
`StepDefinition` is auto-discovered via reflection** — no manual registration.
Build them with `.given` / `.when` / `.then` / `.step` (keyword-agnostic). Regex
capture groups arrive as `match.captures: [String]`.

```swift
import PickleKit

struct CalculatorSteps: StepDefinitions {
    nonisolated(unsafe) static var result = 0
    init() { Self.result = 0 }            // reset the world — see "State" below

    let given = StepDefinition.given("I have the number (\\d+)") { match in
        Self.result = Int(match.captures[0])!
    }
    let when = StepDefinition.when("I add (\\d+)") { match in
        Self.result += Int(match.captures[0])!
    }
    let then = StepDefinition.then("the result should be (\\d+)") { match in
        let expected = Int(match.captures[0])!
        assert(Self.result == expected, "expected \(expected), got \(Self.result)")
    }
}
```

The handler is `@MainActor @Sendable (StepMatch) async throws -> Void` — `await`
and `throw` freely. A step **fails** by throwing (or a failed `assert`/`#expect`).

**`StepMatch`** gives you: `captures: [String]` (regex groups), `dataTable:
DataTable?`, `docString: String?`. `DataTable` has `.rows`, `.headers`,
`.dataRows`, and `.asDictionaries` (`[[String: String]]` keyed by header row).

## 3a. Run with Swift Testing (recommended for unit/library/CI)

```swift
import Testing
import PickleKit

@Suite(.serialized) struct CalculatorTests {        // .serialized: steps share static state
    static let scenarios = GherkinTestScenario.scenarios(
        bundle: .module, subdirectory: "Features"
    )

    @Test(arguments: CalculatorTests.scenarios)
    func scenario(_ test: GherkinTestScenario) async throws {
        let result = try await test.run(stepDefinitions: [CalculatorSteps.self])
        #expect(result.passed)
    }
}
```

Each scenario shows as its own case in the test navigator. `scenarios(bundle:
subdirectory:tagFilter:scenarioNameFilter:)` loads + expands outlines; `run`
returns a `ScenarioResult` with `.passed`.

## 3b. Run with XCTest / XCUITest

Subclass `GherkinTestCase` and override class vars — use this for UI tests
driving `XCUIApplication`:

```swift
final class CalculatorTests: GherkinTestCase {
    override class var featureSubdirectory: String? { "Features" }
    override class var stepDefinitionTypes: [any StepDefinitions.Type] { [CalculatorSteps.self] }
    override class var tagFilter: TagFilter? { TagFilter(excludeTags: ["wip"]) }
}
```

## State, tags, reports

- **State (the one-world-per-scenario rule):** the runner builds a *fresh*
  `StepDefinitions` instance per scenario, so put shared state in `static` and
  **reset it in `init()`** — that's the sanctioned pattern. `init()` runs **off**
  the main actor; do not call `MainActor.assumeIsolated` there (it crashes). Use
  a `needsReset` flag + lazy `@MainActor` world if the state must be main-actor.
- **Tags:** `TagFilter(includeTags: ["smoke"], excludeTags: ["wip"])`. Pass to
  `scenarios(tagFilter:)` or override `tagFilter`. Excluded scenarios are
  reported as *skipped*, not removed.
- **HTML report:** `PICKLE_REPORT=1 swift test` writes a self-contained,
  themeable report (collapsible features, scenario-outline grouping, an outline
  rail). `PICKLE_REPORT_PATH` sets the file; `PICKLE_SPEC_PATH` also writes a
  living-specification page. `xcodebuild` does **not** forward shell env to the
  runner — use scheme environment variables or the `reportEnabled` /
  `reportOutputPath` class overrides; sandboxed UI runners fall back to the
  container tmp dir (path printed to stderr).

## Conventions & gotchas

- Step properties must be **stored `let` instance properties** of the conforming
  type — that's how reflection finds them. A computed var or a free function
  won't be registered.
- Use `@Suite(.serialized)` whenever scenarios share `static` state — Swift
  Testing parallelizes by default, and `.serialized` only orders *within* a
  suite, so keep one step-world per suite.
- Assert inside the **test wrapper** on `result.passed` (Swift Testing) — the
  step handlers fail by throwing; the wrapper surfaces it.
- Features must be **bundled** (`resources: [.copy("Features")]`) so
  `bundle: .module` can find them.
- Keep user-visible behavior in the **feature files**; keep step glue thin.

## Deeper reference

`Example/TodoApp` is a complete macOS SwiftUI app driving `XCUIApplication` via
accessibility ids, with feature files covering CRUD, data tables, outlines, and
tag filtering. `docs/GHERKIN.md` is the full syntax reference; `docs/REPORTING.md`
covers report theming and xcodebuild integration; `docs/BDD_GUIDE.md` covers the
conventions.
