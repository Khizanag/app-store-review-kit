import Foundation

public enum Severity: String, Sendable, Comparable, CaseIterable {
    case note
    case warning
    case error

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

public enum Confidence: String, Sendable {
    case high
    case medium
    case low
}

public struct CheckSpec: Sendable, Equatable {
    public let id: String
    public let confidence: Confidence
    public let parameters: [String: Value]

    public subscript(key: String) -> Value? {
        parameters[key]
    }
}

public struct Rule: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let severity: Severity
    public let evidence: [String]
    public let enforcedBy: String
    public let guidelines: [String]
    public let appliesWhen: [String]
    public let summary: String
    public let fix: String
    public let references: [String]
    public let itms: [String]
    public let check: CheckSpec?
    public let review: [String]

    public var isManual: Bool { check == nil }
}

// MARK: - Decoding
extension Rule {
    init(_ value: Value) throws(RulebookError) {
        guard let id = value["id"]?.string else {
            throw .malformed("rule without an id")
        }
        guard let title = value["title"]?.string,
              let severity = value["severity"]?.string.flatMap(Severity.init(rawValue:)),
              let enforcedBy = value["enforced_by"]?.string,
              let summary = value["summary"]?.string,
              let fix = value["fix"]?.string
        else {
            throw .malformed("rule \(id) is missing a required field")
        }
        self.id = id
        self.title = title
        self.severity = severity
        self.enforcedBy = enforcedBy
        self.summary = summary
        self.fix = fix
        evidence = value["evidence"]?.strings ?? []
        guidelines = value["guidelines"]?.strings ?? []
        appliesWhen = value["applies_when"]?.strings ?? []
        references = value["references"]?.strings ?? []
        itms = value["itms"]?.strings ?? []
        review = value["review"]?.strings ?? []
        check = try value["check"].map { checkValue throws(RulebookError) in
            try CheckSpec(checkValue, ruleID: id)
        }
    }
}

// MARK: - Check decoding
extension CheckSpec {
    init(_ value: Value, ruleID: String) throws(RulebookError) {
        guard var parameters = value.dictionary,
              let id = parameters.removeValue(forKey: "id")?.string,
              let confidence = parameters.removeValue(forKey: "confidence")?.string.flatMap(Confidence.init(rawValue:))
        else {
            throw .malformed("rule \(ruleID) has a [check] without an id or confidence")
        }
        self.init(id: id, confidence: confidence, parameters: parameters)
    }
}
