import Foundation

/// One line of a source file, split into code and string literals.
public struct SourceLine: Sendable, Equatable {
    public let number: Int
    /// The line with comments removed and every string literal emptied to `""`.
    public internal(set) var code: String
    public internal(set) var strings: [String]
    /// True inside `#if DEBUG`, which never ships in a release build.
    public internal(set) var isDebugOnly: Bool
    /// Rule ids silenced on this line by `asrk:ignore`.
    public internal(set) var ignoredRules: Set<String>
}

public struct SourceFile: Sendable {
    public let path: String
    public let lines: [SourceLine]

    /// Lines that ship in a release build.
    public var releaseLines: [SourceLine] {
        lines.filter { !$0.isDebugOnly }
    }

    public init(path: String, text: String) {
        self.path = path
        lines = SourceTokenizer(text: text).tokenize()
    }

    public func isIgnored(_ ruleID: String, line: Int) -> Bool {
        guard line > 0, line <= lines.count else { return false }
        let ignored = lines[line - 1].ignoredRules
        return ignored.contains(ruleID) || ignored.contains("all")
    }
}

/// A small lexer for Swift, Objective-C, and C. It does not parse; it only tells code from
/// comments and string literals, which is what keeps pattern rules from firing on prose.
struct SourceTokenizer {
    private static let ignoreMarker = "asrk:ignore"

    private let characters: [Character]
    private var index = 0
    private var lines: [SourceLine]
    private var current = 0
    private var pendingIgnores: Set<String> = []

    init(text: String) {
        characters = Array(text)
        let count = text.split(separator: "\n", omittingEmptySubsequences: false).count
        lines = (1...max(count, 1)).map {
            SourceLine(number: $0, code: "", strings: [], isDebugOnly: false, ignoredRules: [])
        }
    }

    func tokenize() -> [SourceLine] {
        var tokenizer = self
        tokenizer.run()
        tokenizer.markDebugBlocks()
        return tokenizer.lines
    }
}

// MARK: - Lexing
private extension SourceTokenizer {
    mutating func run() {
        while index < characters.count {
            let character = characters[index]
            if character == "\n" {
                newLine()
            } else if starts(with: "//") {
                lineComment()
            } else if starts(with: "/*") {
                blockComment()
            } else if character == "\"" || (character == "#" && rawStringHashes() != nil) {
                stringLiteral()
            } else {
                lines[current].code.append(character)
                index += 1
            }
        }
    }

    mutating func newLine() {
        if lines[current].code.trimmingCharacters(in: .whitespaces).isEmpty {
            lines[min(current + 1, lines.count - 1)].ignoredRules.formUnion(pendingIgnores)
        }
        pendingIgnores = []
        current = min(current + 1, lines.count - 1)
        index += 1
    }

    mutating func lineComment() {
        var text = ""
        while index < characters.count, characters[index] != "\n" {
            text.append(characters[index])
            index += 1
        }
        let rules = Self.ignoredRules(in: text)
        lines[current].ignoredRules.formUnion(rules)
        pendingIgnores.formUnion(rules)
    }

    mutating func blockComment() {
        var depth = 0
        while index < characters.count {
            if starts(with: "/*") {
                depth += 1
                index += 2
            } else if starts(with: "*/") {
                depth -= 1
                index += 2
                if depth == 0 { return }
            } else if characters[index] == "\n" {
                current = min(current + 1, lines.count - 1)
                index += 1
            } else {
                index += 1
            }
        }
    }

    mutating func stringLiteral() {
        let hashes = rawStringHashes() ?? 0
        index += hashes
        let isMultiline = starts(with: "\"\"\"")
        let quote = isMultiline ? "\"\"\"" : "\""
        index += quote.count
        let terminator = quote + String(repeating: "#", count: hashes)
        let startLine = current
        var text = ""
        let interpolation = "\\" + String(repeating: "#", count: hashes) + "("
        while index < characters.count, !starts(with: terminator) {
            let character = characters[index]
            if starts(with: interpolation) {
                index += interpolation.count
                skipInterpolation()
                text.append(" ")
                continue
            }
            if character == "\\", hashes == 0, index + 1 < characters.count {
                text.append(character)
                text.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "\n" {
                if !isMultiline { break }
                current = min(current + 1, lines.count - 1)
            }
            text.append(character)
            index += 1
        }
        index = min(index + terminator.count, characters.count)
        lines[startLine].code.append("\"\"")
        lines[startLine].strings.append(text)
    }

    /// Skips an interpolated expression up to its closing parenthesis; it is code, not text.
    mutating func skipInterpolation() {
        var depth = 1
        while index < characters.count, depth > 0 {
            switch characters[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "\n": current = min(current + 1, lines.count - 1)
            default: break
            }
            index += 1
        }
    }

    func rawStringHashes() -> Int? {
        var count = 0
        while index + count < characters.count, characters[index + count] == "#" {
            count += 1
        }
        let isQuote = index + count < characters.count && characters[index + count] == "\""
        return isQuote ? count : nil
    }

    func starts(with prefix: String) -> Bool {
        var position = index
        for character in prefix {
            guard position < characters.count, characters[position] == character else { return false }
            position += 1
        }
        return true
    }

    static func ignoredRules(in comment: String) -> Set<String> {
        guard let range = comment.range(of: ignoreMarker) else { return [] }
        let list = comment[range.upperBound...]
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
        return list.isEmpty ? ["all"] : Set(list)
    }
}

// MARK: - Conditional compilation
private extension SourceTokenizer {
    /// Marks lines inside `#if DEBUG` (and the `#else` of `#if !DEBUG`) as debug-only.
    mutating func markDebugBlocks() {
        var stack: [(isDebug: Bool, flipsOnElse: Bool)] = []
        for position in lines.indices {
            let directive = lines[position].code.trimmingCharacters(in: .whitespaces)
            if directive.hasPrefix("#if ") {
                let condition = directive.dropFirst(4).trimmingCharacters(in: .whitespaces)
                let isDebug = condition == "DEBUG"
                let isNotDebug = condition == "!DEBUG"
                let inherited = stack.last?.isDebug ?? false
                stack.append((inherited || isDebug, isDebug || isNotDebug))
            } else if directive.hasPrefix("#else"), let top = stack.popLast() {
                let inherited = stack.last?.isDebug ?? false
                stack.append((inherited || (top.flipsOnElse && !top.isDebug), top.flipsOnElse))
            } else if directive.hasPrefix("#endif") {
                _ = stack.popLast()
            } else if stack.last?.isDebug == true {
                lines[position].isDebugOnly = true
            }
        }
    }
}
