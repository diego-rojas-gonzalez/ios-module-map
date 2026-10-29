import Foundation
import SwiftSyntax
import SwiftParser

public struct ParsedFile {
    public var nodes: [[String: Any]] = []
    public var warnings: [String] = []
    public init(nodes: [[String: Any]] = [], warnings: [String] = []) {
        self.nodes = nodes
        self.warnings = warnings
    }
}

/// Parses one Swift file and extracts top-level and nested type declarations,
/// the same shape module_map.py extracts from Kotlin: kind, name, file, lines,
/// supertypes, functions, properties, constructor, role.
/// Syntactic only (no type-checking), same limitation the Kotlin tool documents.
final class DeclVisitor: SyntaxVisitor {
    private(set) var result = ParsedFile()
    private let relativePath: String
    private let converter: SourceLocationConverter
    private var parentStack: [String] = []

    init(relativePath: String, tree: SourceFileSyntax) {
        self.relativePath = relativePath
        self.converter = SourceLocationConverter(fileName: relativePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func lines(of node: some SyntaxProtocol) -> [Int] {
        let start = node.startLocation(converter: converter).line
        let end = node.endLocation(converter: converter).line
        return [start, end]
    }

    private func docComment(from trivia: Trivia) -> String? {
        let docLines = trivia.compactMap { piece -> String? in
            switch piece {
            case .docLineComment(let text):
                return text.trimmingPrefix("///").trimmingCharacters(in: .whitespaces)
            case .lineComment(let text) where text.hasPrefix("///"):
                return text.trimmingPrefix("///").trimmingCharacters(in: .whitespaces)
            default:
                return nil
            }
        }
        return docLines.isEmpty ? nil : docLines.joined(separator: " ")
    }

    private func attributeNames(_ attrs: AttributeListSyntax) -> [String] {
        attrs.compactMap { element -> String? in
            guard case .attribute(let attr) = element else { return nil }
            return attr.attributeName.trimmedDescription
        }
    }

    private func modifierNames(_ mods: DeclModifierListSyntax) -> [String] {
        mods.map { $0.name.text }
    }

    private func visibility(_ mods: [String]) -> String? {
        let known = ["public", "private", "fileprivate", "open"]
        return mods.first { known.contains($0) }
    }

    private func extractMembers(_ members: MemberBlockItemListSyntax) -> (
        functions: [[String: Any]], properties: [[String: Any]],
        constructor: [[String: Any]]?, constructorAnnotations: [String]
    ) {
        var functions: [[String: Any]] = []
        var properties: [[String: Any]] = []
        var constructor: [[String: Any]]? = nil
        var constructorAnnotations: [String] = []

        for item in members {
            if let fn = item.decl.as(FunctionDeclSyntax.self) {
                let mods = modifierNames(fn.modifiers)
                var entry: [String: Any] = [
                    "name": fn.name.text,
                    "signature": (mods + ["func " + fn.name.text + fn.signature.trimmedDescription])
                        .joined(separator: " ")
                ]
                let attrs = attributeNames(fn.attributes)
                if !attrs.isEmpty { entry["annotations"] = attrs }
                if mods.contains("static") || mods.contains("class") { entry["static"] = true }
                if let doc = docComment(from: fn.leadingTrivia) { entry["doc"] = doc }
                functions.append(entry)
            } else if let v = item.decl.as(VariableDeclSyntax.self) {
                let mods = modifierNames(v.modifiers)
                let isVar = v.bindingSpecifier.text == "var"
                let propertyAttrs = attributeNames(v.attributes)
                for binding in v.bindings {
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    var entry: [String: Any] = ["name": pattern.identifier.text]
                    if let type = binding.typeAnnotation?.type.trimmedDescription {
                        entry["type"] = type
                    }
                    if let vis = visibility(mods) { entry["visibility"] = vis }
                    if isVar { entry["mutable"] = true }
                    if !propertyAttrs.isEmpty { entry["annotations"] = propertyAttrs }
                    properties.append(entry)
                }
            } else if let initDecl = item.decl.as(InitializerDeclSyntax.self) {
                let params = initDecl.signature.parameterClause.parameters.map { p -> [String: Any] in
                    let name = p.secondName?.text ?? p.firstName.text
                    return ["name": name, "type": p.type.trimmedDescription]
                }
                // Prefer the richest initializer when several are declared.
                if constructor == nil || params.count > (constructor?.count ?? 0) {
                    constructor = params
                    constructorAnnotations = attributeNames(initDecl.attributes)
                }
            }
        }
        return (functions, properties, constructor, constructorAnnotations)
    }

    private func buildNode(
        name: String, kind: String, modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax, inheritance: InheritanceClauseSyntax?,
        members: MemberBlockItemListSyntax, node: some SyntaxProtocol
    ) -> [String: Any] {
        let fqn = (parentStack + [name]).joined(separator: ".")
        // module_diagrams.py only recognizes Kotlin's own kind vocabulary
        // (class/interface/object/function) to decide what belongs in the
        // layer diagram and the class table. Map Swift's richer kinds onto
        // it so the existing renderer picks these nodes up, and keep the
        // original Swift kind in `swift_kind` so nothing is lost.
        let diagramKind = (kind == "protocol") ? "interface" : "class"
        var entry: [String: Any] = [
            "id": fqn,
            "kind": diagramKind,
            "swift_kind": kind,
            "name": name,
            "file": relativePath,
            "lines": lines(of: node)
        ]
        if let parent = parentStack.last { entry["parent"] = parent }

        let mods = modifierNames(modifiers)
        if !mods.isEmpty { entry["modifiers"] = mods }
        if let vis = visibility(mods) { entry["visibility"] = vis }

        let attrs = attributeNames(attributes)
        if !attrs.isEmpty { entry["annotations"] = attrs }

        if let doc = docComment(from: node.leadingTrivia) { entry["doc"] = doc }

        let supertypes = inheritance?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        if !supertypes.isEmpty { entry["supertypes"] = supertypes }

        let (functions, properties, constructor, ctorAnnotations) = extractMembers(members)
        if !functions.isEmpty { entry["functions"] = functions }
        if !properties.isEmpty { entry["properties"] = properties }
        if let constructor { entry["constructor"] = constructor }
        if !ctorAnnotations.isEmpty { entry["constructor_annotations"] = ctorAnnotations }

        if let role = inferRole(name: name, kind: kind, supertypes: supertypes) {
            entry["role"] = role
        }
        return entry
    }

    private func visitType(
        name: String, kind: String, modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax, inheritance: InheritanceClauseSyntax?,
        members: MemberBlockItemListSyntax, node: some SyntaxProtocol
    ) {
        let built = buildNode(
            name: name, kind: kind, modifiers: modifiers, attributes: attributes,
            inheritance: inheritance, members: members, node: node
        )
        result.nodes.append(built)
        parentStack.append(name)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(
            name: node.name.text, kind: "class", modifiers: node.modifiers,
            attributes: node.attributes, inheritance: node.inheritanceClause,
            members: node.memberBlock.members, node: node
        )
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { parentStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(
            name: node.name.text, kind: "struct", modifiers: node.modifiers,
            attributes: node.attributes, inheritance: node.inheritanceClause,
            members: node.memberBlock.members, node: node
        )
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { parentStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(
            name: node.name.text, kind: "enum", modifiers: node.modifiers,
            attributes: node.attributes, inheritance: node.inheritanceClause,
            members: node.memberBlock.members, node: node
        )
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { parentStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(
            name: node.name.text, kind: "protocol", modifiers: node.modifiers,
            attributes: node.attributes, inheritance: node.inheritanceClause,
            members: node.memberBlock.members, node: node
        )
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { parentStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extensions don't declare a new type; attach their members to the extended type's name
        // without pushing a new node, so functions added in an extension aren't lost nor duplicated
        // as a standalone node.
        let extendedName = node.extendedType.trimmedDescription
        parentStack.append(extendedName)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { parentStack.removeLast() }
}

public func parseSwiftFile(at path: String, relativePath: String) throws -> ParsedFile {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    let visitor = DeclVisitor(relativePath: relativePath, tree: tree)
    visitor.walk(tree)
    return visitor.result
}
