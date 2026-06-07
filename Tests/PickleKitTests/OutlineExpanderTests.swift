import Testing
@testable import PickleKit

@Suite struct OutlineExpanderTests {

    let expander = OutlineExpander()

    // MARK: - Basic Expansion

    @Test func expandSingleExamplesTable() {
        let outline = ScenarioOutline(
            name: "Eating",
            steps: [
                Step(keyword: .given, text: "I have <start> items"),
                Step(keyword: .when, text: "I remove <count>"),
                Step(keyword: .then, text: "I have <remaining>"),
            ],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["start", "count", "remaining"],
                        ["10", "3", "7"],
                        ["5", "2", "3"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        #expect(scenarios.count == 2)
        #expect(scenarios[0].steps[0].text == "I have 10 items")
        #expect(scenarios[0].steps[1].text == "I remove 3")
        #expect(scenarios[0].steps[2].text == "I have 7")
        #expect(scenarios[1].steps[0].text == "I have 5 items")
    }

    // MARK: - Naming

    @Test func singleExamplesTableNaming() {
        let outline = ScenarioOutline(
            name: "Login",
            steps: [Step(keyword: .given, text: "user <name>")],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["name"],
                        ["Alice"],
                        ["Bob"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        // No placeholder in the name → labelled with the example values.
        #expect(scenarios[0].name == "Login [Alice]")
        #expect(scenarios[1].name == "Login [Bob]")
    }

    @Test func placeholderInNameIsSubstituted() {
        // Cucumber-standard: <param> tokens in the outline NAME are
        // substituted from each row, giving self-describing scenario names.
        let outline = ScenarioOutline(
            name: "Adding <a> and <b>",
            steps: [Step(keyword: .given, text: "<a> plus <b>")],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["a", "b"],
                        ["2", "3"],
                        ["10", "20"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        #expect(scenarios[0].name == "Adding 2 and 3")
        #expect(scenarios[1].name == "Adding 10 and 20")
    }

    @Test func multiColumnFallbackNamingUsesAllValues() {
        let outline = ScenarioOutline(
            name: "Mistakes explain themselves",
            steps: [Step(keyword: .when, text: "I run <expr>")],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["expr", "message"],
                        ["foo()", "missing arg"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        #expect(scenarios[0].name == "Mistakes explain themselves [foo(), missing arg]")
    }

    @Test func multipleExamplesTablesNaming() {
        let outline = ScenarioOutline(
            name: "Access",
            steps: [Step(keyword: .given, text: "role <role>")],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["role"],
                        ["admin"],
                    ])
                ),
                ExamplesTable(
                    table: DataTable(rows: [
                        ["role"],
                        ["user"],
                        ["guest"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        #expect(scenarios.count == 3)
        // No placeholder in the name + multiple blocks → block index kept,
        // labelled with values.
        #expect(scenarios[0].name == "Access [Examples 1: admin]")
        #expect(scenarios[1].name == "Access [Examples 2: user]")
        #expect(scenarios[2].name == "Access [Examples 2: guest]")
    }

    // MARK: - Tag Combination

    @Test func outlineTagsCombinedWithExamplesTags() {
        let outline = ScenarioOutline(
            name: "Tagged",
            tags: ["smoke"],
            steps: [Step(keyword: .given, text: "<x>")],
            examples: [
                ExamplesTable(
                    tags: ["fast"],
                    table: DataTable(rows: [["x"], ["1"]])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)

        #expect(scenarios[0].tags == ["smoke", "fast"])
    }

    // MARK: - Feature-level Expansion

    @Test func expandFeaturePassesThroughRegularScenarios() throws {
        let feature = Feature(
            name: "Mixed",
            scenarios: [
                .scenario(Scenario(name: "Regular", steps: [
                    Step(keyword: .given, text: "something"),
                ])),
                .outline(ScenarioOutline(
                    name: "Parameterized",
                    steps: [Step(keyword: .given, text: "value <v>")],
                    examples: [
                        ExamplesTable(
                            table: DataTable(rows: [["v"], ["1"], ["2"]])
                        ),
                    ]
                )),
            ]
        )

        let expanded = expander.expand(feature)

        #expect(expanded.scenarios.count == 3)

        // First should be the regular scenario unchanged
        let s0 = try #require(expanded.scenarios[0].asScenario)
        #expect(s0.name == "Regular")

        // Next two should be expanded from outline
        let s1 = try #require(expanded.scenarios[1].asScenario)
        #expect(s1.steps[0].text == "value 1")
    }

    // MARK: - Doc String Substitution

    @Test func docStringPlaceholderSubstitution() {
        let outline = ScenarioOutline(
            name: "API",
            steps: [
                Step(keyword: .given, text: "response", docString: "{\"name\": \"<name>\"}"),
            ],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [["name"], ["Alice"]])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)
        #expect(scenarios[0].steps[0].docString == "{\"name\": \"Alice\"}")
    }

    // MARK: - Data Table Substitution

    @Test func dataTablePlaceholderSubstitution() {
        let outline = ScenarioOutline(
            name: "Table",
            steps: [
                Step(
                    keyword: .given,
                    text: "users",
                    dataTable: DataTable(rows: [
                        ["name", "role"],
                        ["<user>", "<role>"],
                    ])
                ),
            ],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [
                        ["user", "role"],
                        ["Alice", "admin"],
                    ])
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)
        let table = scenarios[0].steps[0].dataTable!
        #expect(table.rows[1] == ["Alice", "admin"])
    }

    // MARK: - Empty Examples

    @Test func emptyExamplesProducesNoScenarios() {
        let outline = ScenarioOutline(
            name: "Empty",
            steps: [Step(keyword: .given, text: "<x>")],
            examples: [
                ExamplesTable(
                    table: DataTable(rows: [["x"]]) // Headers only, no data rows
                ),
            ]
        )

        let scenarios = expander.expandOutline(outline)
        #expect(scenarios.isEmpty)
    }
}
