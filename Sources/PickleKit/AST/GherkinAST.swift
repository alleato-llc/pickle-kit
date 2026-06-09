import Foundation

// MARK: - Feature

public struct Feature: Sendable, Equatable {
    public let name: String
    public let description: String
    public let tags: [String]
    public let background: Background?
    public let scenarios: [ScenarioDefinition]
    public let sourceFile: String?

    public init(
        name: String,
        description: String = "",
        tags: [String] = [],
        background: Background? = nil,
        scenarios: [ScenarioDefinition] = [],
        sourceFile: String? = nil
    ) {
        self.name = name
        self.description = description
        self.tags = tags
        self.background = background
        self.scenarios = scenarios
        self.sourceFile = sourceFile
    }
}

// MARK: - Scenario Definition

public enum ScenarioDefinition: Sendable, Equatable {
    case scenario(Scenario)
    case outline(ScenarioOutline)

    public var name: String {
        switch self {
        case .scenario(let s): return s.name
        case .outline(let o): return o.name
        }
    }

    public var tags: [String] {
        switch self {
        case .scenario(let s): return s.tags
        case .outline(let o): return o.tags
        }
    }

    public var sourceLine: Int {
        switch self {
        case .scenario(let s): return s.sourceLine
        case .outline(let o): return o.sourceLine
        }
    }

    /// Returns the associated `Scenario` if this is a `.scenario` case, or `nil`.
    public var asScenario: Scenario? {
        if case .scenario(let s) = self { return s }
        return nil
    }

    /// Returns the associated `ScenarioOutline` if this is an `.outline` case, or `nil`.
    public var asOutline: ScenarioOutline? {
        if case .outline(let o) = self { return o }
        return nil
    }
}

// MARK: - Scenario

public struct Scenario: Sendable, Equatable {
    public let name: String
    public let tags: [String]
    public let steps: [Step]
    public let sourceLine: Int
    /// When this scenario was produced by expanding a `Scenario Outline`, the
    /// outline's name (the group key); nil for a plain scenario. Set by
    /// `OutlineExpander` so reports can group an outline's examples together.
    public let outlineName: String?
    /// For an outline-derived scenario, the part that distinguishes this
    /// example from its siblings (the substituted name, or the Examples-row
    /// values) — shown as the row label under the grouped outline header.
    public let exampleLabel: String?

    public init(
        name: String,
        tags: [String] = [],
        steps: [Step] = [],
        sourceLine: Int = 0,
        outlineName: String? = nil,
        exampleLabel: String? = nil
    ) {
        self.name = name
        self.tags = tags
        self.steps = steps
        self.sourceLine = sourceLine
        self.outlineName = outlineName
        self.exampleLabel = exampleLabel
    }
}

// MARK: - Scenario Outline

public struct ScenarioOutline: Sendable, Equatable {
    public let name: String
    public let tags: [String]
    public let steps: [Step]
    public let examples: [ExamplesTable]
    public let sourceLine: Int

    public init(
        name: String,
        tags: [String] = [],
        steps: [Step] = [],
        examples: [ExamplesTable] = [],
        sourceLine: Int = 0
    ) {
        self.name = name
        self.tags = tags
        self.steps = steps
        self.examples = examples
        self.sourceLine = sourceLine
    }
}

// MARK: - Background

public struct Background: Sendable, Equatable {
    public let steps: [Step]
    public let sourceLine: Int

    public init(steps: [Step] = [], sourceLine: Int = 0) {
        self.steps = steps
        self.sourceLine = sourceLine
    }
}

// MARK: - Step

public struct Step: Sendable, Equatable {
    public let keyword: StepKeyword
    public let text: String
    public let dataTable: DataTable?
    public let docString: String?
    public let sourceLine: Int

    public init(
        keyword: StepKeyword,
        text: String,
        dataTable: DataTable? = nil,
        docString: String? = nil,
        sourceLine: Int = 0
    ) {
        self.keyword = keyword
        self.text = text
        self.dataTable = dataTable
        self.docString = docString
        self.sourceLine = sourceLine
    }
}

// MARK: - Step Keyword

public enum StepKeyword: String, Sendable, Equatable {
    case given = "Given"
    case when = "When"
    case then = "Then"
    case and = "And"
    case but = "But"
}

// MARK: - Data Table

public struct DataTable: Sendable, Equatable {
    public let rows: [[String]]

    public init(rows: [[String]]) {
        self.rows = rows
    }

    public var headers: [String] {
        rows.first ?? []
    }

    public var dataRows: [[String]] {
        guard rows.count > 1 else { return [] }
        return Array(rows.dropFirst())
    }

    /// Returns data rows as dictionaries keyed by header names.
    public var asDictionaries: [[String: String]] {
        let hdrs = headers
        return dataRows.map { row in
            var dict: [String: String] = [:]
            for (index, header) in hdrs.enumerated() where index < row.count {
                dict[header] = row[index]
            }
            return dict
        }
    }
}

// MARK: - Examples Table

public struct ExamplesTable: Sendable, Equatable {
    public let tags: [String]
    public let table: DataTable
    public let sourceLine: Int

    public init(
        tags: [String] = [],
        table: DataTable,
        sourceLine: Int = 0
    ) {
        self.tags = tags
        self.table = table
        self.sourceLine = sourceLine
    }
}
