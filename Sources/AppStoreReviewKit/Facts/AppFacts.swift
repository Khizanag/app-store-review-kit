import Foundation

/// A place in the scanned project that a finding points at.
public struct Location: Sendable, Hashable, Comparable {
    public let path: String
    public let line: Int?

    public init(path: String, line: Int? = nil) {
        self.path = path
        self.line = line
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.path, lhs.line ?? 0) < (rhs.path, rhs.line ?? 0)
    }

    public var description: String {
        line.map { "\(path):\($0)" } ?? path
    }
}

/// A value read from Info.plist or from `INFOPLIST_KEY_*` build settings, with where it came from.
public struct InfoValue: Sendable, Equatable {
    public let value: Value
    public let location: Location
}

public struct PrivacyManifest: Sendable {
    public struct AccessedAPI: Sendable, Equatable {
        public let category: String
        public let reasons: [String]
    }

    public let location: Location
    /// The bundle the manifest belongs to: `app`, or a framework or extension name.
    public let owner: String
    public let parseError: String?
    public let tracking: Bool?
    public let trackingDomains: [String]
    public let accessedAPIs: [AccessedAPI]
    public let collectedDataTypes: [Value]
}

/// What the loaders learned about the app. Checks read facts and never touch the disk.
public struct AppFacts: Sendable {
    public var root: URL
    public var info: [String: InfoValue] = [:]
    public var buildSettings: [String: String] = [:]
    /// The `project.pbxproj` the app target came from, when there is one.
    public var projectPath: String?
    public var manifests: [PrivacyManifest] = []
    public var entitlements: [String: InfoValue] = [:]
    public var sources: [SourceFile] = []
    public var localizedStrings: [LocalizedString] = []
    public var metadata = StoreMetadata()
    public var linkedPackages: Set<String> = []
    public var bundledFrameworks: [String: Location] = [:]
    public var hasProject = false
    public var hasBuiltBundle = false
    public var loadedEvidence: Set<String> = []
    public var notes: [String] = []

    public init(root: URL) {
        self.root = root
    }

    public var appManifests: [PrivacyManifest] {
        manifests.filter { $0.owner == "app" }
    }
}

/// A user-facing string from a String Catalog or `.strings` file.
public struct LocalizedString: Sendable, Equatable {
    public let key: String
    public let text: String
    public let language: String
    public let location: Location
}
