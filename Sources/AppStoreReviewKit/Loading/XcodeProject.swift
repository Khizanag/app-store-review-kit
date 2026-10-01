import Foundation

/// An application target read from `project.pbxproj`, with its build settings resolved for one configuration.
public struct AppTarget: Sendable, Equatable {
    public let name: String
    public let projectPath: String
    public let settings: [String: String]
    public let packageProducts: [String]

    public var infoPlistPath: String? {
        settings["INFOPLIST_FILE"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Info.plist keys Xcode generates from `INFOPLIST_KEY_*` build settings.
    public var generatedInfoKeys: [String: String] {
        let prefix = "INFOPLIST_KEY_"
        var keys: [String: String] = [:]
        for (setting, value) in settings where setting.hasPrefix(prefix) {
            keys[String(setting.dropFirst(prefix.count))] = value
        }
        return keys
    }
}

enum XcodeProjectError: Error, Equatable {
    case unreadable(String)
}

/// Reads application targets from an Xcode project without Xcode.
struct XcodeProject {
    static let applicationType = "com.apple.product-type.application"

    let path: String
    let objects: [String: Value]
    let rootObject: [String: Value]

    init(projectFile: URL, relativePath: String) throws(XcodeProjectError) {
        let root: Value
        do {
            root = try Value.parsePropertyList(Data(contentsOf: projectFile))
        } catch {
            throw .unreadable("\(relativePath): \(error.localizedDescription)")
        }
        guard let objects = root["objects"]?.dictionary,
              let rootID = root["rootObject"]?.string,
              let rootObject = objects[rootID]?.dictionary
        else {
            throw .unreadable("\(relativePath): no root object")
        }
        path = relativePath
        self.objects = objects
        self.rootObject = rootObject
    }

    func applicationTargets(configuration: String) -> [AppTarget] {
        let projectList = rootObject["buildConfigurationList"]?.string
        let projectSettings = settings(listID: projectList, configuration: configuration)
        let base = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        return (rootObject["targets"]?.strings ?? [])
            .compactMap { objects[$0]?.dictionary }
            .filter { $0["productType"]?.string == Self.applicationType }
            .map { target in
                let name = target["name"]?.string ?? "App"
                let targetList = target["buildConfigurationList"]?.string
                var merged = projectSettings
                for (key, value) in settings(listID: targetList, configuration: configuration) {
                    merged[key] = value
                        .replacingOccurrences(of: "$(inherited)", with: projectSettings[key] ?? "")
                        .trimmingCharacters(in: .whitespaces)
                }
                let resolved = Self.expand(merged, builtIns: [
                    "TARGET_NAME": name,
                    "PRODUCT_NAME": merged["PRODUCT_NAME"] ?? name,
                    "SRCROOT": base,
                    "PROJECT_DIR": base,
                ])
                return AppTarget(
                    name: name,
                    projectPath: path,
                    settings: resolved,
                    packageProducts: packageProducts(target),
                )
            }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Helpers
private extension XcodeProject {
    func settings(listID: String?, configuration: String) -> [String: String] {
        guard let listID, let list = objects[listID]?.dictionary else { return [:] }
        let configurations = (list["buildConfigurations"]?.strings ?? []).compactMap { objects[$0]?.dictionary }
        let chosen = configurations.first { $0["name"]?.string == configuration } ?? configurations.first
        var settings: [String: String] = [:]
        for (key, value) in chosen?["buildSettings"]?.dictionary ?? [:] {
            settings[Self.unconditionalKey(key)] = value.string ?? value.strings.joined(separator: " ")
        }
        return settings
    }

    func packageProducts(_ target: [String: Value]) -> [String] {
        (target["packageProductDependencies"]?.strings ?? [])
            .compactMap { objects[$0]?["productName"]?.string }
    }

    /// `KEY[sdk=iphoneos*]` settings count as `KEY`; the engine checks what any build could ship.
    static func unconditionalKey(_ key: String) -> String {
        key.split(separator: "[", maxSplits: 1).first.map(String.init) ?? key
    }

    /// Expands `$(VAR)` and `${VAR}` until nothing changes, so values that reference other settings resolve.
    static func expand(_ settings: [String: String], builtIns: [String: String]) -> [String: String] {
        var values = builtIns.merging(settings) { _, setting in setting }
        for _ in 0..<4 {
            var changed = false
            for (key, value) in values {
                let expanded = expand(value, with: values)
                if expanded != value {
                    values[key] = expanded
                    changed = true
                }
            }
            if !changed { break }
        }
        return values
    }

    static func expand(_ value: String, with values: [String: String]) -> String {
        var result = value
        var replacements = 0
        for (open, close) in [("$(", ")"), ("${", "}")] {
            while replacements < 32,
                  let start = result.range(of: open),
                  let end = result.range(of: close, range: start.upperBound..<result.endIndex) {
                replacements += 1
                let name = String(result[start.upperBound..<end.lowerBound])
                let base = name.split(separator: ":").first.map(String.init) ?? name
                result.replaceSubrange(start.lowerBound..<end.upperBound, with: values[base] ?? "")
            }
        }
        return result
    }
}
