import Foundation

protocol AuthAPI {
    func login(email: String, password: String) async throws -> (token: String, userId: Int)
}

final class SessionStore {
    private var current: Session?

    func save(_ session: Session) {
        current = session
    }

    func clear() {
        current = nil
    }
}

final class AuthRepositoryImpl: AuthRepository {
    private let api: AuthAPI
    private let store: SessionStore

    init(api: AuthAPI, store: SessionStore) {
        self.api = api
        self.store = store
    }

    func login(email: String, password: String) async throws -> Session {
        let result = try await api.login(email: email, password: password)
        let session = Session(token: result.token, userId: result.userId)
        store.save(session)
        return session
    }

    func logout() async throws {
        store.clear()
    }
}
