import Foundation
import Combine

/// Coordinates the login flow and exposes state to the view.
final class LoginViewModel: ObservableObject {
    @Published var state: LoginUiState = .idle

    private let useCase: LoginUseCase

    init(useCase: LoginUseCase) {
        self.useCase = useCase
    }

    /// Launches the login attempt with the given credentials.
    func submit(email: String, password: String) async {
        state = .loading
        do {
            let session = try await useCase.invoke(email: email, password: password)
            state = .success(session)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

enum LoginUiState {
    case idle
    case loading
    case success(Session)
    case error(String)
}
