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

// Pass 1: parse every module first, so edge resolution (pass 2) can tell a
// reference to a sibling module's type ("project") apart from one that
// matches nothing in this run ("library") — needed even for a single-module
// run so `calls`/`depends_on` edges can resolve against that module's own
// freshly-parsed nodes before anything is written.
var parsedByModule: [String: [ParsedFile]] = [:]
var registry: GlobalRegistry = [:]

for module in modules {
    let files = swiftFiles(in: module.dir)
    log("\(module.name): parsing \(files.count) files...")

    var parsedFiles: [ParsedFile] = []
    for file in files {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        do {
            let parsed = try parseSwiftFile(at: file.path, relativePath: relative, moduleName: module.name)
            parsedFiles.append(parsed)
        } catch {
            log("warning: could not parse \(relative): \(error)")
        }
    }
    parsedByModule[module.name] = parsedFiles

    for file in parsedFiles {
        for node in file.nodes {
            guard let name = node["name"] as? String, let id = node["id"] as? String else { continue }
            registry[name, default: []].append(GlobalEntry(module: module.name, id: id))
        }
    }
}

let allModuleNames = modules.map { $0.name }

// Pass 2: build and write each module's map now that the registry covers
// every module discovered in this run.
for module in modules {
    let parsedFiles = parsedByModule[module.name] ?? []
    let relativeModuleDir = module.dir.path.replacingOccurrences(of: root.path + "/", with: "")
    let map = buildModuleMap(
        moduleName: module.name, moduleDir: relativeModuleDir,
        parsed: parsedFiles, includeTimestamp: includeTimestamp,
        registry: registry, allModules: allModuleNames
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
