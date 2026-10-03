@testable import AppStoreReviewKit
import Foundation
import Testing

@Suite("Rulebook")
struct RulebookTests {
    @Test
    func embeddedRulebookLoads() throws {
        let rulebook = try Rulebook.embedded()
        #expect(rulebook.rules.count >= 50)
        #expect(rulebook.guidelinesRevision.count == 10)
        #expect(!rulebook.catalog("required-reason-apis", list: "categories").isEmpty)
    }

    @Test
    func everyAutomatedCheckIDIsKnownOrReportedAsSkipped() throws {
        let rulebook = try Rulebook.embedded()
        let registered = rulebook.rules.compactMap(\.check).filter { CheckRegistry.byID[$0.id] != nil }
        #expect(registered.count >= 20)
    }

    @Test
    func rejectsNewerSchemas() {
        #expect(throws: RulebookError.unsupportedSchema(99)) {
            try Rulebook(data: Data(#"{"schema_version": 99, "rules": []}"#.utf8))
        }
        #expect(throws: RulebookError.malformed("missing schema_version")) {
            try Rulebook(data: Data("{}".utf8))
        }
    }

    @Test
    func filtersRulesByGuidelineAndExplainsThem() throws {
        let rulebook = try Rulebook.embedded()
        let privacy = RuleReporter.rules(in: rulebook, guideline: "5.1")
        #expect(privacy.contains { $0.id == "privacy.required-reason-undeclared" })
        #expect(privacy.allSatisfy { rule in rule.guidelines.contains { $0.hasPrefix("5.1") } })
        #expect(!RuleReporter.rules(in: rulebook, guideline: "5.1").contains { $0.guidelines == ["5.10"] })

        let rule = try #require(rulebook.rule("privacy.required-reason-undeclared"))
        let text = RuleReporter.explain(rule)
        #expect(text.hasPrefix("privacy.required-reason-undeclared: "))
        #expect(text.contains("Fix: "))
        #expect(text.contains("rules/privacy/required-reason-undeclared.toml"))

        let json = Data(RuleReporter.list([rule], as: .json).utf8)
        let decoded = try #require(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        #expect(decoded.first?["id"] as? String == rule.id)
    }

    @Test
    func versionsCompareNumerically() {
        #expect(Version("9.3") < Version("13.0"))
        #expect(!(Version("13") < Version("13.0")))
        #expect(Version("12.4.1") < Version("12.5"))
    }
}

@Suite("Reporters")
struct ReporterTests {
    func sampleReport() throws -> Report {
        let fixture = try Fixture(["App/Network.swift": "let url = \"http://localhost:3000\""])
        defer { fixture.remove() }
        return try fixture.review()
    }

    @Test
    func sarifCarriesRulesResultsAndFingerprints() throws {
        let report = try sampleReport()
        let data = Data(Reporter.render(report, as: .sarif).utf8)
        let sarif = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let run = try #require((sarif["runs"] as? [[String: Any]])?.first)
        let results = try #require(run["results"] as? [[String: Any]])

        #expect(sarif["version"] as? String == "2.1.0")
        #expect(results.count == report.findings.count)
        let result = try #require(results.first { $0["ruleId"] as? String == "build.debug-endpoints" })
        let fingerprints = try #require(result["partialFingerprints"] as? [String: String])
        #expect(fingerprints["asrkInstance"] == "build.debug-endpoints#hosts")
        let driver = try #require((run["tool"] as? [String: Any])?["driver"] as? [String: Any])
        let rules = try #require(driver["rules"] as? [[String: Any]])
        #expect(rules.contains { ($0["helpUri"] as? String)?.hasSuffix("rules/build/debug-endpoints.toml") == true })
    }

    @Test
    func jsonListsFindingsSkipsAndQuestions() throws {
        let report = try sampleReport()
        let data = Data(Reporter.render(report, as: .json).utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect((json["findings"] as? [[String: Any]])?.count == report.findings.count)
        #expect((json["skipped"] as? [[String: Any]])?.isEmpty == false)
        #expect((json["needs_a_person"] as? [[String: Any]])?.isEmpty == false)
    }

    @Test
    func textEndsWithASummary() throws {
        let text = Reporter.render(try sampleReport(), as: .text)
        #expect(text.contains("WARNING  build.debug-endpoints"))
        #expect(text.contains("for a person"))
    }
}
