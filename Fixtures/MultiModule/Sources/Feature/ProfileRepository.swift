import Foundation
import Core

final class ProfileRepository {
    private let client: NetworkClient

    init(client: NetworkClient) {
        self.client = client
    }

    func load() {
        client.fetch()
    }
}
