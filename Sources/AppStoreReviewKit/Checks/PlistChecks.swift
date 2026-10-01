import Foundation

struct UsageDescriptionsCheck: Check {
    let ids = ["usage-descriptions"]

    func run(_ context: CheckContext) -> [Finding] {
        let catalog = context.spec["catalog"]?.string ?? "usage-descriptions"
        return context.rulebook.catalog(catalog, list: "resources").compactMap { resource in
            let keys = resource["keys"]?.strings ?? []
            guard !keys.contains(where: { context.facts.info[$0] != nil }) else { return nil }
            let hits = context.facts.codeHits(resource["symbols"]?.strings ?? [], ruleID: context.rule.id)
            guard !hits.isEmpty else { return nil }
            let name = resource["name"]?.string ?? keys.first ?? "a protected resource"
            return context.finding(
                "Requests \(name) access (\(hits.patterns.joined(separator: ", "))) without "
                    + "\(keys.joined(separator: " or ")) in Info.plist.",
                subject: keys.first ?? name,
                at: hits.sample(),
            )
        }
    }
}

struct UsageDescriptionQualityCheck: Check {
    let ids = ["usage-description-quality"]

    func run(_ context: CheckContext) -> [Finding] {
        let minimumLength = Int(context.spec["min_length"]?.number ?? 25)
        let placeholders = context.strings("placeholders").map(TermMatcher.init)
        return context.facts.info
            .filter { $0.key.hasSuffix("UsageDescription") }
            .sorted { $0.key < $1.key }
            .compactMap { key, info in
                let text = info.value.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let problem: String? = if text.isEmpty {
                    "is empty"
                } else if let placeholder = placeholders.first(where: { $0.matches(text) }) {
                    "reads like a placeholder (\"\(placeholder.term)\")"
                } else if text.count < minimumLength {
                    "is \(text.count) characters; say what feature uses the data and why"
                } else {
                    nil
                }
                return problem.map { context.finding("\(key) \($0).", subject: key, at: [info.location]) }
            }
    }
}

struct PlistKeyPairsCheck: Check {
    let ids = ["plist-key-pairs"]

    func run(_ context: CheckContext) -> [Finding] {
        (context.spec["requires"]?.dictionary ?? [:])
            .sorted { $0.key < $1.key }
            .compactMap { key, required in
                guard let present = context.facts.info[key],
                      let requiredKey = required.string,
                      context.facts.info[requiredKey] == nil
                else { return nil }
                return context.finding("\(key) is set without \(requiredKey).", subject: key, at: [present.location])
            }
    }
}

struct PlistKeyPresentCheck: Check {
    let ids = ["plist-key-present"]

    func run(_ context: CheckContext) -> [Finding] {
        guard let key = context.spec["key"]?.string, context.facts.info[key] == nil else { return [] }
        return [context.finding("Info.plist does not set \(key).", subject: key, at: [context.infoLocation])]
    }
}

struct ATSExceptionsCheck: Check {
    let ids = ["ats-exceptions"]

    func run(_ context: CheckContext) -> [Finding] {
        guard let ats = context.facts.info["NSAppTransportSecurity"],
              ats.value["NSAllowsArbitraryLoads"]?.bool == true
        else { return [] }
        return [
            context.finding(
                "NSAllowsArbitraryLoads disables App Transport Security for every connection.",
                subject: "NSAllowsArbitraryLoads",
                at: [ats.location],
            ),
        ]
    }
}

struct LaunchScreenCheck: Check {
    let ids = ["launch-screen"]
    private let keys = ["UILaunchScreen", "UILaunchStoryboardName", "UILaunchScreens", "UILaunchStoryboards"]

    func run(_ context: CheckContext) -> [Finding] {
        let facts = context.facts
        guard facts.buildSettings["SDKROOT"].map({ $0.contains("iphoneos") || $0 == "auto" }) ?? true,
              !keys.contains(where: { facts.info[$0] != nil })
        else { return [] }
        return [context.finding("No launch screen is configured.", subject: "app", at: [context.infoLocation])]
    }
}

struct DeploymentTargetCheck: Check {
    let ids = ["deployment-target"]

    func run(_ context: CheckContext) -> [Finding] {
        guard let minimum = context.spec["minimum"]?["iphoneos"]?.string,
              let target = context.facts.buildSettings["IPHONEOS_DEPLOYMENT_TARGET"],
              Version(target) < Version(minimum)
        else { return [] }
        return [
            context.finding(
                "IPHONEOS_DEPLOYMENT_TARGET is \(target); App Store Connect requires \(minimum) or later.",
                subject: "IPHONEOS_DEPLOYMENT_TARGET",
                at: [context.facts.projectPath.map { Location(path: $0) } ?? context.rootLocation],
            ),
        ]
    }
}

/// A dotted version that compares numerically: 9.3 < 13.0.
struct Version: Comparable {
    let parts: [Int]

    init(_ text: String) {
        parts = text.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        let left = lhs.parts + Array(repeating: 0, count: count - lhs.parts.count)
        let right = rhs.parts + Array(repeating: 0, count: count - rhs.parts.count)
        return left.lexicographicallyPrecedes(right)
    }
}
