import AppStoreReviewKit
import Foundation

enum ExitCode: Int32 {
    case clean = 0
    case findings = 1
    case usage = 2
}

struct UsageError: Error {
    let message: String
}

struct CheckCommand {
    var path = "."
    var format = OutputFormat.text
    var failOn: Severity? = .error
    var loadOptions = LoadOptions()
    var reviewOptions = ReviewOptions()
    var rulebookPath: String?

    init(arguments: [String]) throws(UsageError) {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--format":
                let value = try Self.value(for: argument, from: &remaining)
                guard let parsed = OutputFormat(rawValue: value) else {
                    throw UsageError(message: "--format must be text, json, or sarif")
                }
                format = parsed
            case "--fail-on":
                let value = try Self.value(for: argument, from: &remaining)
                guard value == "never" || Severity(rawValue: value) != nil else {
                    throw UsageError(message: "--fail-on must be error, warning, note, or never")
                }
                failOn = Severity(rawValue: value)
            case "--target":
                loadOptions.target = try Self.value(for: argument, from: &remaining)
            case "--configuration":
                loadOptions.configuration = try Self.value(for: argument, from: &remaining)
            case "--profile":
                reviewOptions.profile = try Self.value(for: argument, from: &remaining)
            case "--trait":
                reviewOptions.traits.insert(try Self.value(for: argument, from: &remaining))
            case "--disable":
                reviewOptions.disabledRules.insert(try Self.value(for: argument, from: &remaining))
            case "--rulebook":
                rulebookPath = try Self.value(for: argument, from: &remaining)
            case let option where option.hasPrefix("-"):
                throw UsageError(message: "Unknown option \(option)")
            default:
                path = argument
            }
        }
    }

    func run() throws(UsageError) -> ExitCode {
        let rulebook = try loadRulebook()
        let root = URL(filePath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw UsageError(message: "\(path) is not a folder. Point asrk at the folder with your Xcode project.")
        }
        let facts = ProjectLoader(options: loadOptions).load(root)
        let report = ReviewEngine(rulebook: rulebook, options: reviewOptions).review(facts)
        Output.write(Reporter.render(report, as: format))
        guard let failOn else { return .clean }
        return report.failing(at: failOn).isEmpty ? .clean : .findings
    }

    private func loadRulebook() throws(UsageError) -> Rulebook {
        do {
            guard let rulebookPath else { return try Rulebook.embedded() }
            return try Rulebook(data: Data(contentsOf: URL(filePath: rulebookPath)))
        } catch {
            throw UsageError(message: "\(error)")
        }
    }

    private static func value(
        for option: String,
        from arguments: inout ArraySlice<String>,
    ) throws(UsageError) -> String {
        guard let value = arguments.popFirst(), !value.hasPrefix("--") else {
            throw UsageError(message: "\(option) needs a value")
        }
        return value
    }
}

struct RulesCommand {
    var guideline: String?
    var format = OutputFormat.text

    init(arguments: [String]) throws(UsageError) {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            guard let value = remaining.popFirst() else {
                throw UsageError(message: "\(argument) needs a value")
            }
            switch argument {
            case "--guideline":
                guideline = value
            case "--format":
                guard let parsed = OutputFormat(rawValue: value), parsed != .sarif else {
                    throw UsageError(message: "--format must be text or json")
                }
                format = parsed
            default:
                throw UsageError(message: "Unknown option \(argument)")
            }
        }
    }

    func run() throws(UsageError) -> String {
        do {
            let rules = RuleReporter.rules(in: try Rulebook.embedded(), guideline: guideline)
            return RuleReporter.list(rules, as: format)
        } catch {
            throw UsageError(message: "\(error)")
        }
    }
}

enum Output {
    static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
