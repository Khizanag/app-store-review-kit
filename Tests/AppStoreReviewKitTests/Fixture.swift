@testable import AppStoreReviewKit
import Foundation

/// A throwaway project folder written file by file.
struct Fixture {
    let root: URL

    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "asrk-\(UUID().uuidString)")
        for (path, contents) in files {
            let url = root.appending(path: path)
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    func review(options: ReviewOptions = ReviewOptions(), load: LoadOptions = LoadOptions()) throws -> Report {
        let facts = ProjectLoader(options: load).load(root)
        return ReviewEngine(rulebook: try Rulebook.embedded(), options: options).review(facts)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    static func plist(_ entries: [String: String]) -> String {
        let body = entries.sorted { $0.key < $1.key }
            .map { "  <key>\($0.key)</key>\n  <string>\($0.value)</string>" }
            .joined(separator: "\n")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \(body)
            </dict>
            </plist>
            """
    }

    static func manifest(categories: [String: [String]], tracking: Bool = false) -> String {
        let entries = categories.sorted { $0.key < $1.key }.map { category, reasons in
            let codes = reasons.map { "<string>\($0)</string>" }.joined()
            return """
                <dict><key>NSPrivacyAccessedAPIType</key><string>\(category)</string>
                <key>NSPrivacyAccessedAPITypeReasons</key><array>\(codes)</array></dict>
                """
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
              <key>NSPrivacyTracking</key><\(tracking ? "true" : "false")/>
              <key>NSPrivacyTrackingDomains</key><array/>
              <key>NSPrivacyCollectedDataTypes</key><array/>
              <key>NSPrivacyAccessedAPITypes</key><array>\(entries.joined())</array>
            </dict>
            </plist>
            """
    }
}

// MARK: - Report helpers
extension Report {
    var ruleIDs: Set<String> {
        Set(findings.map(\.ruleID))
    }

    func findings(for ruleID: String) -> [Finding] {
        findings.filter { $0.ruleID == ruleID }
    }
}
