# PickleKit

[![CI](https://github.com/nycjv321/pickle-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nycjv321/pickle-kit/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-Apple%20Platforms-blue)](https://github.com/nycjv321/pickle-kit)
[![Swift](https://img.shields.io/badge/swift-6.2%2B-orange)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)

A standalone Swift Cucumber/BDD testing framework with zero external dependencies. Parse Gherkin `.feature` files, register step definitions with regex patterns, and run scenarios — integrated with both Swift Testing and XCTest.

## Requirements

- Swift 6.2+
- macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+
- Swift Testing bridge (`GherkinTestScenario`) works on all platforms with Swift Testing support
- XCTest bridge (`GherkinTestCase`) requires ObjC runtime (Apple platforms)

## Installation

Add PickleKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nycjv321/pickle-kit.git", from: "0.1.0"),
],
targets: [
    .testTarget(
        name: "MyTests",
        dependencies: ["PickleKit"],
        resources: [.copy("Features")]
    ),
]
```

## Quick Start

### 1. Write a feature file

```gherkin
# Tests/MyTests/Features/calculator.feature
Feature: Calculator

  Scenario: Addition
    Given I have the number 5
    When I add 3
    Then the result should be 8
```

### 2. Define step definitions

Create types conforming to the `StepDefinitions` protocol. Each stored `StepDefinition` property is automatically discovered via reflection:

```swift
import PickleKit

struct CalculatorSteps: StepDefinitions {
    nonisolated(unsafe) static var result = 0
    init() { Self.result = 0 }

    let givenNumber = StepDefinition.given("I have the number (\\d+)") { match in
        Self.result = Int(match.captures[0])!
    }

    let addNumber = StepDefinition.when("I add (\\d+)") { match in
        Self.result += Int(match.captures[0])!
    }

    let checkResult = StepDefinition.then("the result should be (\\d+)") { match in
        let expected = Int(match.captures[0])!
        assert(Self.result == expected, "Expected \(expected) but got \(Self.result)")
    }
}
```

### 3. Write a test

**Swift Testing (recommended)** — use `GherkinTestScenario` for library tests, unit tests, and CI pipelines:

```swift
import Testing
import PickleKit

@Suite(.serialized) struct CalculatorTests {
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

<details>
<summary>XCTest alternative (GherkinTestCase)</summary>

Use `GherkinTestCase` when you need XCUITest for UI tests, or are working in a target where Swift Testing is unavailable (e.g., Xcode UI testing bundles):

```swift
import XCTest
import PickleKit

final class CalculatorTests: GherkinTestCase {
    override class var featureSubdirectory: String? { "Features" }
    override class var stepDefinitionTypes: [any StepDefinitions.Type] {
        [CalculatorSteps.self]
    }
}
```

</details>

<details>
<summary>Inline alternative (registerStepDefinitions)</summary>

With `GherkinTestCase`, you can also register steps inline — both approaches work and can coexist:

```swift
final class CalculatorTests: GherkinTestCase {
    override class var featureSubdirectory: String? { "Features" }

    override func registerStepDefinitions() {
        var result = 0

        given("I have the number (\\d+)") { match in
            result = Int(match.captures[0])!
        }

        when("I add (\\d+)") { match in
            result += Int(match.captures[0])!
        }

        then("the result should be (\\d+)") { match in
            let expected = Int(match.captures[0])!
            XCTAssertEqual(result, expected)
        }
    }
}
```

</details>

### 4. Run tests

```bash
swift test
```

Each scenario appears as a separate test in Xcode's test navigator.

## Why PickleKit

Before PickleKit, using Cucumber-style BDD in Swift required external toolchains — Ruby (via Cucumber), Java (via Karate), or CocoaPods-based frameworks. PickleKit provides a zero-dependency Swift-native Cucumber framework that integrates directly with Swift Testing and XCTest. No Gemfile, no Podfile, no build plugins — just a Swift package dependency.

## Gherkin Support

PickleKit supports the core Gherkin syntax:

- **Keywords** — `Feature`, `Background`, `Scenario`, `Scenario Outline`, `Given`, `When`, `Then`, `And`, `But`
- **Tags** — `@smoke`, `@wip`, etc. at feature and scenario level
- **Data Tables** — pipe-delimited tables accessible via `match.dataTable`
- **Doc Strings** — triple-quoted blocks accessible via `match.docString`
- **Scenario Outlines** — parameterized scenarios expanded from `Examples` tables
- **Backgrounds** — shared setup steps that run before every scenario
- **Comments** — lines starting with `#`

See [Gherkin Reference](docs/GHERKIN.md) for full syntax, step registration, tag filtering, and programmatic usage.

## HTML Test Reports

Generate Cucumber-style HTML reports with per-step results, timing, and status filtering:

```bash
PICKLE_REPORT=1 swift test
```

The report includes summary counts, collapsible per-feature sections, **Scenario Outline grouping** (an outline's examples fold under one header), per-step timing and error details, interactive filtering, and a sticky outline sidebar. It's a single self-contained HTML file and is **themeable** — light/dark out of the box, following the system preference and remembering your choice.

**[See a live report + living spec ↗](https://alleato-llc.github.io/pickle-kit/)** — regenerated on every push from PickleKit's own cucumber feature fixtures (arithmetic, a shopping cart, tags, doc strings, a data table, and a grouped scenario outline), run by its integration suite.

[![PickleKit HTML test report](https://alleato-llc.github.io/pickle-kit/screenshots/report.png)](https://alleato-llc.github.io/pickle-kit/report.html)

See [Report Configuration](docs/REPORTING.md) for customization, theming, xcodebuild integration, and programmatic generation.

## Example: TodoApp with XCUITest

The [`Example/TodoApp`](Example/TodoApp) directory contains a complete macOS SwiftUI todo app that demonstrates PickleKit with XCUITest.

![Xcode test navigator showing XCUITest results for the TodoApp](docs/todo-test-run.png)

It includes:

- **3 targets**: TodoApp (application), TodoAppTests (unit tests for `TodoStore`), TodoAppUITests (Gherkin UI tests)
- **3 feature files** covering CRUD, completion toggling, data tables, scenario outlines, and tag filtering
- **Unit tests** for the `@Observable TodoStore` — verifying add, remove, update, clear, and toggle without UI
- **Step definitions** that drive `XCUIApplication` via accessibility identifiers
- **URL-scheme seeding** (`todoapp://seed`) for fast, deterministic test setup
- **xcodegen** project spec (`project.yml`) — run `xcodegen generate` to create the Xcode project

See [`Example/TodoApp/README.md`](Example/TodoApp/README.md) for setup and usage.

## Setup

To adopt PickleKit's BDD conventions in your project — including configuration for AI-assisted development with Claude Code — see the [Setup Guide](docs/SETUP.md).

## AI-Assisted Development

PickleKit's Gherkin scenarios work as automated feedback loops improving the quality of the SDLC. This works especially well with AI coding agents. Write the spec in natural language, let the agent implement, run tests, and feed failures back — the same red-green-refactor cycle, with the agent doing the implementation. PickleKit itself was built this way with [Claude Code](https://claude.ai/claude-code).

See [AI-Assisted Development](docs/AI-DEVELOPMENT.md) for the workflow, lessons learned, and practical advice.

## Documentation

| Document | Content |
|----------|---------|
| [Gherkin Reference](docs/GHERKIN.md) | Syntax, step registration, tag filtering, programmatic usage |
| [BDD Conventions Guide](docs/BDD_GUIDE.md) | Feature file, step definition, and runner conventions |
| [Setup Guide](docs/SETUP.md) | Adopting BDD conventions in your project, Claude Code configuration |
| [Testing Guide](docs/TESTING.md) | Test design philosophy, BDD rationale, UI test best practices, CI |
| [Report Configuration](docs/REPORTING.md) | HTML report customization, xcodebuild integration |
| [AI-Assisted Development](docs/AI-DEVELOPMENT.md) | BDD feedback loop for AI coding agents |
| [Release Process](docs/RELEASE.md) | Conventional commits, CI/CD pipeline, automated releases |

## License

MIT — see [LICENSE](LICENSE) for details.
