import Foundation

public struct SwiftModule {
    public let name: String
    public let dir: URL
}

private let excludedComponents: Set<String> = [
    ".build", "DerivedData", "Pods", ".git", "fastlane", ".swiftpm", "Carthage"
]

/// Finds the Swift files belonging to one module, same recursive walk
/// module_map.py does for Kotlin sources (`kotlin_files()`), but excluding
/// Tests the way the Kotlin tool excludes test source sets.
public func swiftFiles(in dir: URL, includeTests: Bool = false) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else { return [] }

    var files: [URL] = []
    for case let url as URL in enumerator {
        let components = Set(url.pathComponents)
        if !components.isDisjoint(with: excludedComponents) { continue }
        if !includeTests && (url.lastPathComponent.hasSuffix("Tests.swift")
            || components.contains("Tests") || components.contains(where: { $0.hasSuffix("Tests") })) {
            continue
        }
        if url.pathExtension == "swift" {
            files.append(url)
        }
    }
    return files.sorted { $0.path < $1.path }
}

/// `module-map.py` reads `settings.gradle.kts` to find Gradle modules; here, the
/// Swift equivalent reads `Package.swift` with a regex (same "Gradle via regex"
/// style limitation the Kotlin tool documents: no manifest execution, no convention
/// plugins). Falls back to treating `root` itself as a single module.
public func discoverModules(root: URL) -> [SwiftModule] {
    let packageManifest = root.appendingPathComponent("Package.swift")
    guard FileManager.default.fileExists(atPath: packageManifest.path),
          let content = try? String(contentsOf: packageManifest, encoding: .utf8)
    else {
        return [SwiftModule(name: root.lastPathComponent, dir: root)]
    }

    let targetNamePattern = #/\.(?:target|executableTarget|testTarget)\s*\(\s*name:\s*"([^"]+)"/#
    var modules: [SwiftModule] = []
    for match in content.matches(of: targetNamePattern) {
        let name = String(match.1)
        let candidate = root.appendingPathComponent("Sources").appendingPathComponent(name)
        let dir = FileManager.default.fileExists(atPath: candidate.path) ? candidate : root
        modules.append(SwiftModule(name: name, dir: dir))
    }
    return modules.isEmpty ? [SwiftModule(name: root.lastPathComponent, dir: root)] : modules
}
