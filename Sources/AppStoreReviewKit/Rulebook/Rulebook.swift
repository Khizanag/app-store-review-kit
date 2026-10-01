import Foundation

public enum RulebookError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case malformed(String)
    case unsupportedSchema(Int)

    public var description: String {
        switch self {
        case let .unreadable(reason): "Cannot read the rulebook: \(reason)"
        case let .malformed(reason): "Malformed rulebook: \(reason)"
        case let .unsupportedSchema(version): "Rulebook schema \(version) is newer than this engine supports"
        }
    }
}

public struct Rulebook: Sendable {
    public static let supportedSchemaVersion = 1

    public let guidelinesRevision: String
    public let rules: [Rule]
    public let catalogs: [String: Value]

    public init(data: Data) throws(RulebookError) {
        let root: Value
        do {
            root = try Value.parseJSON(data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        guard let version = root["schema_version"].flatMap(\.number).map(Int.init) else {
            throw .malformed("missing schema_version")
        }
        guard version <= Self.supportedSchemaVersion else {
            throw .unsupportedSchema(version)
        }
        guidelinesRevision = root["guidelines_revision"]?.string ?? "unknown"
        catalogs = root["catalogs"]?.dictionary ?? [:]
        var rules: [Rule] = []
        for value in root["rules"]?.array ?? [] {
            rules.append(try Rule(value))
        }
        self.rules = rules
    }

    /// The rulebook compiled into this engine by `rulebook build`.
    public static func embedded() throws(RulebookError) -> Rulebook {
        try Rulebook(data: Data(EmbeddedRulebook.json.utf8))
    }

    public func rule(_ id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    /// The entries of a catalog list, for example `catalog("traits", list: "traits")`.
    public func catalog(_ name: String, list: String) -> [Value] {
        catalogs[name]?[list]?.array ?? []
    }
}

// MARK: - Value helpers
extension Value {
    var number: Double? {
        if case let .number(value) = self { value } else { nil }
    }
}
