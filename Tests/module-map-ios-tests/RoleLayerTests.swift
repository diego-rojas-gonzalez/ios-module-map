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
