import Foundation

public enum OutputFormat: String, Sendable, CaseIterable {
    case text
    case json
    case sarif
}

public enum Reporter {
    static let repository = "https://github.com/Khizanag/app-store-review-kit"

    public static func render(_ report: Report, as format: OutputFormat) -> String {
        switch format {
        case .text: text(report)
        case .json: serialize(json(report))
        case .sarif: serialize(sarif(report))
        }
    }

    static func ruleURL(_ ruleID: String) -> String {
        let parts = ruleID.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return repository }
        return "\(repository)/blob/main/rules/\(parts[0])/\(parts[1]).toml"
    }

    static func serialize(_ object: Any) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return "{}" }
        return (String(bytes: data, encoding: .utf8) ?? "{}") + "\n"
    }
}

// MARK: - Text
extension Reporter {
    static func text(_ report: Report) -> String {
        var lines: [String] = []
        for finding in report.findings {
            let rule = report.rules[finding.ruleID]
            let severity = finding.severity.rawValue.uppercased()
            lines.append("\(severity)  \(finding.ruleID)  [\(finding.confidence.rawValue) confidence]")
            lines.append("  \(finding.message)")
            for location in finding.locations {
                lines.append("  at \(location.description)")
            }
            if let guidelines = rule?.guidelines, !guidelines.isEmpty {
                lines.append("  guideline \(guidelines.joined(separator: ", "))")
            }
            if let fix = rule?.fix {
                lines.append("  fix: \(fix.replacingOccurrences(of: "\n", with: " "))")
            }
            lines.append("")
        }
        if !report.manual.isEmpty {
            lines.append("NEEDS A PERSON (\(report.manual.count) rules)")
            for rule in report.manual {
                lines.append("  \(rule.id): \(rule.title)")
                if let seen = report.reviewEvidence[rule.id], let first = seen.first {
                    let more = seen.count > 1 ? " and \(seen.count - 1) more" : ""
                    lines.append("    start at \(first.description)\(more)")
                }
            }
            lines.append("")
        }
        for note in report.notes {
            lines.append("note: \(note)")
        }
        lines.append(summary(report))
        return lines.joined(separator: "\n") + "\n"
    }

    static func summary(_ report: Report) -> String {
        let counts = Severity.allCases.reversed().map { severity in
            "\(report.findings.count { $0.severity == severity }) \(severity.rawValue)"
        }
        return "\(counts.joined(separator: ", ")); \(report.manual.count) for a person; "
            + "\(report.skipped.count) skipped. Traits: \(report.traits.joined(separator: ", ")). "
            + "Guidelines \(report.guidelinesRevision)."
    }
}

// MARK: - JSON
extension Reporter {
    static func json(_ report: Report) -> [String: Any] {
        [
            "guidelines_revision": report.guidelinesRevision,
            "traits": report.traits,
            "findings": report.findings.map { finding in
                [
                    "rule": finding.ruleID,
                    "instance": finding.instance,
                    "severity": finding.severity.rawValue,
                    "confidence": finding.confidence.rawValue,
                    "message": finding.message,
                    "locations": finding.locations.map { location -> [String: Any] in
                        ["path": location.path, "line": location.line.map { $0 as Any } ?? NSNull()]
                    },
                    "guidelines": report.rules[finding.ruleID]?.guidelines ?? [],
                    "fix": report.rules[finding.ruleID]?.fix ?? "",
                ] as [String: Any]
            },
            "needs_a_person": report.manual.map { rule in
                [
                    "rule": rule.id,
                    "title": rule.title,
                    "questions": rule.review,
                    "seen_at": (report.reviewEvidence[rule.id] ?? []).map(\.description),
                ] as [String: Any]
            },
            "skipped": report.skipped.map { ["rule": $0.ruleID, "reason": $0.reason] },
            "notes": report.notes,
        ]
    }
}

// MARK: - SARIF
extension Reporter {
    static func sarif(_ report: Report) -> [String: Any] {
        let ruleIDs = Array(Set(report.findings.map(\.ruleID))).sorted()
        let rules: [[String: Any]] = ruleIDs.compactMap { id in
            guard let rule = report.rules[id] else { return nil }
            return [
                "id": rule.id,
                "name": rule.id,
                "shortDescription": ["text": rule.title],
                "fullDescription": ["text": rule.summary],
                "help": ["text": rule.fix],
                "helpUri": ruleURL(rule.id),
                "defaultConfiguration": ["level": level(rule.severity)],
                "properties": ["tags": ["app-store-review"] + rule.guidelines.map { "guideline-\($0)" }],
            ]
        }
        let results: [[String: Any]] = report.findings.map { finding in
            [
                "ruleId": finding.ruleID,
                "level": level(finding.severity),
                "message": ["text": finding.message],
                "partialFingerprints": ["asrkInstance": finding.instance],
                "properties": ["confidence": finding.confidence.rawValue],
                "locations": finding.locations.map { location in
                    var physical: [String: Any] = ["artifactLocation": ["uri": location.path]]
                    if let line = location.line {
                        physical["region"] = ["startLine": line]
                    }
                    return ["physicalLocation": physical]
                },
            ]
        }
        let driver: [String: Any] = [
            "name": "asrk",
            "informationUri": repository,
            "rules": rules,
        ]
        return [
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            "version": "2.1.0",
            "runs": [["tool": ["driver": driver], "results": results]],
        ]
    }

    static func level(_ severity: Severity) -> String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .note: "note"
        }
    }
}
