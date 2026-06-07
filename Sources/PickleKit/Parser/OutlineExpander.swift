import Foundation

/// Expands `ScenarioOutline` definitions into concrete `Scenario` instances
/// by substituting `<placeholder>` tokens with values from each Examples row.
public struct OutlineExpander: Sendable {

    public init() {}

    /// Expand all outline definitions in a feature into concrete scenarios.
    /// Regular scenarios pass through unchanged.
    public func expand(_ feature: Feature) -> Feature {
        let expanded = feature.scenarios.flatMap { definition -> [ScenarioDefinition] in
            switch definition {
            case .scenario:
                return [definition]
            case .outline(let outline):
                return expandOutline(outline).map { .scenario($0) }
            }
        }

        return Feature(
            name: feature.name,
            description: feature.description,
            tags: feature.tags,
            background: feature.background,
            scenarios: expanded,
            sourceFile: feature.sourceFile
        )
    }

    /// Expand a single ScenarioOutline into concrete Scenarios.
    public func expandOutline(_ outline: ScenarioOutline) -> [Scenario] {
        var scenarios: [Scenario] = []

        for (exampleIndex, examples) in outline.examples.enumerated() {
            let headers = examples.table.headers
            let dataRows = examples.table.dataRows

            for (rowIndex, row) in dataRows.enumerated() {
                let substitutions = Dictionary(
                    uniqueKeysWithValues: zip(headers, row)
                )

                let expandedSteps = outline.steps.map { step in
                    Step(
                        keyword: step.keyword,
                        text: substitute(step.text, with: substitutions),
                        dataTable: step.dataTable.map { substituteTable($0, with: substitutions) },
                        docString: step.docString.map { substitute($0, with: substitutions) },
                        sourceLine: step.sourceLine
                    )
                }

                // Friendly naming, Cucumber-style: substitute <placeholder>
                // tokens in the outline NAME (not just the steps). When the
                // name carries no placeholders, label the scenario with its
                // example VALUES rather than an opaque row index — so
                // "Construction mistakes [Row 2]" becomes
                // "Construction mistakes [Person(name: 7, …), 'name' is a String]".
                let substitutedName = substitute(outline.name, with: substitutions)
                let name: String
                if substitutedName != outline.name {
                    name = substitutedName
                } else {
                    let label = row.joined(separator: ", ")
                    if outline.examples.count > 1 {
                        // Multiple example blocks: keep the block visible so
                        // identical rows across blocks stay distinguishable.
                        name = "\(outline.name) [Examples \(exampleIndex + 1): \(label)]"
                    } else {
                        name = "\(outline.name) [\(label)]"
                    }
                }

                // Combine outline tags with example-level tags
                let combinedTags = outline.tags + examples.tags

                let scenario = Scenario(
                    name: name,
                    tags: combinedTags,
                    steps: expandedSteps,
                    sourceLine: outline.sourceLine
                )
                scenarios.append(scenario)
            }
        }

        return scenarios
    }

    // MARK: - Private

    private func substitute(_ text: String, with values: [String: String]) -> String {
        var result = text
        for (key, value) in values {
            result = result.replacingOccurrences(of: "<\(key)>", with: value)
        }
        return result
    }

    private func substituteTable(_ table: DataTable, with values: [String: String]) -> DataTable {
        let newRows = table.rows.map { row in
            row.map { cell in substitute(cell, with: values) }
        }
        return DataTable(rows: newRows)
    }
}
