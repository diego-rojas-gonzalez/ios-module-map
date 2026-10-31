import Foundation

struct CounterState: Equatable {
    var count: Int = 0
    var isLoading: Bool = false
}

enum CounterAction {
    case increment
    case decrement
    case faceResponse(Int)
    case setLoading(isLoading: Bool)
}

@Reducer
struct CounterReducer {
    let api: CounterClient

    func reduce(into state: inout CounterState, action: CounterAction) {
        switch action {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .faceResponse(let value):
            state.count = value
        case .setLoading(let isLoading):
            state.isLoading = isLoading
        }
    }
}

final class CounterEffect {
    let client: CounterClient
    init(client: CounterClient) {
        self.client = client
    }

    func fetchFace() -> Int {
        client.fetchFace()
    }
}

protocol CounterClient {
    func fetchFace() -> Int
}
