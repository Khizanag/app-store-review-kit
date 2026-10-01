@testable import AppStoreReviewKit
import Testing

@Suite("Source tokenizer")
struct SourceTokenizerTests {
    @Test
    func separatesCodeStringsAndComments() {
        let text = #"let defaults = UserDefaults.standard // UserDefaults in a comment"#
        let file = SourceFile(path: "A.swift", text: text)
        #expect(file.lines[0].code == "let defaults = UserDefaults.standard ")
        #expect(file.lines[0].strings.isEmpty)

        let literal = SourceFile(path: "B.swift", text: #"let url = "http://localhost:8080" + value"#)
        #expect(literal.lines[0].code == #"let url = "" + value"#)
        #expect(literal.lines[0].strings == ["http://localhost:8080"])
    }

    @Test
    func handlesBlockCommentsAndMultilineStrings() {
        let text = """
            /* AVCaptureDevice
               /* nested */ still a comment */
            let a = \"\"\"
            line one
            line two
            \"\"\"
            let b = #"raw "quoted" text"#
            """
        let file = SourceFile(path: "C.swift", text: text)
        #expect(file.lines[0].code.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(file.lines[1].code.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(file.lines[2].strings.count == 1)
        #expect(file.lines[2].strings[0].contains("line two"))
        #expect(file.lines[6].strings == [#"raw "quoted" text"#])
    }

    @Test
    func keepsEscapedQuotesInsideStrings() {
        let file = SourceFile(path: "D.swift", text: #"let s = "say \"hi\"" ; let t = 1"#)
        #expect(file.lines[0].strings == [#"say \"hi\""#])
        #expect(file.lines[0].code.hasSuffix("; let t = 1"))
    }

    @Test
    func marksDebugOnlyLines() {
        let text = """
            #if DEBUG
            let host = "http://localhost"
            #else
            let host = "https://example.com"
            #endif
            #if !DEBUG
            let release = true
            #else
            let debug = true
            #endif
            """
        let flags = SourceFile(path: "E.swift", text: text).lines.map(\.isDebugOnly)
        #expect(flags == [false, true, false, false, false, false, false, false, true, false])
    }

    @Test
    func readsIgnoreDirectives() {
        let text = """
            // asrk:ignore build.debug-endpoints
            let host = "http://localhost"
            let other = "http://localhost" // asrk:ignore build.debug-endpoints, network.ipv4-literals
            let third = "http://localhost"
            """
        let file = SourceFile(path: "F.swift", text: text)
        #expect(file.isIgnored("build.debug-endpoints", line: 2))
        #expect(file.isIgnored("network.ipv4-literals", line: 3))
        #expect(!file.isIgnored("build.debug-endpoints", line: 4))
        #expect(!file.isIgnored("build.debug-endpoints", line: 99))
    }

    @Test
    func dropsInterpolatedCodeFromStrings() {
        let file = SourceFile(path: "G.swift", text: #"let s = LocalizedStringResource("\(placeholder: .int) loans")"#)
        #expect(file.lines[0].strings == ["  loans"])
    }

    @Test(arguments: [
        ("TODO", "TODO: write copy", true),
        ("TODO", "Todo en orden", false),
        ("lorem ipsum", "Lorem Ipsum dolor", true),
        ("test", "The latest release", false),
        ("test", "test", true),
        ("placeholder", "Placeholder title", true),
    ])
    func matchesTermsAsWholeWords(term: String, text: String, matches: Bool) {
        #expect(TermMatcher(term).matches(text) == matches)
    }

    @Test(arguments: [
        ("stat(path, &info)", true),
        ("let stat = 3", false),
        ("object.stat(x)", false),
        ("UserDefaults.standard", true),
        ("MyUserDefaultsStore()", false),
        ("x.creationDate", true),
    ])
    func matchesSymbolsOnWordBoundaries(code: String, matches: Bool) {
        let symbol = ["stat", "UserDefaults", "creationDate"].first { code.contains($0) } ?? ""
        #expect(SymbolMatcher(symbol).matches(code) == matches)
    }
}
