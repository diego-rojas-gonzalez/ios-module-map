import Foundation

/// Swift types too common to be worth a graph edge — the equivalent of the
/// Kotlin tool quietly ignoring kotlin.* / java.lang.* collaborators.
private let skipTypes: Set<String> = [
    "String", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "Double", "Float",
    "Bool", "Void", "Any", "AnyObject", "Self", "Data", "URL", "Date", "UUID",
    "CGFloat", "NSObject", "Error", "Character", "Array", "Dictionary", "Set", "Optional"
]

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

public func buildEdgesAndExternals(nodes: [[String: Any]]) -> (edges: [[String: Any]], externals: [[String: Any]]) {
    var localIds: [String: String] = [:]
    for n in nodes {
        if let name = n["name"] as? String, let id = n["id"] as? String { localIds[name] = id }
    }

    var edges: [[String: Any]] = []
    var externalsByName: [String: [String: Any]] = [:]

    func targetId(for name: String) -> String { localIds[name] ?? name }
    func registerExternalIfNeeded(_ name: String) {
        guard localIds[name] == nil, externalsByName[name] == nil else { return }
        externalsByName[name] = ["id": name, "name": name, "origin": "library"]
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
            if skipTypes.contains(base) || !isGraphWorthy(base) { continue }
            registerExternalIfNeeded(base)
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
                if skipTypes.contains(base) || !isGraphWorthy(base) { continue }
                registerExternalIfNeeded(base)
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
                if skipTypes.contains(base) || !isGraphWorthy(base) || base == (node["name"] as? String ?? "") { continue }
                registerExternalIfNeeded(base)
                edges.append([
                    "from": fromId, "to": targetId(for: base), "kind": "uses_type",
                    "provenance": ["ast"], "weight": 1
                ])
            }
        }
    }
    return (edges, Array(externalsByName.values))
}

private let legend: [String: Any] = [
    "edge_kinds": [
        "extends": "subclass of (superclass only, first inherited type on a class)",
        "implements": "protocol conformance",
        "depends_on": "collaborator received through an initializer parameter",
        "uses_type": "the type appears in a stored property",
        "calls": "reserved — not extracted in this version (needs a call-graph index)",
        "instantiates": "reserved — not extracted in this version"
    ],
    "provenance": [
        "ast": "read from the module's syntax tree (swift-syntax)"
    ],
    "external_nodes.origin": "this version marks every unresolved type as \"library\" — it does not yet cross-reference other modules to tell project types apart from framework ones",
    "weight": "number of aggregated occurrences on the edge",
    "visibility": "if absent, the declaration is internal (Swift's default)"
]

public func buildModuleMap(moduleName: String, moduleDir: String, parsed: [ParsedFile], includeTimestamp: Bool) -> [String: Any] {
    let allNodes = parsed.flatMap { $0.nodes }
    let (edges, externals) = buildEdgesAndExternals(nodes: allNodes)

    var map: [String: Any] = [
        "schema": "module-map/1",
        "legend": legend,
        "module": ["name": moduleName, "dir": moduleDir, "type": "spm-or-folder"],
        "sources": ["ast": ["parser": "swift-syntax", "files": parsed.count]],
        "nodes": allNodes,
        "external_nodes": externals,
        "edges": edges
    ]
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
