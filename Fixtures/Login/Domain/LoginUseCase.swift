import Foundation

struct Session {
    let token: String
    let userId: Int
}

protocol AuthRepository {
    func login(email: String, password: String) async throws -> Session
    func logout() async throws
}

/// Coordinates a login attempt against the configured AuthRepository.
final class LoginUseCase {
    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func invoke(email: String, password: String) async throws -> Session {
        try await repository.login(email: email, password: password)
    }
}
