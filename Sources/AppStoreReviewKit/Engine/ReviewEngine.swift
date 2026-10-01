import Foundation

public struct ReviewOptions: Sendable {
    /// Traits to assume in addition to the ones detected, for example from a profile.
    public var traits: Set<String> = []
    public var profile: String?
    /// Rule ids to leave out entirely.
    public var disabledRules: Set<String> = []

    public init(traits: Set<String> = [], profile: String? = nil, disabledRules: Set<String> = []) {
        self.traits = traits
        self.profile = profile
        self.disabledRules = disabledRules
    }
}

public struct ReviewEngine: Sendable {
    public let rulebook: Rulebook
    public let options: ReviewOptions

    public init(rulebook: Rulebook, options: ReviewOptions = ReviewOptions()) {
        self.rulebook = rulebook
        self.options = options
    }

    public func review(_ facts: AppFacts) -> Report {
        let traits = traits(for: facts)
        var findings: [Finding] = []
        var skipped: [SkippedRule] = []
        var manual: [Rule] = []
        var reviewEvidence: [String: [Location]] = [:]

        for rule in rulebook.rules where !options.disabledRules.contains(rule.id) {
            guard rule.appliesWhen.isEmpty || !traits.isDisjoint(with: rule.appliesWhen) else { continue }
            guard let spec = rule.check else {
                manual.append(rule)
                continue
            }
            guard let check = CheckRegistry.check(for: spec) else {
                skipped.append(SkippedRule(ruleID: rule.id, reason: "not automated yet"))
                if !rule.review.isEmpty { manual.append(rule) }
                continue
            }
            let available = Set(rule.evidence).intersection(facts.loadedEvidence)
            guard !available.isEmpty else {
                let needed = rule.evidence.joined(separator: ", ")
                skipped.append(SkippedRule(ruleID: rule.id, reason: "needs \(needed) evidence"))
                continue
            }
            let context = CheckContext(facts: facts, rule: rule, spec: spec, rulebook: rulebook)
            let results = check.run(context)
            if !rule.review.isEmpty { manual.append(rule) }
            if check is SignalCheck, spec.confidence == .low, !rule.review.isEmpty {
                let locations = results.flatMap(\.locations)
                if !locations.isEmpty { reviewEvidence[rule.id] = locations }
            } else {
                findings += results
            }
        }

        return Report(
            guidelinesRevision: rulebook.guidelinesRevision,
            traits: traits.sorted(),
            findings: findings.sorted(by: Self.order),
            skipped: skipped.sorted { $0.ruleID < $1.ruleID },
            manual: manual.sorted { $0.id < $1.id },
            reviewEvidence: reviewEvidence,
            notes: facts.notes,
            rules: Dictionary(uniqueKeysWithValues: rulebook.rules.map { ($0.id, $0) }),
        )
    }

    /// Detected traits, plus the profile's traits and any set explicitly.
    public func traits(for facts: AppFacts) -> Set<String> {
        var traits = options.traits
        if let profile = options.profile {
            let profiles = rulebook.catalog("profiles", list: "profiles")
            traits.formUnion(profiles.first { $0["id"]?.string == profile }?["traits"]?.strings ?? [])
        }
        for trait in rulebook.catalog("traits", list: "traits") {
            guard let id = trait["id"]?.string else { continue }
            let signals = trait["signals"]?.strings ?? []
            if !facts.signalHits(signals, ruleID: "trait.\(id)").isEmpty
                || signals.contains(where: { facts.entitlements[$0] != nil }) {
                traits.insert(id)
            }
        }
        return traits
    }

    static func order(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        if lhs.ruleID != rhs.ruleID { return lhs.ruleID < rhs.ruleID }
        let left = lhs.locations.first ?? Location(path: "")
        let right = rhs.locations.first ?? Location(path: "")
        return left != right ? left < right : lhs.instance < rhs.instance
    }
}
