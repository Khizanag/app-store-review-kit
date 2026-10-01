import Foundation

/// Every file under a project root, walked once, sorted, skipping build output and dependencies.
struct ProjectFiles {
    let root: URL
    let relativePaths: [String]
    private let maximumBytes: Int

    init(root: URL, maximumBytes: Int) {
        self.root = root.standardizedFileURL
        self.maximumBytes = maximumBytes
        relativePaths = Self.walk(self.root)
    }

    func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    func paths(named name: String) -> [String] {
        relativePaths.filter { ($0 as NSString).lastPathComponent == name }
    }

    func paths(withExtensions extensions: Set<String>) -> [String] {
        relativePaths.filter { extensions.contains(($0 as NSString).pathExtension) }
    }

    func text(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: url(path)), data.count <= maximumBytes else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    private static func walk(_ root: URL) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return []
        }
        var paths: [String] = []
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true {
                if ProjectLoader.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            paths.append(String(url.standardizedFileURL.path.dropFirst(prefix.count)))
        }
        return paths.sorted()
    }
}

enum PrivacyManifestReader {
    static func read(_ url: URL, path: String, owner: String) -> PrivacyManifest {
        let location = Location(path: path)
        let value: Value
        do {
            value = try Value.parsePropertyList(Data(contentsOf: url))
        } catch {
            return PrivacyManifest(
                location: location,
                owner: owner,
                parseError: error.localizedDescription,
                tracking: nil,
                trackingDomains: [],
                accessedAPIs: [],
                collectedDataTypes: [],
            )
        }
        let accessed = (value["NSPrivacyAccessedAPITypes"]?.array ?? []).compactMap { entry in
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"]?.strings ?? []
            return entry["NSPrivacyAccessedAPIType"]?.string.map {
                PrivacyManifest.AccessedAPI(category: $0, reasons: reasons)
            }
        }
        return PrivacyManifest(
            location: location,
            owner: owner,
            parseError: value.dictionary == nil ? "The root is not a dictionary." : nil,
            tracking: value["NSPrivacyTracking"]?.bool,
            trackingDomains: value["NSPrivacyTrackingDomains"]?.strings ?? [],
            accessedAPIs: accessed,
            collectedDataTypes: value["NSPrivacyCollectedDataTypes"]?.array ?? [],
        )
    }
}

enum StringCatalogReader {
    static func read(_ url: URL, path: String) -> [LocalizedString] {
        guard let data = try? Data(contentsOf: url), let catalog = try? Value.parseJSON(data) else { return [] }
        let sourceLanguage = catalog["sourceLanguage"]?.string ?? "en"
        var strings: [LocalizedString] = []
        for (key, entry) in catalog["strings"]?.dictionary ?? [:] {
            let location = Location(path: path)
            let localizations = entry["localizations"]?.dictionary ?? [:]
            if localizations[sourceLanguage] == nil, !key.isEmpty {
                strings.append(LocalizedString(key: key, text: key, language: sourceLanguage, location: location))
            }
            for (language, localization) in localizations {
                guard let text = localization["stringUnit"]?["value"]?.string else { continue }
                strings.append(LocalizedString(key: key, text: text, language: language, location: location))
            }
        }
        return strings.sorted { ($0.key, $0.language) < ($1.key, $1.language) }
    }
}

/// Dependency names from `Package.resolved` and `Podfile.lock`, used to detect third-party SDKs.
enum PackageListReader {
    static func read(_ files: ProjectFiles) -> Set<String> {
        var names: Set<String> = []
        for path in files.paths(named: "Package.resolved") {
            guard let data = try? Data(contentsOf: files.url(path)), let resolved = try? Value.parseJSON(data) else {
                continue
            }
            let pins = resolved["pins"]?.array ?? resolved["object"]?["pins"]?.array ?? []
            for pin in pins {
                if let identity = pin["identity"]?.string ?? pin["package"]?.string {
                    names.insert(identity)
                }
            }
        }
        for path in files.paths(named: "Podfile.lock") {
            for line in files.text(path)?.split(separator: "\n") ?? [] where line.hasPrefix("  - ") {
                let name = line.dropFirst(4).split(separator: " ").first.map(String.init) ?? ""
                names.insert(name.split(separator: "/").first.map(String.init) ?? name)
            }
        }
        return names
    }
}
