import Foundation

struct PlaceholderStringsCheck: Check {
    let ids = ["placeholder-strings"]

    func run(_ context: CheckContext) -> [Finding] {
        let matchers = context.strings("terms").map(TermMatcher.init)
        let catalogHits = context.facts.localizedStrings.flatMap { string in
            matchers.filter { $0.matches(string.text) }.map {
                SourceHit(pattern: $0.term, location: string.location)
            }
        }
        let literalHits = context.facts.literalHits(ruleID: context.rule.id) { literal in
            matchers.contains { $0.matches(literal) }
        }
        .flatMap { hit in
            matchers.filter { $0.matches(hit.pattern) }.map {
                SourceHit(pattern: $0.term, location: hit.location)
            }
        }
        let hits = catalogHits + literalHits
        return Dictionary(grouping: hits, by: \.pattern).sorted { $0.key < $1.key }.map { term, hits in
            context.finding(
                "User-facing text contains \"\(term)\".",
                subject: term.lowercased(),
                at: hits.sample(),
            )
        }
    }
}

struct DebugHostsCheck: Check {
    let ids = ["debug-hosts"]

    func run(_ context: CheckContext) -> [Finding] {
        let patterns = context.strings("patterns").map { $0.lowercased() }
        var hits: [SourceHit] = []
        for file in context.facts.sources {
            for line in file.releaseLines where !file.isIgnored(context.rule.id, line: line.number) {
                for literal in line.strings {
                    guard let authority = Self.authority(of: literal),
                          let pattern = patterns.first(where: { Self.host(authority, matches: $0) })
                    else { continue }
                    hits.append(SourceHit(pattern: pattern, location: Location(path: file.path, line: line.number)))
                }
            }
        }
        guard !hits.isEmpty else { return [] }
        return [
            context.finding(
                "Release code points at development hosts (\(hits.patterns.joined(separator: ", "))).",
                subject: "hosts",
                at: hits.sample(),
            ),
        ]
    }

    /// `host:port` of a URL literal, or nil when the literal is not a URL.
    static func authority(of literal: String) -> String? {
        guard let schemeEnd = literal.range(of: "://") else { return nil }
        let rest = literal[schemeEnd.upperBound...]
        return String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }).lowercased()
    }

    static func host(_ authority: String, matches pattern: String) -> Bool {
        if pattern.hasSuffix(".") {
            return authority.hasPrefix(pattern) || authority.contains("." + pattern)
        }
        return authority.contains(pattern)
    }
}

struct IPv4LiteralsCheck: Check {
    let ids = ["ipv4-literals"]

    func run(_ context: CheckContext) -> [Finding] {
        let hits = context.facts.literalHits(ruleID: context.rule.id, where: Self.containsIPv4)
        guard !hits.isEmpty else { return [] }
        return [context.finding("String literals contain IPv4 addresses.", subject: "ipv4", at: hits.sample())]
    }

    static func containsIPv4(_ text: String) -> Bool {
        text.split { !$0.isNumber && $0 != "." }.contains { token in
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 4 && parts.allSatisfy { part in
                (1...3).contains(part.count) && (Int(part) ?? 256) <= 255
            }
        }
    }
}

/// "If the app does X it must also do Y": report once per project when the trigger appears and
/// the safeguard appears nowhere, in code or in user-facing strings.
struct TriggerSafeguardCheck: Check {
    struct Pairing {
        let trigger: String
        let safeguard: String
        let message: String
    }

    static let parameters: [String: Pairing] = [
        "account-deletion": Pairing(
            trigger: "creation_signals",
            safeguard: "deletion_signals",
            message: "Creates accounts but no account deletion was found",
        ),
        "restore-purchases": Pairing(
            trigger: "purchase_signals",
            safeguard: "restore_signals",
            message: "Sells purchases but no restore action was found",
        ),
        "login-services": Pairing(
            trigger: "third_party",
            safeguard: "privacy_preserving",
            message: "Offers third-party login without an equivalent privacy-preserving option",
        ),
    ]

    var ids: [String] { Array(Self.parameters.keys).sorted() }

    func run(_ context: CheckContext) -> [Finding] {
        guard let parameters = Self.parameters[context.spec.id] else { return [] }
        let facts = context.facts
        let triggers = facts.signalHits(context.strings(parameters.trigger), ruleID: context.rule.id)
        guard !triggers.isEmpty else { return [] }
        let safeguards = context.strings(parameters.safeguard)
        let protected = !facts.codeHits(safeguards, ruleID: context.rule.id).isEmpty
            || !facts.stringHits(safeguards, ruleID: context.rule.id).isEmpty
            || facts.localizedStrings.contains { string in
                safeguards.contains { string.text.localizedCaseInsensitiveContains($0) }
            }
        guard !protected else { return [] }
        return [
            context.finding(
                "\(parameters.message) (\(triggers.patterns.joined(separator: ", "))).",
                subject: "app",
                at: triggers.sample(),
            ),
        ]
    }
}

/// Generic "if the app does X it must also do Y": `signals` are the trigger, `satisfied_by` the safeguard.
struct SatisfiedByCheck: Check {
    let ids: [String] = []

    func run(_ context: CheckContext) -> [Finding] {
        let facts = context.facts
        let triggers = facts.signalHits(SignalCheck.parameterNames.flatMap(context.strings), ruleID: context.rule.id)
        guard !triggers.isEmpty,
              facts.signalHits(context.strings("satisfied_by"), ruleID: context.rule.id).isEmpty
        else { return [] }
        return [
            context.finding(
                "Found \(triggers.patterns.joined(separator: ", ")) without "
                    + "\(context.strings("satisfied_by").prefix(3).joined(separator: ", ")).",
                subject: "app",
                at: triggers.sample(),
            ),
        ]
    }
}

/// Reports where risky APIs, SDKs, or hosts appear so a person can judge them against the rule.
struct SignalCheck: Check {
    static let parameterNames = ["signals", "patterns", "hosts", "packages", "sdks"]

    let ids = ["external-payments", "third-party-ai-endpoints", "dynamic-code", "private-symbols", "kids-sdks"]

    func run(_ context: CheckContext) -> [Finding] {
        let signals = Self.parameterNames.flatMap(context.strings)
        let hits = context.facts.signalHits(signals, ruleID: context.rule.id)
        guard !hits.isEmpty else { return [] }
        let prompt = context.rule.review.first.map { " Review: \($0)" } ?? ""
        return [
            context.finding(
                "Found \(hits.patterns.joined(separator: ", ")).\(prompt)",
                subject: "app",
                at: hits.sample(),
            ),
        ]
    }
}
