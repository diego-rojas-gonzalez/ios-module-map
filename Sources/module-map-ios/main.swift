import Foundation
import ModuleMapCore

let startTime = Date()
func log(_ message: String) {
    let elapsed = Date().timeIntervalSince(startTime)
    print("[module_map_ios + \(String(format: "%4.1f", elapsed))s] \(message)")
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("usage: module-map-ios <dir> [-o <output-dir>] [--no-timestamp]")
    exit(1)
}

let inputPath = args.removeFirst()
var outputDir: String? = nil
var includeTimestamp = true

var i = 0
while i < args.count {
    switch args[i] {
    case "-o", "--output":
        i += 1
        if i < args.count { outputDir = args[i] }
    case "--no-timestamp":
        includeTimestamp = false
    default:
        break
    }
    i += 1
}

let root = URL(fileURLWithPath: inputPath).standardizedFileURL
let modules = discoverModules(root: root)

for module in modules {
    let files = swiftFiles(in: module.dir)
    log("\(module.name): parsing \(files.count) files...")

    var parsedFiles: [ParsedFile] = []
    for file in files {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        do {
            let parsed = try parseSwiftFile(at: file.path, relativePath: relative)
            parsedFiles.append(parsed)
        } catch {
            log("warning: could not parse \(relative): \(error)")
        }
    }

    let relativeModuleDir = module.dir.path.replacingOccurrences(of: root.path + "/", with: "")
    let map = buildModuleMap(
        moduleName: module.name, moduleDir: relativeModuleDir,
        parsed: parsedFiles, includeTimestamp: includeTimestamp
    )

    let nodeCount = (map["nodes"] as? [[String: Any]])?.count ?? 0
    let externalCount = (map["external_nodes"] as? [[String: Any]])?.count ?? 0
    let edgeCount = (map["edges"] as? [[String: Any]])?.count ?? 0

    let destination: URL
    if let outputDir {
        let outDirURL = URL(fileURLWithPath: outputDir)
        destination = outDirURL.appendingPathComponent("\(module.name).module-map.json")
    } else {
        destination = module.dir.appendingPathComponent("docs/architecture/\(module.name).module-map.json")
    }

    do {
        try writeJSON(map, to: destination)
        log("\(destination.path): \(nodeCount) nodes, \(externalCount) externals, \(edgeCount) edges")
    } catch {
        log("error writing \(destination.path): \(error)")
    }
}
