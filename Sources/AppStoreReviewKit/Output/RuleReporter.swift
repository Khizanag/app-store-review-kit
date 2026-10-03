import Foundation

/// Renders rules themselves, for `asrk rules` and `asrk explain`.
public enum RuleReporter {
    /// Rules that cite a guideline section or any section below it: `5.1` matches `5.1.1`.
    public static func rules(in rulebook: Rulebook, guideline: String?) -> [Rule] {
        guard let guideline else { return rulebook.rules }
        return rulebook.rules.filter { rule in
            rule.guidelines.contains { $0 == guideline || $0.hasPrefix(guideline + ".") }
        }
    }

    public static func list(_ rules: [Rule], as format: OutputFormat) -> String {
        guard format == .json else {
            let lines = rules.map { rule in
                let kind = rule.isManual ? "manual" : rule.review.isEmpty ? "automated" : "assisted"
                let guidelines = rule.guidelines.isEmpty ? "-" : rule.guidelines.joined(separator: ",")
                return "\(rule.id)\t\(rule.severity.rawValue)\t\(kind)\t\(guidelines)\t\(rule.title)"
            }
            return lines.joined(separator: "\n") + "\n"
        }
        return Reporter.serialize(rules.map(json))
    }

    public static func explain(_ rule: Rule) -> String {
        var lines = ["\(rule.id): \(rule.title)", ""]
        lines.append("Severity \(rule.severity.rawValue), surfaces at \(rule.enforcedBy)"
            + (rule.check.map { ", \($0.confidence.rawValue)-confidence check" } ?? ", needs a person"))
        if !rule.guidelines.isEmpty {
            lines.append("Guidelines: \(rule.guidelines.joined(separator: ", "))")
        }
        if !rule.appliesWhen.isEmpty {
            lines.append("Applies to apps with: \(rule.appliesWhen.joined(separator: ", "))")
        }
        lines += ["", rule.summary, "", "Fix: \(rule.fix)"]
        if !rule.review.isEmpty {
            lines += ["", "Questions for a person:"] + rule.review.map { "  - \($0)" }
        }
        if !rule.references.isEmpty {
            lines += ["", "References:"] + rule.references.map { "  \($0)" }
        }
        lines += ["", "Source: \(Reporter.ruleURL(rule.id))"]
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ rule: Rule) -> [String: Any] {
        [
            "id": rule.id,
            "title": rule.title,
            "severity": rule.severity.rawValue,
            "enforced_by": rule.enforcedBy,
            "guidelines": rule.guidelines,
            "applies_when": rule.appliesWhen,
            "automated": !rule.isManual,
            "summary": rule.summary,
            "fix": rule.fix,
            "questions": rule.review,
            "references": rule.references,
        ]
    }
}
