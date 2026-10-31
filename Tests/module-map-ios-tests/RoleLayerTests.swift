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
