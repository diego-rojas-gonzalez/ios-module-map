import Testing
@testable import ModuleMapCore

@Test func viewModelRoleByNameSuffix() {
    #expect(inferRole(name: "LoginViewModel", kind: "class", supertypes: []) == "viewmodel")
}

@Test func useCaseRoleByNameSuffix() {
    #expect(inferRole(name: "LoginUseCase", kind: "class", supertypes: []) == "usecase")
}

@Test func layerFallsBackToRoleWhenNoFolderMatches() {
    #expect(inferLayer(filePath: "Sources/Login/LoginUseCase.swift", role: "usecase") == "Domain")
}

@Test func layerFromFolderSegment() {
    #expect(inferLayer(filePath: "Sources/Login/Domain/LoginUseCase.swift", role: nil) == "Domain")
}

@Test func reducerRoleByMacroAnnotationWithNoExplicitConformance() {
    #expect(inferRole(name: "CounterReducer", kind: "struct", supertypes: [], annotations: ["Reducer"]) == "reducer")
    #expect(inferRole(name: "Feature", kind: "struct", supertypes: [], annotations: ["Reducer"]) == "reducer")
}

@Test func actionRoleRequiresEnum() {
    #expect(inferRole(name: "CounterAction", kind: "enum", supertypes: []) == "action")
    #expect(inferRole(name: "LoginIntent", kind: "enum", supertypes: []) == "action")
    #expect(inferRole(name: "TapAction", kind: "class", supertypes: []) == nil)
}

@Test func stateRoleByNameSuffix() {
    #expect(inferRole(name: "CounterState", kind: "struct", supertypes: []) == "state")
    #expect(inferRole(name: "LoginUiState", kind: "enum", supertypes: []) == "state")
}

@Test func effectRoleByNameSuffix() {
    #expect(inferRole(name: "CounterEffect", kind: "class", supertypes: []) == "effect")
    #expect(inferRole(name: "AuthMiddleware", kind: "class", supertypes: []) == "effect")
}

@Test func storeRoleRequiresExplicitConformanceNotBareNameSuffix() {
    #expect(inferRole(name: "SessionStore", kind: "class", supertypes: []) == nil)
    #expect(inferRole(name: "FeatureStore", kind: "class", supertypes: ["Store"]) == "store")
}

// Regression for a real --no-timestamp non-determinism bug: external_nodes
// used to serialize in Dictionary.values order, which Swift's per-process
// hash-seed randomization can reorder run to run on byte-identical source,
// even though the externals *content* was always correct. Pin the output to
// a sorted order so two runs on the same code are byte-identical, as the
// README promises.
@Test func externalNodesAreSortedByIdRegardlessOfInsertionOrder() {
    let node: [String: Any] = [
        "id": "Feature.Widget", "name": "Widget", "kind": "class", "swift_kind": "class",
        "properties": [
            ["name": "z", "type": "Zebra"],
            ["name": "m", "type": "Mango"],
            ["name": "a", "type": "Apple"],
        ],
    ]
    let (_, externals) = buildEdgesAndExternals(nodes: [node])
    let ids = externals.compactMap { $0["id"] as? String }
    #expect(ids == ids.sorted())
    #expect(ids == ["Apple", "Mango", "Zebra"])
}
