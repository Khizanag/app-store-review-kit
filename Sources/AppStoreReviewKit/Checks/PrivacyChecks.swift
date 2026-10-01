import Foundation

struct PrivacyManifestPresentCheck: Check {
    let ids = ["privacy-manifest-present"]

    func run(_ context: CheckContext) -> [Finding] {
        guard context.facts.appManifests.isEmpty else { return [] }
        return [context.finding("The app has no PrivacyInfo.xcprivacy.", subject: "app", at: [context.rootLocation])]
    }
}

/// Required reason API categories from `catalogs/required-reason-apis.toml`.
struct RequiredReasonCategory {
    let key: String
    let name: String
    let symbols: [String]
    let codes: Set<String>
    let sdkOnlyCodes: Set<String>

    static func all(in rulebook: Rulebook) -> [RequiredReasonCategory] {
        rulebook.catalog("required-reason-apis", list: "categories").compactMap { entry in
            guard let key = entry["key"]?.string else { return nil }
            let reasons = entry["reasons"]?.array ?? []
            return RequiredReasonCategory(
                key: key,
                name: entry["name"]?.string ?? key,
                symbols: entry["symbols"]?.strings ?? [],
                codes: Set(reasons.compactMap { $0["code"]?.string }),
                sdkOnlyCodes: Set(reasons.filter { $0["sdk_only"]?.bool == true }.compactMap { $0["code"]?.string }),
            )
        }
    }
}

struct RequiredReasonAPIsCheck: Check {
    let ids = ["required-reason-apis"]

    func run(_ context: CheckContext) -> [Finding] {
        let declared = Set(context.facts.appManifests.flatMap(\.accessedAPIs).map(\.category))
        return RequiredReasonCategory.all(in: context.rulebook).compactMap { category in
            guard !declared.contains(category.key) else { return nil }
            let hits = context.facts.codeHits(category.symbols, ruleID: context.rule.id)
            guard !hits.isEmpty else { return nil }
            let symbols = hits.patterns.joined(separator: ", ")
            return context.finding(
                "Uses \(category.name) APIs (\(symbols)) but no privacy manifest declares \(category.key).",
                subject: category.key,
                at: hits.sample(),
            )
        }
    }
}

struct RequiredReasonCodesCheck: Check {
    let ids = ["required-reason-codes"]

    func run(_ context: CheckContext) -> [Finding] {
        let categories = Dictionary(
            RequiredReasonCategory.all(in: context.rulebook).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        return context.facts.appManifests.flatMap { manifest in
            manifest.accessedAPIs.flatMap { api -> [Finding] in
                guard let category = categories[api.category] else {
                    return [
                        context.finding(
                            "\(api.category) is not a required reason API category.",
                            subject: api.category,
                            at: [manifest.location],
                        ),
                    ]
                }
                return api.reasons.compactMap { code in
                    if !category.codes.contains(code) {
                        return context.finding(
                            "\(code) is not an approved reason for \(category.name).",
                            subject: "\(api.category)/\(code)",
                            at: [manifest.location],
                        )
                    }
                    guard category.sdkOnlyCodes.contains(code) else { return nil }
                    return context.finding(
                        "\(code) may only be declared by a third-party SDK, not by the app.",
                        subject: "\(api.category)/\(code)",
                        at: [manifest.location],
                    )
                }
            }
        }
    }
}

struct ManifestTrackingDomainsCheck: Check {
    let ids = ["manifest-tracking-domains"]

    func run(_ context: CheckContext) -> [Finding] {
        context.facts.appManifests
            .filter { $0.tracking == true && $0.trackingDomains.isEmpty }
            .map {
                context.finding(
                    "NSPrivacyTracking is true but NSPrivacyTrackingDomains is empty.",
                    subject: $0.location.path,
                    at: [$0.location],
                )
            }
    }
}

struct TrackingTransparencyCheck: Check {
    let ids = ["att-usage"]

    func run(_ context: CheckContext) -> [Finding] {
        let facts = context.facts
        let hits = facts.signalHits(context.strings("signals"), ruleID: context.rule.id)
        guard !hits.isEmpty else { return [] }
        let requestsPermission = !facts.codeHits(["requestTrackingAuthorization"], ruleID: context.rule.id).isEmpty
        let hasPurposeString = facts.info["NSUserTrackingUsageDescription"] != nil
        guard !requestsPermission || !hasPurposeString else { return [] }
        let missing = [
            requestsPermission ? nil : "never calls ATTrackingManager.requestTrackingAuthorization",
            hasPurposeString ? nil : "has no NSUserTrackingUsageDescription",
        ]
        .compactMap(\.self)
        .joined(separator: " and ")
        return [
            context.finding(
                "Uses \(hits.patterns.joined(separator: ", ")) but \(missing).",
                subject: "app",
                at: hits.sample(),
            ),
        ]
    }
}
