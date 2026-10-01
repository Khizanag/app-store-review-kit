import Foundation

/// Field limits from `[check]`: `field` with `max`, or `limits` in characters and `byte_limits` in UTF-8 bytes.
struct MetadataLengthCheck: Check {
    let ids = ["metadata-length"]

    func run(_ context: CheckContext) -> [Finding] {
        var characterLimits = (context.spec["limits"]?.dictionary ?? [:]).compactMapValues(\.number)
        if let field = context.spec["field"]?.string, let maximum = context.spec["max"]?.number {
            characterLimits[field] = maximum
        }
        let byteLimits = (context.spec["byte_limits"]?.dictionary ?? [:]).compactMapValues(\.number)
        return findings(context, limits: characterLimits, unit: "characters") { $0.count }
            + findings(context, limits: byteLimits, unit: "bytes") { $0.utf8.count }
    }

    private func findings(
        _ context: CheckContext,
        limits: [String: Double],
        unit: String,
        measure: (String) -> Int,
    ) -> [Finding] {
        limits.keys.sorted().flatMap { name in
            let limit = Int(limits[name] ?? 0)
            return context.facts.metadata.values(of: name).compactMap { locale, field -> Finding? in
                let length = measure(field.text)
                guard length > limit else { return nil }
                return context.finding(
                    "The \(locale) \(name) is \(length) \(unit); the limit is \(limit).",
                    subject: "\(locale)/\(name)",
                    at: [field.location],
                )
            }
        }
    }
}

struct MetadataTermsCheck: Check {
    let ids = ["metadata-terms"]

    func run(_ context: CheckContext) -> [Finding] {
        let matchers = context.strings("terms").map(TermMatcher.init)
        return context.strings("fields").flatMap { name in
            context.facts.metadata.values(of: name).compactMap { locale, field in
                let found = matchers.filter { $0.matches(field.text) }.map(\.term)
                guard !found.isEmpty else { return nil }
                return context.finding(
                    "The \(locale) \(name) mentions \(found.map { "\"\($0)\"" }.joined(separator: ", ")).",
                    subject: "\(locale)/\(name)",
                    at: [field.location],
                )
            }
        }
    }
}

struct ReleaseNotesCheck: Check {
    let ids = ["release-notes-generic"]

    func run(_ context: CheckContext) -> [Finding] {
        let phrases = context.strings("phrases").map { $0.lowercased() }
        return context.facts.metadata.values(of: "release_notes").compactMap { locale, field in
            let text = field.text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            guard phrases.contains(text) else { return nil }
            return context.finding(
                "The \(locale) What's New text is only \"\(field.text)\".",
                subject: "\(locale)/release_notes",
                at: [field.location],
            )
        }
    }
}

struct DemoAccountCheck: Check {
    let ids = ["demo-account"]

    func run(_ context: CheckContext) -> [Finding] {
        let facts = context.facts
        guard facts.loadedEvidence.contains("metadata") else { return [] }
        let hits = facts.signalHits(context.strings("login_signals"), ruleID: context.rule.id)
        let review = facts.metadata.reviewInformation
        let hasDemoUser = !(review["demo_user"]?.text.isEmpty ?? true)
        guard !hits.isEmpty, !hasDemoUser else { return [] }
        let signals = hits.patterns.joined(separator: ", ")
        return [
            context.finding(
                "The app has a login (\(signals)) but review_information has no demo_user.",
                subject: "app",
                at: hits.sample(),
            ),
        ]
    }
}
