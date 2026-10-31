import Foundation

/// Swift types too common to count as a real collaborator — the equivalent
/// of the Kotlin tool quietly ignoring kotlin.* / java.lang.* collaborators.
/// Named after the domain term the JSON legend itself uses for `depends_on`
/// ("collaborator received through an initializer parameter").
private let nonCollaboratorTypes: Set<String> = [
    "String", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "Double", "Float",
    "Bool", "Void", "Any", "AnyObject", "Self", "Data", "URL", "Date", "UUID",
    "CGFloat", "NSObject", "Error", "Character", "Array", "Dictionary", "Set", "Optional"
]

/// Where one declaration lives, for cross-module edge resolution.
public struct GlobalEntry {
    public let module: String
    public let id: String
    public init(module: String, id: String) {
        self.module = module
        self.id = id
    }
}
/// Simple type name -> every module that declares it. Built once across all
/// modules of a run (see main.swift) so a reference to a sibling module's
/// type resolves to `origin: "project"` instead of a guessed "library".
public typealias GlobalRegistry = [String: [GlobalEntry]]

/// Strips Optional/force-unwrap sigils and generic wrappers down to a single
/// best-guess type name. Syntactic only — same tradeoff as the rest of this tool.
public func baseTypeName(_ raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasSuffix("?") || t.hasSuffix("!") { t.removeLast() }
    if t.hasPrefix("[") && t.hasSuffix("]") {
        t = String(t.dropFirst().dropLast())
        if let colonIdx = t.firstIndex(of: ":") { t = String(t[..<colonIdx]) }
    }
    if let openIdx = t.firstIndex(of: "<") {
        t = String(t[..<openIdx])
    }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Closures (`() -> Void`) and opaque return types (`some View`) aren't a
/// named declaration anywhere, so they make noisy, meaningless graph nodes.
private func isGraphWorthy(_ typeName: String) -> Bool {
    !typeName.isEmpty && !typeName.contains("->") && !typeName.contains(" ") && !typeName.contains("(")
}

public func buildEdgesAndExternals(
    nodes: [[String: Any]], registry: GlobalRegistry = [:], currentModule: String = ""
) -> (edges: [[String: Any]], externals: [[String: Any]]) {
    var localIds: [String: String] = [:]
    for n in nodes {
        if let name = n["name"] as? String, let id = n["id"] as? String { localIds[name] = id }
    }

    var edges: [[String: Any]] = []
    var externalsById: [String: [String: Any]] = [:]

    // Local (same module) wins outright. Otherwise, a name declared in
    // exactly one other module resolves there (`origin: "project"`); an
    // ambiguous name (declared in several modules) or one found nowhere
    // falls back to `"library"` — a guessed cross-module link is worse
    // than none, same "missing arrow > false arrow" rule the Kotlin tool
    // documents for its own codegraph edge validation.
    func resolve(_ name: String) -> (id: String, external: [String: Any]?) {
        if let localId = localIds[name] { return (localId, nil) }
        if let entries = registry[name], entries.count == 1, let entry = entries.first, entry.module != currentModule {
            return (entry.id, ["id": entry.id, "name": name, "origin": "project", "module": entry.module])
        }
        return (name, ["id": name, "name": name, "origin": "library"])
    }

    func targetId(for name: String) -> String {
        let (id, external) = resolve(name)
        if let external, externalsById[id] == nil { externalsById[id] = external }
        return id
    }

    for node in nodes {
        guard let fromId = node["id"] as? String else { continue }
        // Only an actual `class` can have a superclass; structs/enums/protocols
        // only ever conform to protocols, regardless of the Kotlin-compatible
        // `kind` written to the node (see swift_kind in SwiftFileParser.swift).
        let swiftKind = node["swift_kind"] as? String ?? node["kind"] as? String ?? ""

        let supertypes = node["supertypes"] as? [String] ?? []
        for (idx, raw) in supertypes.enumerated() {
            let base = baseTypeName(raw)
            if nonCollaboratorTypes.contains(base) || !isGraphWorthy(base) { continue }
            let edgeKind = (swiftKind == "class" && idx == 0) ? "extends" : "implements"
            edges.append([
                "from": fromId, "to": targetId(for: base), "kind": edgeKind,
                "provenance": ["ast"], "weight": 1
            ])
        }

        if let ctor = node["constructor"] as? [[String: Any]] {
            for param in ctor {
                guard let rawType = param["type"] as? String, let pname = param["name"] as? String else { continue }
                let base = baseTypeName(rawType)
                if nonCollaboratorTypes.contains(base) || !isGraphWorthy(base) { continue }
                edges.append([
                    "from": fromId, "to": targetId(for: base), "kind": "depends_on",
                    "provenance": ["ast"], "weight": 1,
                    "details": [["via": "init", "name": pname, "di": true]]
                ])
            }
        }

        if let props = node["properties"] as? [[String: Any]] {
            for prop in props {
                guard let rawType = prop["type"] as? String else { continue }
                let base = baseTypeName(rawType)
                if nonCollaboratorTypes.contains(base) || !isGraphWorthy(base) || base == (node["name"] as? String ?? "") { continue }
                edges.append([
                    "from": fromId, "to": targetId(for: base), "kind": "uses_type",
                    "provenance": ["ast"], "weight": 1
                ])
            }
        }

        if let calls = node["_calls"] as? [[String: Any]] {
            for call in calls {
                guard let rawType = call["type"] as? String, let fn = call["function"] as? String,
                      let method = call["method"] as? String else { continue }
                let base = baseTypeName(rawType)
                if nonCollaboratorTypes.contains(base) || !isGraphWorthy(base) { continue }
                // module_diagrams.py's flow/sequence builders read `from`/`to`
                // as the caller/callee *function* names (not node ids) and an
                // optional `line` to order a sequence trace.
                var detail: [String: Any] = ["from": fn, "to": method]
                if let line = call["line"] as? Int { detail["line"] = line }
                edges.append([
                    "from": fromId, "to": targetId(for: base), "kind": "calls",
                    "provenance": ["ast"], "weight": 1,
                    "details": [detail]
                ])
            }
        }
    }
    return (edges, Array(externalsById.values))
}

private let legend: [String: Any] = [
    "edge_kinds": [
        "extends": "subclass of (superclass only, first inherited type on a class)",
        "implements": "protocol conformance",
        "depends_on": "collaborator received through an initializer parameter",
        "uses_type": "the type appears in a stored property",
        "calls": "a method is called on self, a property, or an init parameter — resolved by the receiver's declared type, same rule as android-module-map's codegraph edge validation",
        "instantiates": "reserved — not extracted in this version"
    ],
    "provenance": [
        "ast": "read from the module's syntax tree (swift-syntax)"
    ],
    "external_nodes.origin": "\"project\" = exactly one other module in this run declares the type; \"library\" = not found in this run (a framework, an external SPM package, or an ambiguous name declared in several modules)",
    "weight": "number of aggregated occurrences on the edge",
    "visibility": "if absent, the declaration is internal (Swift's default)"
]

public func buildModuleMap(
    moduleName: String, moduleDir: String, parsed: [ParsedFile], includeTimestamp: Bool,
    registry: GlobalRegistry = [:], allModules: [String] = []
) -> [String: Any] {
    let rawNodes = parsed.flatMap { $0.nodes }
    let (edges, externals) = buildEdgesAndExternals(nodes: rawNodes, registry: registry, currentModule: moduleName)
    let publicNodes = rawNodes.map { node -> [String: Any] in
        var n = node
        n.removeValue(forKey: "_calls")
        return n
    }

    var map: [String: Any] = [
        "schema": "module-map/1",
        "legend": legend,
        "module": ["name": moduleName, "dir": moduleDir, "type": "spm-or-folder"],
        "sources": ["ast": ["parser": "swift-syntax", "files": parsed.count]],
        "nodes": publicNodes,
        "external_nodes": externals,
        "edges": edges
    ]
    if !allModules.isEmpty {
        map["project"] = ["modules": allModules.sorted()]
    }
    if includeTimestamp {
        map["generated_at"] = ISO8601DateFormatter().string(from: Date())
    }
    return map
}

public func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: url)
}
