import Foundation

/// Pushes the login flow's screens and hands control back once it's done.
final class LoginCoordinator {
    private let assembly: LoginAssembly

    init(assembly: LoginAssembly) {
        self.assembly = assembly
    }

    func start() {}
}
