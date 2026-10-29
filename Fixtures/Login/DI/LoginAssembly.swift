import Foundation

/// Wires the Login feature's dependency graph.
final class LoginAssembly {
    func resolveLoginUseCase(api: AuthAPI) -> LoginUseCase {
        let store = SessionStore()
        let repository = AuthRepositoryImpl(api: api, store: store)
        return LoginUseCase(repository: repository)
    }
}
