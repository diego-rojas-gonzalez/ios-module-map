import Foundation

/// Heuristics for role/layer inference, mirroring android-module-map's
/// by_segment / by_role fallback chain (see .module-map.toml in that repo).
/// These are defaults; a future `.module-map.toml` reader can override them.

public func inferRole(
    name: String, kind: String, supertypes: [String], annotations: [String] = []
) -> String? {
    let supers = Set(supertypes)
    let attrs = Set(annotations)

    // MVI/TCA vocabulary — checked first and against both `supers` and
    // `attrs` because the macro form (`@Reducer struct Feature { ... }`)
    // adds the `Reducer` conformance via an invisible extension: the
    // explicit `: Reducer`/`: ReducerProtocol` never appears in the source
    // this tool actually parses, only the attribute does. None of these
    // have a Kotlin analog (same situation as "coordinator"), so they stay
    // iOS-specific — see .module-map.toml's [layers.by_role] override.
    if attrs.contains("Reducer") || supers.contains("Reducer") || supers.contains("ReducerProtocol") {
        return "reducer"
    }
    if name.hasSuffix("Reducer") { return "reducer" }
    // Bare `*Store` name-suffix is deliberately NOT enough here: "Store" is
    // common iOS vocabulary for plain caches/persistence (e.g. `SessionStore`
    // in Fixtures/Login, unrelated to MVI) with no Reducer/Action/State in
    // sight, and TCA's own `Store`/`StoreOf<Feature>` is rarely subclassed by
    // user code — it's consumed as a property type, not redeclared. Require
    // an explicit, intentional conformance instead.
    if supers.contains("Store") { return "store" }
    if kind == "enum" && (name.hasSuffix("Action") || name.hasSuffix("Intent")) { return "action" }
    if name.hasSuffix("State") && (kind == "struct" || kind == "enum") { return "state" }
    if name.hasSuffix("Effect") || name.hasSuffix("Middleware") { return "effect" }

    // Reuse android-module-map's own role vocabulary wherever there's a direct
    // analog, so module_diagrams.py's built-in by_role defaults (calibrated for
    // Kotlin/Android) already place these in the right layer with no extra
    // config. "coordinator" has no Kotlin analog, so it stays iOS-specific —
    // see .module-map.toml's [layers.by_role] override for it.
    if supers.contains("UIViewController") || name.hasSuffix("ViewController") {
        return "activity"
    }
    if supers.contains("View") || name.hasSuffix("Screen") {
        return "composable"
    }
    if name.hasSuffix("ViewModel") || supers.contains("ObservableObject") {
        return "viewmodel"
    }
    if name.hasSuffix("UseCase") || name.hasSuffix("Interactor") {
        return "usecase"
    }
    if name.hasSuffix("Repository") || name.hasSuffix("RepositoryImpl") {
        return "repository"
    }
    if name.hasSuffix("Service") || name.hasSuffix("Client") || name.hasSuffix("API") || name.hasSuffix("Api") {
        return "api_service"
    }
    if name.hasSuffix("Assembly") || name.hasSuffix("Container") || name.hasSuffix("DIModule")
        || name.hasSuffix("Resolver") || name.hasSuffix("Factory") {
        return "di_module"
    }
    if name.hasSuffix("Coordinator") {
        return "coordinator"
    }
    return nil
}

private let segmentLayers: [String: String] = [
    "ui": "Presentation", "presentation": "Presentation", "views": "Presentation",
    "viewmodels": "Presentation", "screens": "Presentation",
    "domain": "Domain", "usecases": "Domain", "usecase": "Domain", "interactors": "Domain",
    "data": "Data", "repositories": "Data", "repository": "Data", "services": "Data",
    "network": "Data", "networking": "Data",
    "di": "DI", "injection": "DI", "dependencyinjection": "DI",
    // MVI/TCA: reducers/state/actions sit next to the view they drive, same
    // as viewmodels; effects orchestrate side effects, same shelf as usecases.
    "reducer": "Presentation", "reducers": "Presentation",
    "state": "Presentation", "action": "Presentation", "actions": "Presentation",
    "effect": "Domain", "effects": "Domain"
]

private let roleLayers: [String: String] = [
    "view": "Presentation", "viewmodel": "Presentation", "coordinator": "Presentation",
    "usecase": "Domain",
    "repository": "Data", "api_service": "Data",
    "di_module": "DI",
    // Same default-shelf reasoning as the segment map above.
    "reducer": "Presentation", "store": "Presentation",
    "state": "Presentation", "action": "Presentation",
    "effect": "Domain"
]

public func inferLayer(filePath: String, role: String?) -> String {
    let segments = filePath.lowercased().split(separator: "/").map(String.init)
    for segment in segments {
        if let layer = segmentLayers[segment] {
            return layer
        }
    }
    if let role, let layer = roleLayers[role] {
        return layer
    }
    return "Other"
}
