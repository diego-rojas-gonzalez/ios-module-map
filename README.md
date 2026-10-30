# ios-module-map

Reads a Swift module and writes the same `.module-map.json` schema that
[`android-module-map`](https://github.com/pfranccino/android-module-map)
writes for Kotlin — so its `module-diagrams` command can render Mermaid
diagrams for an iOS module unchanged, with no Python code touched.

```
module-map-ios     Swift source  →  .module-map.json   (this repo)
module-diagrams    map JSON      →  .md / .html        (android-module-map)
```

## Why share a schema instead of writing a second renderer

`module_diagrams.py` already knows how to turn `nodes`/`edges`/`external_nodes`
into a layered architecture diagram, a DI graph, a class table and layer
violations — none of that is Kotlin-specific once the JSON is in hand. The
only genuinely new piece for iOS is the extractor: reading Swift declarations
and shaping them into that same JSON.

## Quick start

> Requires Swift 5.9+ (ships with Xcode or the Swift toolchain) and a clone of
> `android-module-map` for the diagram step.

```bash
swift run module-map-ios path/to/MyFeature --no-timestamp
python3 path/to/android-module-map/scripts/module_diagrams.py \
    path/to/MyFeature/docs/architecture/MyFeature.module-map.json \
    -o docs/architecture
```

`module-map-ios` writes `<module>.module-map.json` next to the module (or to
`-o <dir>` like the Kotlin tool). Point it at:
- a folder (treated as one module), or
- a folder containing `Package.swift` (each SPM target becomes a module).

## What it extracts

For every `class`/`struct`/`enum`/`protocol` (syntactic only — no
type-checking, same tradeoff `android-module-map` makes for Kotlin):

- declaration shape: supertypes/conformances, stored properties, functions
  (signature as text), the richest `init` as `constructor`, attributes,
  doc comments (`///`)
- **role**, inferred by name/conformance — reusing Kotlin's own vocabulary
  wherever there's a direct analog, so `module_diagrams.py`'s built-in
  by-role layer defaults already place these correctly:

  | Swift shape | role | (Kotlin analog) |
  |---|---|---|
  | `*ViewModel`, conforms to `ObservableObject` | `viewmodel` | ViewModel |
  | `UIViewController` subclass, `*ViewController` | `activity` | Activity |
  | conforms to `View`, `*Screen` | `composable` | `@Composable` function |
  | `*UseCase`, `*Interactor` | `usecase` | UseCase |
  | `*Repository`, `*RepositoryImpl` | `repository` | Repository |
  | `*Service`, `*Client`, `*API`/`*Api` | `api_service` | Retrofit API |
  | `*Assembly`, `*Container`, `*Resolver`, `*Factory` | `di_module` | Hilt module |
  | `*Coordinator` | `coordinator` | *(no Kotlin analog — see below)* |

- **edges**, from what's visible in the syntax alone: `extends` (a class's
  first inherited type), `implements` (protocol conformances), `depends_on`
  (initializer parameters — the common constructor-injection pattern),
  `uses_type` (stored property types), and **`calls`** — `receiver.method(...)`
  inside a function body, resolved through the receiver's declared type (a
  property, constructor param, or `self`), the same "declared type of the
  receiver" rule `android-module-map`'s own edge validation uses. This is
  what feeds `module_diagrams.py`'s flow and sequence diagrams — e.g.
  `LoginViewModel.submit` → `LoginUseCase.invoke` → `AuthRepository.login` in
  `Fixtures/Login`. No `instantiates` yet. A call through a local variable or
  a chained expression (`foo().bar()`) isn't resolved — only self members —
  so a flow can be missing a hop, never show a wrong one.
- **`id`s are module-qualified** (`Login.LoginUseCase`, not just
  `LoginUseCase`) and **cross-module references resolve to `origin:
  "project"`** when a run covers more than one module (point `module-map-ios`
  at a `Package.swift` root, or at a parent folder holding several — see
  `Fixtures/MultiModule/`). A type declared in more than one module with the
  same simple name is ambiguous and falls back to `"library"` rather than
  guessing; a type genuinely outside this run (framework, external SPM
  package) does too.

## Extending the role → layer mapping

`coordinator` has no Kotlin equivalent, so `module_diagrams.py`'s built-in
defaults don't know where it belongs — drop a `.module-map.toml` next to the
module (same mechanism `android-module-map`'s README documents):

```toml
[layers.by_role]
coordinator = "Presentation"
```

See [`Fixtures/Login/.module-map.toml`](Fixtures/Login/.module-map.toml) for
a working example, and `Fixtures/Login/` in general for a small worked
feature (Domain/Data/UI/DI) that exercises the whole pipeline — regenerate it
with:

```bash
swift run module-map-ios Fixtures/Login --no-timestamp
python3 path/to/android-module-map/scripts/module_diagrams.py \
    Fixtures/Login/docs/architecture/Login.module-map.json -o /tmp/out
```

[`Fixtures/MultiModule/`](Fixtures/MultiModule/) is a smaller, two-target
`Package.swift` (`Core`, `Feature` depending on it) demonstrating cross-module
resolution: `swift run module-map-ios Fixtures/MultiModule --no-timestamp`
and check `Feature.module-map.json` — `NetworkClient` resolves to
`external_nodes[].origin: "project"` with `module: "Core"`, not `"library"`.

## Limitations

> Known boundaries for this first version — not bugs.

- **Syntactic only** — no type-checking, so a name collision between two
  locally-declared types with the same simple name isn't disambiguated.
- **`calls` only resolves self/property/param receivers** — a call through a
  local variable, a static/type-level call (`Foo.bar()`), or a chained
  expression isn't captured. Enough for the DI-driven chains that matter for
  flow diagrams (ViewModel → UseCase → Repository → API); not a full
  call graph.
- **`Package.swift` read by regex** — target names and `Sources/<name>`
  paths only; no manifest execution, so custom target `path:` overrides or
  plugin-generated targets aren't seen. Same tradeoff as the Kotlin tool
  reading `build.gradle.kts` without running Gradle.
- **Extension members aren't merged** — a type's methods added via
  `extension Foo { ... }` elsewhere aren't attached to `Foo`'s node yet.
- **No neighbor-less layer for plain data types** — a struct with no role
  and no typed neighbor (e.g. a bare DTO) lands in `Other`, same as the
  Kotlin tool's behavior for an un-roled data class.
- **Function-signature edges aren't extracted** — only `constructor` and
  stored `properties` feed `depends_on`/`uses_type`; parameter/return types
  of regular functions don't yet (the richest signal for DI is already
  covered via initializers).
- **Running `swift test` needs a full Xcode install** — a Command Line
  Tools–only install has neither `XCTest` nor `Testing` available, even
  though `swift build`/`swift run` work fine. `Tests/` is written against
  Swift Testing (`import Testing`, `@Test`), ready for whenever Xcode is
  present.

## What's next

The actual motivation for this tool is comparing an iOS module map against
an Android one — counting use cases, repositories, etc. on one platform and
scaffolding the equivalent boilerplate on the other when a feature exists on
only one side. That diffing/generation step is intentionally **not** part of
this repo; it's planned as a separate tool that consumes two `.module-map.json`
files (one from here, one from `android-module-map`) and is scoped
separately.
