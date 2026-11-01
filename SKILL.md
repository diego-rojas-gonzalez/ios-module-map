---
name: module-map-ios
description: Map and analyze one Swift module (a folder, or an SPM package with several targets) with the bundled deterministic extractor. module-map-ios builds a JSON map of the module (swift-syntax AST only — no type-checking, no network at run time) with the same nodes/edges/external_nodes/legend schema `android-module-map` uses; android-module-map's module_diagrams.py then turns that map into a Markdown/HTML document with Mermaid diagrams (layered architecture, flows from the ViewModels/Coordinators, sequence of a flow, module dependencies) and an analysis (classes, layer violations, entry points, external dependencies, edges to review). Use this whenever the user asks to diagram, map, document or analyze the architecture of an iOS/Swift module or feature, asks how a module is structured or what depends on what, or wants Mermaid diagrams of a Swift module, even if they do not mention this skill or the tool by name.
---

# Module map (iOS)

One Swift binary does the extraction, and it needs no model: the same code always produces the
same JSON. This repo only produces that JSON — drawing the diagrams is `android-module-map`'s
job, downstream. Your job is to run the extractor, find a `module_diagrams.py` that can render
the map, and then add the two things neither script can do: check the doubtful edges against the
source, and describe types that have no doc comment.

Do not draw or redraw the diagrams yourself. They are generated from the map so that every arrow
is backed by an edge; a hand-drawn arrow breaks that guarantee.

## Step 1: Generate the map

1. **Find the target directory.** It can be:
   - a single module folder (treated as one module), or
   - a folder containing `Package.swift` (every SPM target inside becomes its own module), or
   - a folder holding several such package/module folders.
   If none of the given path or its parents look like a Swift module (no `.swift` files, no
   `Package.swift`), say so and ask for the right path instead of guessing.

2. **Swift toolchain.** Only Swift 5.9+ is required (ships with Xcode or the Swift toolchain). No
   virtualenv, no Python, no AI model for this half of the pipeline. The first `swift build` in
   this repo resolves `swift-syntax` from the network; after that it's offline.

   ```
   swift build
   ```

3. **Run.** From this repo's root, pointing at the target directory in the *other* project:

   ```
   swift run module-map-ios <directory> --no-timestamp
   ```

   Each map is written inside its own module, in `<module>/docs/architecture/`, unless `-o
   <dir>` collects them elsewhere. Progress goes to stdout; a normal run takes seconds. There is
   no `--no-codegraph` or `--android-cli` equivalent: `calls` edges are resolved directly from the
   AST in the same pass, always on, and nothing here runs a build system.

If the run fails, show the full error and stop. Do not patch `module-map-ios`'s source or work
around it without the user's approval.

## Step 2: Generate the documents

This repo has no renderer. The JSON map uses the exact schema `android-module-map`'s
`module_diagrams.py` already knows how to draw, so look for that script before asking the user to
install anything:

1. A sibling clone next to this repo or the target project, e.g. `../android-module-map/scripts/module_diagrams.py`.
2. `android-module-map`'s own skill already installed in this project, e.g.
   `.claude/skills/module-map/scripts/module_diagrams.py`.
3. A path the user gives you.

If none exist, tell the user and offer the two options from the README: clone
`https://github.com/pfranccino/android-module-map` (needs Python 3.10+), or install it as a
Claude Code skill. Don't invent a path and don't vendor a copy of the script into this repo.

Once found:

```
python3 <path-to>/module_diagrams.py <module-or-directory> --no-timestamp
```

It writes `<module>.md` (and, for one module, `<module>.html`) next to the map, and
`index.md`/`index.html` when the run covers several modules. Roles with no Kotlin analog
(`coordinator`, `reducer`, `state`, `action`, `effect`, `store`) have no built-in layer default —
if `.module-map.toml` next to the module doesn't already map them under `[layers.by_role]`, those
nodes land in the catch-all `Other` layer; point this out rather than silently accepting it.

Options worth knowing (full list in `module_diagrams.py --help` or `android-module-map`'s README):
`--only <sections>`, `--module <name>`, `--flow Class.function`, `-o <dir>`. There is no `--lang`
for this half — `module-map-ios` itself has no Spanish output.

## Step 3: Review what the scripts cannot decide

Write the results to `<module>.review.md` next to the generated document. The generated document
is overwritten on every run, so do not edit it.

1. **Edges to review.** Go through the last section of the generated document.
   - A `calls` edge only exists when the receiver was `self`, a stored property, or a constructor
     parameter with a declared type — never a local variable, a static call, or a chained
     expression. There's nothing ambiguous to double-check the way Kotlin's name-based codegraph
     matches are, but a *missing* flow hop is exactly what this limitation produces: if a flow
     looks broken, check whether the missing call goes through a local variable before assuming
     the architecture itself is wrong.
   - A "possible gap" is a type with a role but no relationships. Check whether it's reached
     through something the map can't see — a `Coordinator` wiring via closures, a SwiftUI
     `NavigationStack` route, a property wrapper with no explicit type annotation
     (`@Dependency(\.client) var client`), or reducer composition inside a `body` computed
     property (`Scope { ... }`, `CombineReducers { ... }`).
   - For an `Action`/`Intent` enum, the `cases` list is the only signal the map has for which
     case does what — there's no `handles`-style edge from a case to the reducer that switches on
     it. Trace that by hand if the user asks which reducer handles which action.
2. **Layer violations.** For each row marked as unverified, confirm it in the source before
   calling it a violation.
3. **Responsibilities.** For each type with no `///` doc comment, read it and write one sentence
   on what it's responsible for.

Report only what you checked, with `file:line` for each finding. If the review shows a diagram is
wrong, say which edge is wrong and why; do not fix the diagram by hand.

## When a diagram or rule should change

Layer assignment, forbidden layer crossings, and the size above which the layer diagram switches
to one box per package are all read from `.module-map.toml` by `module_diagrams.py` — never by
`module-map-ios`, which only writes the JSON and never looks at that file. If the user wants
`coordinator`/`reducer`/`state`/`action`/`effect`/`store` placed somewhere, or a Kotlin-inherited
default changed, propose the edit to `.module-map.toml` next to the module and wait for approval,
so the result stays reproducible. Propose a change to `module-map-ios`'s Swift source only for
what the extraction itself is missing (see the README's Limitations), and never without the
user's approval.

## Finish

Tell the user where the map, the document, and the review live, how many nodes and edges the map
has, and which review items need a human decision.

## Constraints

- Do not modify the target project's source code.
- Do not modify `module-map-ios`'s source, or `android-module-map`'s scripts, on your own.
- Do not commit anything.
