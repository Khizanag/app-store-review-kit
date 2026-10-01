import Foundation

/// Store listing text per locale, read from a fastlane-style `metadata/` folder:
/// `metadata/<locale>/name.txt`, `subtitle.txt`, `keywords.txt`, and so on, plus `review_information/`.
public struct StoreMetadata: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public let text: String
        public let location: Location
    }

    /// Fields keyed by locale, then by field name: `name`, `subtitle`, `description`, `keywords`,
    /// `promotional_text`, `release_notes`, `support_url`, `marketing_url`, `privacy_policy_url`.
    public var locales: [String: [String: Field]] = [:]
    /// `review_information/*.txt`: `demo_user`, `demo_password`, `notes`, and contact fields.
    public var reviewInformation: [String: Field] = [:]

    public var isEmpty: Bool {
        locales.isEmpty && reviewInformation.isEmpty
    }

    /// Every value of one field across locales, sorted by locale.
    public func values(of field: String) -> [(locale: String, field: Field)] {
        locales.keys.sorted().compactMap { locale in
            locales[locale]?[field].map { (locale, $0) }
        }
    }
}

enum MetadataReader {
    static let fileNames: [String: String] = [
        "name.txt": "name",
        "subtitle.txt": "subtitle",
        "description.txt": "description",
        "keywords.txt": "keywords",
        "promotional_text.txt": "promotional_text",
        "release_notes.txt": "release_notes",
        "support_url.txt": "support_url",
        "marketing_url.txt": "marketing_url",
        "privacy_url.txt": "privacy_policy_url",
    ]

    static func read(_ files: ProjectFiles) -> StoreMetadata {
        var metadata = StoreMetadata()
        for path in files.relativePaths {
            let components = path.split(separator: "/").map(String.init)
            guard components.count >= 3,
                  components[components.count - 3] == "metadata",
                  let text = files.text(path)?.trimmingCharacters(in: .whitespacesAndNewlines)
            else { continue }
            let folder = components[components.count - 2]
            let file = components[components.count - 1]
            let field = StoreMetadata.Field(text: text, location: Location(path: path))
            if folder == "review_information" {
                metadata.reviewInformation[String(file.dropLast(4))] = field
            } else if let name = fileNames[file] {
                metadata.locales[folder, default: [:]][name] = field
            }
        }
        return metadata
    }
}
