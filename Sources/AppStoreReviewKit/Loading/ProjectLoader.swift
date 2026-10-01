import Foundation

public struct LoadOptions: Sendable {
    public var configuration = "Release"
    public var target: String?
    public var maximumFileBytes = 2_000_000

    public init(configuration: String = "Release", target: String? = nil) {
        self.configuration = configuration
        self.target = target
    }
}

/// Builds `AppFacts` from a project folder: Xcode projects, Info.plist files, privacy manifests,
/// entitlements, sources, String Catalogs, and resolved package lists.
public struct ProjectLoader {
    static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "Pods", "Carthage", "DerivedData", "SourcePackages",
        "node_modules", "xcuserdata", "build", ".claude",
    ]
    static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cpp"]

    public let options: LoadOptions

    public init(options: LoadOptions = LoadOptions()) {
        self.options = options
    }

    public func load(_ root: URL) -> AppFacts {
        var facts = AppFacts(root: root)
        let files = ProjectFiles(root: root, maximumBytes: options.maximumFileBytes)
        let target = loadTarget(files, into: &facts)

        loadInfo(files, target: target, into: &facts)
        facts.manifests = files.paths(named: "PrivacyInfo.xcprivacy").map {
            PrivacyManifestReader.read(files.url($0), path: $0, owner: "app")
        }
        loadEntitlements(files, target: target, into: &facts)
        facts.sources = files.paths(withExtensions: Self.sourceExtensions)
            .filter { !Self.isTestPath($0) }
            .compactMap { path in files.text(path).map { SourceFile(path: path, text: $0) } }
        facts.localizedStrings = files.paths(withExtensions: ["xcstrings"]).flatMap {
            StringCatalogReader.read(files.url($0), path: $0)
        }
        facts.linkedPackages.formUnion(PackageListReader.read(files))
        facts.metadata = MetadataReader.read(files)
        facts.loadedEvidence.formUnion(evidence(for: facts))
        return facts
    }
}

// MARK: - Assembly
private extension ProjectLoader {
    func loadTarget(_ files: ProjectFiles, into facts: inout AppFacts) -> AppTarget? {
        var targets: [AppTarget] = []
        for path in files.paths(named: "project.pbxproj") {
            do {
                let project = try XcodeProject(projectFile: files.url(path), relativePath: path)
                targets += project.applicationTargets(configuration: options.configuration)
                facts.hasProject = true
            } catch {
                facts.notes.append("Skipped an unreadable Xcode project: \(error)")
            }
        }
        if let name = options.target {
            guard let match = targets.first(where: { $0.name == name }) else {
                facts.notes.append("No application target named \(name); using every Info.plist found.")
                return nil
            }
            return match
        }
        if targets.count > 1 {
            let names = targets.map(\.name).joined(separator: ", ")
            facts.notes.append("Several app targets (\(names)); checked \(targets[0].name). Pick one with --target.")
        }
        return targets.first
    }

    func loadInfo(_ files: ProjectFiles, target: AppTarget?, into facts: inout AppFacts) {
        guard let target else {
            for path in files.paths(named: "Info.plist") where !Self.isTestPath(path) {
                merge(plist: files.url(path), path: path, into: &facts.info)
            }
            return
        }
        facts.buildSettings = target.settings
        facts.projectPath = target.projectPath
        facts.linkedPackages.formUnion(target.packageProducts)
        if let infoPath = target.infoPlistPath, files.exists(infoPath) {
            merge(plist: files.url(infoPath), path: infoPath, into: &facts.info)
        }
        let settingsLocation = Location(path: target.projectPath)
        for (key, value) in target.generatedInfoKeys {
            let infoKey = key == "UILaunchScreen_Generation" ? "UILaunchScreen" : key
            facts.info[infoKey] = InfoValue(value: .string(value), location: settingsLocation)
        }
    }

    func loadEntitlements(_ files: ProjectFiles, target: AppTarget?, into facts: inout AppFacts) {
        let declared = target?.settings["CODE_SIGN_ENTITLEMENTS"].flatMap { $0.isEmpty ? nil : $0 }
        let paths = declared.map { [$0] } ?? files.paths(withExtensions: ["entitlements"])
        for path in paths where files.exists(path) {
            merge(plist: files.url(path), path: path, into: &facts.entitlements)
        }
    }

    func merge(plist url: URL, path: String, into values: inout [String: InfoValue]) {
        guard let data = try? Data(contentsOf: url), let plist = try? Value.parsePropertyList(data) else {
            return
        }
        let lines = PlistLineIndex(data: data)
        for (key, value) in plist.dictionary ?? [:] {
            values[key] = InfoValue(value: value, location: Location(path: path, line: lines.line(of: key)))
        }
    }

    func evidence(for facts: AppFacts) -> Set<String> {
        var evidence: Set<String> = ["source"]
        if facts.hasProject || !facts.sources.isEmpty || !facts.info.isEmpty { evidence.insert("project") }
        if !facts.info.isEmpty { evidence.insert("plist") }
        if !facts.manifests.isEmpty { evidence.insert("manifest") }
        if facts.hasProject || !facts.entitlements.isEmpty { evidence.insert("entitlements") }
        if !facts.metadata.isEmpty { evidence.insert("metadata") }
        return evidence
    }

    static func isTestPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasSuffix("Tests") || $0.hasSuffix("UITests") }
    }
}

/// Finds the line of a key in an XML property list so findings can cite `Info.plist:42`.
struct PlistLineIndex {
    private let lines: [Substring]

    init(data: Data) {
        let text = String(bytes: data, encoding: .utf8) ?? ""
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    func line(of key: String) -> Int? {
        let needle = "<key>\(key)</key>"
        return lines.firstIndex { $0.contains(needle) }.map { $0 + 1 }
    }
}
