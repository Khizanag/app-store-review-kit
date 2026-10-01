import Foundation

public struct SourceHit: Sendable, Equatable {
    public let pattern: String
    public let location: Location
}

// MARK: - Matching
extension AppFacts {
    /// Release code lines containing a symbol. Identifiers match whole words; plain C function
    /// names, such as `stat`, match only when called, so a variable named `stat` does not count.
    func codeHits(_ symbols: [String], ruleID: String) -> [SourceHit] {
        let matchers = symbols.map(SymbolMatcher.init)
        return releaseLines(ruleID: ruleID).flatMap { path, line in
            matchers.filter { $0.matches(line.code) }.map {
                SourceHit(pattern: $0.symbol, location: Location(path: path, line: line.number))
            }
        }
    }

    /// Release string literals that contain any pattern, ignoring case.
    func stringHits(
        _ patterns: [String],
        ruleID: String,
        where accept: (String) -> Bool = { _ in true },
    ) -> [SourceHit] {
        let lowered = patterns.map { ($0, $0.lowercased()) }
        return releaseLines(ruleID: ruleID).flatMap { path, line in
            line.strings.filter(accept).flatMap { literal in
                let text = literal.lowercased()
                return lowered.filter { text.contains($0.1) }.map {
                    SourceHit(pattern: $0.0, location: Location(path: path, line: line.number))
                }
            }
        }
    }

    /// Release string literals that satisfy a predicate.
    func literalHits(ruleID: String, where accept: (String) -> Bool) -> [SourceHit] {
        releaseLines(ruleID: ruleID).flatMap { path, line in
            line.strings.filter(accept).map {
                SourceHit(pattern: $0, location: Location(path: path, line: line.number))
            }
        }
    }

    /// Where any signal appears: API names in code, phrases and hosts in user-facing text, and
    /// SDK names in linked packages. See `SignalKind` for how a signal is classified.
    func signalHits(_ signals: [String], ruleID: String) -> [SourceHit] {
        let code = signals.filter { SignalKind($0) != .text }
        let text = signals.filter { SignalKind($0) != .code }
        let packages = signals.filter { signal in
            linkedPackages.contains { $0.caseInsensitiveCompare(signal) == .orderedSame }
        }
        let packageHits = packages.map { SourceHit(pattern: $0, location: Location(path: "Package dependencies")) }
        return codeHits(code, ruleID: ruleID) + textHits(text, ruleID: ruleID) + packageHits
    }

    /// String literals and String Catalog entries that contain a phrase as whole words.
    func textHits(_ phrases: [String], ruleID: String) -> [SourceHit] {
        let matchers = phrases.map(TermMatcher.init)
        let literals = literalHits(ruleID: ruleID) { literal in matchers.contains { $0.matches(literal) } }
            .flatMap { hit in
                matchers.filter { $0.matches(hit.pattern) }.map { SourceHit(pattern: $0.term, location: hit.location) }
            }
        let catalog = localizedStrings.flatMap { string in
            matchers.filter { $0.matches(string.text) }.map { SourceHit(pattern: $0.term, location: string.location) }
        }
        return literals + catalog
    }

    private func releaseLines(ruleID: String) -> [(String, SourceLine)] {
        sources.flatMap { file in
            file.releaseLines
                .filter { !file.isIgnored(ruleID, line: $0.number) }
                .map { (file.path, $0) }
        }
    }
}

/// How a rule signal is matched. `ATTrackingManager` and `Auth.auth()` are code; `api.openai.com`
/// and `per week` are text; a bare lowercase word such as `stripe` is either.
enum SignalKind: Equatable {
    case code
    case text
    case either

    init(_ signal: String) {
        let isIdentifier = signal.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if signal.contains(" ") {
            self = .text
        } else if signal.contains("(") || signal.hasPrefix("@") || signal.hasPrefix(".") {
            self = .code
        } else if isIdentifier {
            self = signal.contains { $0.isUppercase || $0 == "_" } ? .code : .either
        } else {
            self = .text
        }
    }
}

struct SymbolMatcher {
    let symbol: String
    private let isIdentifier: Bool
    private let isFunctionName: Bool

    init(_ symbol: String) {
        self.symbol = symbol
        isIdentifier = symbol.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        isFunctionName = isIdentifier && symbol.allSatisfy { $0.isLowercase || $0 == "_" }
    }

    func matches(_ code: String) -> Bool {
        guard isIdentifier else { return code.contains(symbol) }
        var searchRange = code.startIndex..<code.endIndex
        while let range = code.range(of: symbol, range: searchRange) {
            if isBounded(range, in: code) { return true }
            searchRange = range.upperBound..<code.endIndex
        }
        return false
    }

    private func isBounded(_ range: Range<String.Index>, in code: String) -> Bool {
        let before = range.lowerBound > code.startIndex ? code[code.index(before: range.lowerBound)] : nil
        let after = range.upperBound < code.endIndex ? code[range.upperBound] : nil
        if let before, Self.isIdentifierCharacter(before) { return false }
        if let after, Self.isIdentifierCharacter(after) { return false }
        guard isFunctionName else { return true }
        let isMember = before == "."
        let isCalled = code[range.upperBound...].drop { $0 == " " }.first == "("
        return !isMember && isCalled
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// Matches a word or phrase in prose. All-caps terms such as `TODO` match only in capitals, so the
/// Spanish "Todo" does not count; every term must stand as whole words.
struct TermMatcher {
    let term: String
    private let isCaseSensitive: Bool

    init(_ term: String) {
        self.term = term
        isCaseSensitive = term.contains { $0.isLetter } && !term.contains { $0.isLowercase }
    }

    func matches(_ text: String) -> Bool {
        let options: String.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, options: options, range: searchRange) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let startsWord = term.first.map { !$0.isLetter } ?? true || !(before?.isLetter ?? false)
            let endsWord = term.last.map { !$0.isLetter } ?? true || !(after?.isLetter ?? false)
            if startsWord, endsWord { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }
}

// MARK: - Reporting helpers
extension Array where Element == SourceHit {
    /// The first few locations, enough to act on without flooding the report.
    func sample(_ limit: Int = 5) -> [Location] {
        [Location](Set(map(\.location)).sorted().prefix(limit))
    }

    var patterns: [String] {
        Set(map(\.pattern)).sorted()
    }
}
