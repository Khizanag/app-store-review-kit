import Foundation

/// One `[check].id` from the rulebook. Checks are pure: they read facts and rule parameters only.
public protocol Check: Sendable {
    var ids: [String] { get }
    func run(_ context: CheckContext) -> [Finding]
}

public struct CheckContext: Sendable {
    public let facts: AppFacts
    public let rule: Rule
    public let spec: CheckSpec
    public let rulebook: Rulebook

    /// A heuristic can point a person at code but never fails a build on its own, so low-confidence
    /// findings are capped at warning.
    public var severity: Severity {
        spec.confidence == .low ? min(rule.severity, .warning) : rule.severity
    }

    public func finding(_ message: String, subject: String, at locations: [Location]) -> Finding {
        Finding(
            ruleID: rule.id,
            subject: subject,
            severity: severity,
            confidence: spec.confidence,
            message: message,
            locations: locations,
        )
    }

    public func strings(_ parameter: String) -> [String] {
        spec[parameter]?.strings ?? []
    }

    public var rootLocation: Location {
        Location(path: ".")
    }

    /// Where an Info.plist key is set, or where it should be added.
    public var infoLocation: Location {
        facts.info.values.map(\.location).min() ?? rootLocation
    }
}

public enum CheckRegistry {
    public static let all: [any Check] = [
        PrivacyManifestPresentCheck(),
        RequiredReasonAPIsCheck(),
        RequiredReasonCodesCheck(),
        ManifestTrackingDomainsCheck(),
        UsageDescriptionsCheck(),
        UsageDescriptionQualityCheck(),
        PlistKeyPairsCheck(),
        PlistKeyPresentCheck(),
        ATSExceptionsCheck(),
        LaunchScreenCheck(),
        DeploymentTargetCheck(),
        TrackingTransparencyCheck(),
        PlaceholderStringsCheck(),
        DebugHostsCheck(),
        IPv4LiteralsCheck(),
        TriggerSafeguardCheck(),
        SignalCheck(),
        MetadataLengthCheck(),
        MetadataTermsCheck(),
        ReleaseNotesCheck(),
        DemoAccountCheck(),
    ]

    /// The check for a rule: a dedicated one by id, else a generic one when the parameters follow the
    /// convention: `signals` (or `patterns`, `sdks`, `hosts`, `packages`) and optionally `satisfied_by`.
    public static func check(for spec: CheckSpec) -> (any Check)? {
        if let check = byID[spec.id] { return check }
        guard SignalCheck.parameterNames.contains(where: { spec[$0] != nil }) else { return nil }
        return spec["satisfied_by"] == nil ? SignalCheck() : SatisfiedByCheck()
    }

    public static let byID: [String: any Check] = {
        var checks: [String: any Check] = [:]
        for check in all {
            for id in check.ids {
                checks[id] = check
            }
        }
        return checks
    }()
}
