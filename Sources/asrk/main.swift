import AppStoreReviewKit
import Foundation

let usage = """
    asrk: check an app against Apple's App Review Guidelines before you submit.

    Usage:
      asrk check [folder] [options]   Review the Xcode project in a folder (default: current folder).
      asrk rules                      List every rule in the embedded rulebook.
      asrk version                    Print the engine and guidelines versions.

    Options for check:
      --format text|json|sarif        Output format (default: text).
      --fail-on error|warning|note|never
                                      Exit 1 when a finding reaches this severity (default: error).
      --target NAME                   App target to check when the project has several.
      --configuration NAME            Build configuration to read (default: Release).
      --profile NAME                  App type: utility, subscription, social, kids, game, ai, health, fintech.
      --trait NAME                    Treat the app as having a trait; repeatable.
      --disable RULE                  Skip a rule; repeatable.
      --rulebook PATH                 Use a rulebook.json instead of the embedded one.

    Silence one finding in code with a comment on the line or the line above:
      // asrk:ignore <rule-id>

    """

let version = "0.1.0"
let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "check":
        let command = try CheckCommand(arguments: Array(arguments.dropFirst()))
        exit(try command.run().rawValue)
    case "rules":
        let rulebook = try Rulebook.embedded()
        let lines = rulebook.rules.map { rule in
            let kind = rule.isManual ? "manual" : "check \(rule.check?.id ?? "")"
            return "\(rule.id)\t\(rule.severity.rawValue)\t\(kind)\t\(rule.title)"
        }
        Output.write(lines.joined(separator: "\n") + "\n")
    case "version", "--version":
        let rulebook = try Rulebook.embedded()
        Output.write("asrk \(version), \(rulebook.rules.count) rules, guidelines \(rulebook.guidelinesRevision)\n")
    case nil, "help", "--help", "-h":
        Output.write(usage)
    case let other?:
        throw UsageError(message: "Unknown command \(other). Run asrk help.")
    }
} catch let error as UsageError {
    Output.error("asrk: \(error.message)")
    exit(ExitCode.usage.rawValue)
} catch {
    Output.error("asrk: \(error)")
    exit(ExitCode.usage.rawValue)
}
