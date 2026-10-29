import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    var onLoggedIn: () -> Void

    var body: some View {
        LoginForm(state: viewModel.state) { email, password in
            Task { await viewModel.submit(email: email, password: password) }
        }
    }
}

struct LoginForm: View {
    let state: LoginUiState
    var onSubmit: (String, String) -> Void

    var body: some View {
        Text("login form")
    }
}
