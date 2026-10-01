import Foundation

public struct Finding: Sendable, Equatable {
    public let ruleID: String
    /// Stable across runs, for baselines and suppressions: `rule#subject`.
    public let instance: String
    public let severity: Severity
    public let confidence: Confidence
    public let message: String
    public let locations: [Location]

    public init(
        ruleID: String,
        subject: String,
        severity: Severity,
        confidence: Confidence,
        message: String,
        locations: [Location],
    ) {
        self.ruleID = ruleID
        instance = "\(ruleID)#\(subject)"
        self.severity = severity
        self.confidence = confidence
        self.message = message
        self.locations = locations.sorted()
    }
}

public struct SkippedRule: Sendable, Equatable {
    public let ruleID: String
    public let reason: String
}

public struct Report: Sendable {
    public let guidelinesRevision: String
    public let traits: [String]
    public let findings: [Finding]
    public let skipped: [SkippedRule]
    /// Rules that apply to this app but need a person to judge; each carries its review questions.
    public let manual: [Rule]
    /// Where low-confidence signals for a manual rule appeared, to start the person's review there.
    public let reviewEvidence: [String: [Location]]
    public let notes: [String]
    public let rules: [String: Rule]

    public func failing(at threshold: Severity) -> [Finding] {
        findings.filter { $0.severity >= threshold }
    }
}
