# elm-rad Layer 6 Design — Components

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–4 shipped (cells, reactions, `Remote`/`Request`, `Rad.Http`, debounced cells, validated cells). Layer 5 (Forms) NOT shipped; Layer 6 does not depend on it.

---

## 1. Scope

Layer 6 introduces reusable component definitions. A `ComponentDef view cells computed` bundles a cells record, computed values, a view, and reactions into a module-level value that can be mounted into a parent application (or another component) via `withInstance`. The parent renders the component via `embed` and composes its reactions via `include`. Components are parameterizable through ordinary Elm functions.

**In scope:**
- `ComponentDef view cells computed` opaque.
- `defineComponent : { init, computed, view, reactions } -> ComponentDef view cells computed`.
- `withInstance : String -> ComponentDef view cells computed -> CellBuilder (cells -> rest) -> CellBuilder rest`.
- `embed : ComponentDef view cells computed -> cells -> view`.
- `include : ComponentDef view cells computed -> cells -> List (Reaction model)`.
- All existing `CellBuilder` primitives (`with`, `withDebounced`, `withValidated`) work inside a component's `init`.
- **Nested components:** `withInstance` also works inside a component's own `init`, producing hierarchical key prefixes (`"parent.child.field"`).
- Persistence-key namespacing via an internal `keyPrefix` field on `CellBuilder`. Keys are stamped onto each `Cell` record at build time.
- Two example apps: `counter-component` (parameterized, mounted twice) and `tagpicker-component` (composes `DebouncedCell` + `Rad.Http` inside a component).
- `elm-test` suites covering CellBuilder refactor regression, `withInstance`/namespacing, `embed`/`include` dispatch, and validated cells inside components.

**Out of scope:**
- Forms (Layer 5) — Layer 6 is independent.
- Persistence itself (Layer 7). Layer 6 *installs* namespaced keys on each `Cell.key`; Layer 7 reads them.
- A standalone validated-inside-component example app. The capability is tested but not demoed (to keep example count manageable).
- Lifecycle hooks (`onMount`, `onUnmount`). No use case yet.
- Dynamic component lists (`List ComponentInstance`). Requires Array-indexed IDs; deferred until a real use case appears.
- SVG/Canvas engines, WebSockets, additional effect libraries (Layer 8+).

**Key decisions (for future user-facing docs):**

1. **`CellBuilder` becomes a lazy recipe.** Internally refactored from an eager `{nextId, metas, ctor}` record to `(BuildState -> BuildResult ctor)` so a component's `init` can be started at an arbitrary `nextId` and prefix. Public API (`build`, `with`, `runBuilder`) unchanged.

2. **Reuse `CellBuilder` pipeline for components.** `ComponentDef`'s `init` field is a `CellBuilder cells` — same shape parent apps use. No separate `ComponentBuilder` API. Users write `build Cells |> with ... |> withDebounced ... |> withValidated ...` inside `defineComponent`.

3. **Cells record embeds directly in the parent model.** No `Instance` wrapper — the cells are plain data, debugger-friendly, survive hot reload. The parent accesses component cells via normal record access: `model.category.selected`.

4. **`embed`/`include` are dispatch helpers, not component state.** They take the `ComponentDef` and the cells record and call the def's `view`/`reactions` functions. The parent writes the `ComponentDef` at every use site — recommended pattern is to bind the `ComponentDef` as a module-level value and reference it by name.

5. **Persistence keys namespace at build time.** `withInstance "primary" componentDef` runs `componentDef.init` with an extended prefix; `with "selected"` inside the component produces a `Cell` whose `.key` is `"primary.selected"`. No runtime lookup; no side structures.

6. **No new Msg variants, no new runtime state.** Components dispatch through existing `ApplyAction` + `ReactionResult`. Engines stay unchanged. `AppModel model` tuple shape is unchanged.

---

## 2. Module layout after Layer 6

| Module | Audience | New in Layer 6 |
|---|---|---|
| `Rad` | App authors | + `ComponentDef` (opaque alias), `defineComponent`, `withInstance`, `embed`, `include` |
| `Rad.Engine` | Engine authors | — (unchanged) |
| `Rad.View` | App authors | — (unchanged) |
| `Rad.Read` | App authors | — (unchanged) |
| `Rad.Http` | App authors | — (unchanged) |
| `Rad.Internal.Component` | private | **NEW**: `ComponentDef(..)`, accessors |
| `Rad.Internal.Action`, `Debounced`, `Msg`, `Reaction`, `Registry`, `Request`, `Source`, `Validated` | private | — (unchanged) |

**Internal refactor (no user-visible API change):**
- `Rad.elm`'s `CellBuilder` changes from a concrete state record to a lazy function from `BuildState` to `BuildResult`. Public signatures of `build`, `with`, `runBuilder` are unchanged.
- `Rad.Internal.Debounced` and `Rad.Internal.Validated` stay as-is at their own module level; only their `with*` entry points in `Rad.elm` get updated bodies to thread the new state.

---

## 3. Types and public surface

```elm
-- Rad (public)

type ComponentDef view cells computed  -- opaque alias to IComponent.ComponentDef

defineComponent :
    { init : CellBuilder cells
    , computed : cells -> computed
    , view : cells -> computed -> view
    , reactions : cells -> computed -> List (Reaction model)
    }
    -> ComponentDef view cells computed

withInstance :
    String
    -> ComponentDef view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest

embed : ComponentDef view cells computed -> cells -> view
include : ComponentDef view cells computed -> cells -> List (Reaction model)
```

**Parameterization** is pure Elm function composition — no new API:

```elm
tagPicker : { endpoint : String, placeholder : String } -> ComponentDef (SimpleView model) TagPickerCells {}
tagPicker config =
    defineComponent
        { init = build TagPickerCells |> with "query" "" stringCodec |> ...
        , computed = \_ -> {}
        , view = \c _ -> ... use config.placeholder ...
        , reactions = \c _ ->
            [ on (toSource c.query)
                (\q -> Rad.Http.httpGet prodHandler (config.endpoint ++ "?q=" ++ q) decoder)
                c.results
            ]
        }
```

**Recommended pattern (docstrings will guide):** bind each parameterized `ComponentDef` as a module-level value and reference it by name to avoid re-constructing at every use site.

```elm
downloadsCounter : ComponentDef ...
downloadsCounter = counterComponent { label = "Downloads", step = 1 }

app =
    { init = build Model |> withInstance "counter" downloadsCounter |> ...
    , view = \m _ -> col [ embed downloadsCounter m.counter, ... ]
    , reactions = \m _ -> include downloadsCounter m.counter ++ ...
    }
```

---

## 4. CellBuilder refactor (foundational)

### Current shape (Layer 0-5)

```elm
type CellBuilder ctor
    = CellBuilder
        { nextId : Int
        , metas : List (Int, Encode.Value)
        , ctor : ctor
        }
```

`build` starts `nextId = 0`, `metas = []`; each `with` allocates the next id and extends `metas` + `ctor`; `runBuilder` returns `(ctor, Registry.fromMetas metas)`.

### New shape (Layer 6)

```elm
type CellBuilder ctor
    = CellBuilder (BuildState -> BuildResult ctor)


type alias BuildState =
    { nextId : Int
    , prefix : String
    }


type alias BuildResult ctor =
    { nextId : Int
    , metas : List (Int, Encode.Value)
    , ctor : ctor
    }
```

`CellBuilder ctor` is a function from a starting `BuildState` to a `BuildResult ctor`. The recipe is deferred — nothing is allocated until a state flows in.

### Behavior in the public API

`build`, `with`, `runBuilder` keep their signatures. Only their bodies change.

```elm
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder (\state ->
        { nextId = state.nextId
        , metas = []
        , ctor = ctor
        }
    )


with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder f) =
    CellBuilder (\state ->
        let
            parent = f state
            id = parent.nextId
            cell = Cell { id = id, key = state.prefix ++ key, codec = codec, initial = initial }
        in
        { nextId = id + 1
        , metas = (id, codec.encode initial) :: parent.metas
        , ctor = parent.ctor cell
        }
    )


runBuilder : CellBuilder ctor -> (ctor, Registry)
runBuilder (CellBuilder f) =
    let
        result = f { nextId = 0, prefix = "" }
    in
    (result.ctor, Registry.fromMetas result.metas)
```

### `withDebounced` and `withValidated` refits

Mechanical — each threads the new state:

```elm
withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withDebounced key delayMs initial codec (CellBuilder f) =
    CellBuilder (\state ->
        let
            parent = f state
            rawId = parent.nextId
            settledId = parent.nextId + 1
            timerSeqId = parent.nextId + 2
            fullKey = state.prefix ++ key
            cell = IDebounced.DebouncedCell { rawId = rawId, ..., initial = initial, codec = codec }
            encodedInitial = codec.encode initial
        in
        { nextId = parent.nextId + 3
        , metas =
            (timerSeqId, Encode.int 0)
                :: (settledId, encodedInitial)
                :: (rawId, encodedInitial)
                :: parent.metas
        , ctor = parent.ctor cell
        }
    )
```

Same treatment for `withValidated` (three slots; uses `state.prefix ++ key` for the key).

### Back-compat guarantee

Every Layer 0-5 test must pass unchanged after this refactor. The Slice 1 checkpoint is the existing 78-test suite running green.

---

## 5. `withInstance`, `embed`, `include`

### `Rad.Internal.Component`

```elm
module Rad.Internal.Component exposing (ComponentDef(..), initOf, computedOf, viewOf, reactionsOf)


type ComponentDef view cells computed
    = ComponentDef
        { init : CellBuilder cells
        , computed : cells -> computed
        , view : cells -> computed -> view
        , reactions : cells -> computed -> List (Reaction model)
        }


initOf : ComponentDef view cells computed -> CellBuilder cells
initOf (ComponentDef d) = d.init


-- analogous accessors for computed / view / reactions
```

**Note on the `reactions` field's model type variable:** `Reaction model` is phantom-typed over `model`. The `model` parameter doesn't appear in `ComponentDef`'s own type parameters; it's a free variable that unifies at use site with whatever the parent app's model type is. Same mechanism Layer 2's `AppDef.reactions : model -> computed -> List (Reaction model)` uses today.

### `withInstance`

```elm
withInstance : String -> ComponentDef view cells computed -> CellBuilder (cells -> rest) -> CellBuilder rest
withInstance name (ComponentDef def) (CellBuilder f) =
    CellBuilder (\state ->
        let
            parent = f state
            childPrefix = state.prefix ++ name ++ "."
            (CellBuilder g) = def.init
            child = g { nextId = parent.nextId, prefix = childPrefix }
        in
        { nextId = child.nextId
        , metas = child.metas ++ parent.metas
        , ctor = parent.ctor child.ctor
        }
    )
```

Key points:
- `child` is evaluated at `parent.nextId` with extended prefix.
- `parent.ctor child.ctor` applies the child's `cells` value to the parent's continuation (which expects `cells -> rest`).
- `metas` from the child are prepended onto parent's — registry entries merge cleanly.

### `embed` and `include`

```elm
embed : ComponentDef view cells computed -> cells -> view
embed (ComponentDef def) cells =
    def.view cells (def.computed cells)


include : ComponentDef view cells computed -> cells -> List (Reaction model)
include (ComponentDef def) cells =
    def.reactions cells (def.computed cells)
```

Both evaluate `def.computed cells` once and pass the result through. Each is called per cycle (embed on every render; include on every `fireReactions` pass). Cheap assuming `computed` is a cheap function.

### Nested components

A component's `init` may call `withInstance` to nest a sub-component. Because `withInstance` is polymorphic over the builder's continuation and threads `state.prefix` correctly, nesting needs no special handling:

```elm
settingsPanel : ComponentDef ... SettingsCells ...
settingsPanel =
    defineComponent
        { init =
            build SettingsCells
                |> with "fontSize" 16 intCodec
                |> withInstance "theme" themePicker
        , reactions = \cells _ ->
            include themePicker cells.theme ++ [ -- own reactions -- ]
        , view = ...
        , computed = \_ -> {}
        }
```

When the parent mounts `settingsPanel` as `withInstance "settings" settingsPanel`, the key chain becomes `"settings.fontSize"` and `"settings.theme.<field>"`.

---

## 6. Examples and Vite middleware additions

### Two new example apps

**1. `counter-component`** — parameterized component mounted twice.

- Component: `counterComponent : { label : String, step : Int } -> ComponentDef (SimpleView model) CounterCells {}`.
- `CounterCells = { n : Cell Int }`.
- View: a label, a `watch` showing the count, and `+`/`-` buttons that dispatch `modify c.n (\v -> v + config.step)` / `(\v -> v - config.step)`.
- Parent binds two instances at module level:
  ```elm
  downloadsCounter = counterComponent { label = "Downloads", step = 1 }
  scaleCounter = counterComponent { label = "Scale", step = 10 }
  ```
- Parent mounts both: `build Model |> withInstance "downloads" downloadsCounter |> withInstance "scale" scaleCounter`.
- View: `col [ embed downloadsCounter model.downloads, embed scaleCounter model.scale ]`.
- Reactions: `\_ _ -> []` (no reactions for this component).
- Demonstrates: parameterization via closure, two-instance isolation, key namespacing (Registry contains `downloads.n` and `scale.n`), `embed` dispatch.

**2. `tagpicker-component`** — `DebouncedCell` + `Rad.Http` inside a component.

- Component: `tagPicker : { endpoint : String, placeholder : String } -> ComponentDef (SimpleView model) TagPickerCells {}`.
- `TagPickerCells = { query : DebouncedCell String, suggestions : Cell (Remote RequestError (List String)) }`.
- Component's `init` uses `withDebounced` (500ms) and `with`.
- Component's `reactions` fire an HTTP request when `settled query` changes:
  ```elm
  [ on (settled cells.query)
      (\q ->
          if String.trim q == "" then
              Rad.noRequest
          else
              Rad.Http.httpGet prodHandler
                  (config.endpoint ++ "?q=" ++ q)
                  matchesDecoder
      )
      cells.suggestions
  ]
  ```
- View: `debouncedInput` bound to `cells.query` (placeholder = `config.placeholder`), plus a `watch` on `toSource cells.suggestions` rendering the list.
- Parent binds two instances: `categoryPicker = tagPicker { endpoint = "/api/search", placeholder = "Category…" }` and `tagPickerInstance = tagPicker { endpoint = "/api/search", placeholder = "Tag…" }`.
- Parent's `reactions`: `include categoryPicker model.category ++ include tagPickerInstance model.tags`.
- Demonstrates: `withDebounced` inside a component, reactions inside a component, HTTP dispatch via closure, two instances sharing one mock endpoint with isolated cell state.

### Mock endpoint additions

**None.** Both examples reuse the existing `/api/search` endpoint from Layer 2. No change to `examples/mock-api-plugin.js`.

### Entries added to `examples/vite.config.js` `rollupOptions.input`

- `counter-component`, `tagpicker-component`.

### New `.html` + `.elm` files

Standard MPA entry + `Elm.X.init` pattern; matches existing examples.

---

## 7. Testing strategy

### Pure elm-test suites (four new files + regression gate)

**`ComponentBuilderTest.elm`** — CellBuilder refactor regression.
- `build Model |> with "n" 0 intCodec |> runBuilder` produces a `(Model, Registry)` with the expected cell value and an empty-prefix `Cell.key == "n"`.
- Second cell's id is 1.
- Running `runBuilder` twice on the same builder produces identical output (lazy-recipe is deterministic).
- Primary role: catching any regression introduced by the CellBuilder refactor. Slice 1 MUST run the full Layer 0-4 test suite (78 tests) and see it pass unchanged.

**`ComponentInstanceTest.elm`** — `withInstance` + namespacing.
- `build Model |> withInstance "primary" counterComponent |> runBuilder` allocates IDs starting from the parent's `nextId`.
- The cells record's `.n` field is a `Cell` with `.key == "primary.n"`.
- Two instances: `build Model |> withInstance "a" counter |> withInstance "b" counter` produces non-overlapping ID ranges; keys are `"a.n"` and `"b.n"`.
- **Nested instance:** a component whose `init` calls `withInstance "child" ...` produces cells with doubly-namespaced keys (`"parent.child.field"`) when mounted under `"parent"` by the outer app.

**`ComponentDispatchTest.elm`** — `embed` + `include` wiring.
- `embed componentDef cells` invokes `componentDef.view cells (componentDef.computed cells)`; use a `view` that returns a sentinel structure and assert on it.
- `include componentDef cells` returns the list produced by `componentDef.reactions cells (componentDef.computed cells)`.
- A component with `reactions = \_ _ -> []` returns an empty list from `include`.
- A component with two reactions returns both from `include`.

**`ComponentValidatedTest.elm`** — validated cells inside components.
- A component whose `init` uses `withValidated`: verify the three Registry slots end up at the correct namespaced keys and at IDs starting from the parent's `nextId`.
- The component's `reactions` function calls `validationReactions cells.username`; `include componentDef cells` returns that reaction correctly.
- `Rad.validate cells.username` (dispatched at the parent against the component's cell) writes a non-zero seq to the correct slot.
- Calling `include`'s returned reaction's `buildRequest` after `validate` produces `IReaction.DispatchTask _`.

### Browser smoke (manual)

- **`counter-component`:** "+" on Downloads increments Downloads only. "+" on Scale increments Scale only, and by 10. Confirms per-instance isolation.
- **`tagpicker-component`:** typing in the Category input after 500ms debounce triggers a request and shows results; typing in the Tag input does likewise, with isolated cell state. Confirms per-instance isolation plus in-component async.

### Deliberately not tested

- Cross-instance cells writing into each other (no such API; users would orchestrate explicitly).
- Hot reload — a property of the design, not runtime-testable in pure Elm.
- DOM events beyond view-binding code paths.

---

## 8. Forward-compat shaping and risks

### Forward-compat shaping

- **`ComponentDef` is opaque.** Future lifecycle hooks (`onMount`, `onUnmount`) land via new fields on the input record to `defineComponent` — existing call sites keep working because Elm records are structurally typed and growing an input record doesn't break prior callers unless they pin the exact record shape.
- **`CellBuilder` as a lazy recipe** is a universal seam. All future `with*` primitives (`withForm` in Layer 5, whatever else) thread the shared `BuildState`. No further structural change needed for build-time composition.
- **Namespaced keys from day one.** When Layer 7 lands, `Cell.key` already carries the full namespaced string. Layer 7 reads it.
- **Reactions remain `List (Reaction model)`.** Layer 4's `validationReactions` and Layer 6's `include` both produce lists the user concatenates; Layer 5 `formReactions` will fit the same shape.
- **No new `Msg` variants.** Components dispatch through existing `ApplyAction` + `ReactionResult`. Engines stay unchanged.
- **Nested components work by pure function composition** — no depth-specific runtime. Arbitrary nesting is recursive `withInstance`.

### Risks

**1. `CellBuilder` refactor is foundational.** A wrong move breaks every layer. Mitigation: Slice 1 lands the refactor in isolation; acceptance gate is the full 78-test Layer 0-4 suite passing unchanged. Zero new functionality in that slice.

**2. `computed` runs twice per cycle** (once for `embed`, once for `include`). Users with expensive `computed` pay 2x. Documented; users can memoize via `Rad.derive` + `Rad.Read.map` if needed (already a Layer 1 idiom).

**3. `ComponentDef` written three times.** `withInstance`, `embed`, `include` each need the def. Docs + the Recommended Pattern steer users toward binding at module level. Not a runtime concern.

**4. `reactions`' `Reaction model` phantom.** A component's reactions can only reference its own cells (closures are built from `cells`, not `model`). Enforced by types. This is a feature — no accidental reach-across into the parent's cells.

**5. Nested namespacing collision.** Two sibling components with the same instance name produce colliding keys (`"shared.field"`). Elm won't catch this statically. Documented as consumer responsibility; future layers may add a runtime assertion if it becomes a real bug source.

**6. Reaction list order matters for cross-reaction data flow within a single cycle.** The runtime's `fireReactions` fold threads each reaction's `writeLoading` through the next iteration's registry, so reactions later in the list observe earlier reactions' `Loading` writes. But the real `Done` value from an async reaction only lands on a subsequent `ReactionResult` msg — next cycle, not this one. Cross-reaction dependencies that expect in-cycle visibility of another reaction's *result* will lag one frame.

**Example of ordering that silently misbehaves:**

```elm
-- Component A: reaction on source.input writes to model.intermediate : Cell (Remote err v)
-- Component B: reaction on settled/source(intermediate) writes to model.result : Cell (Remote err v)

reactions = \model _ ->
    include componentB model.b ++ include componentA model.a
    -- B listed BEFORE A
```

On a user input change, B's reaction fires first but `intermediate` hasn't been touched yet this cycle, so B sees no trigger change and skips. Then A fires and writes `intermediate = Loading`. B doesn't re-check in this cycle — it picks up A's Loading state on the next Msg that flows through `run`. One-frame lag where B's view shows stale data.

Fix: write the producer before the consumer.

```elm
reactions = \model _ ->
    include componentA model.a ++ include componentB model.b
```

Documented as consumer responsibility.

### Explicitly deferred

- Lifecycle hooks (`onMount`, `onUnmount`).
- Component-scoped persistence configuration (Layer 7).
- `Form` inside a component, `b.form` in a future builder (Layer 5).
- Dynamic component lists (`List ComponentInstance` in a parent).

---

## 9. Seven vertical slices

Each slice ends with green `elm make`, green `elm-test`, and (where applicable) a visible checkpoint.

### Slice 1 — `CellBuilder` lazy-recipe refactor

Internal refactor only. `CellBuilder ctor` becomes `CellBuilder (BuildState -> BuildResult ctor)`. `build`, `with`, `runBuilder`, `withDebounced`, `withValidated` rewrite their bodies to thread the new state. No new public surface.

Tests: the existing 78-test suite must pass unchanged. No new tests.

Checkpoint: tree green, zero public-API deltas.

### Slice 2 — `Rad.Internal.Component` + `defineComponent`

New internal module `Rad.Internal.Component` with `ComponentDef(..)` and accessors. Public `defineComponent` and `type alias ComponentDef` in `Rad`.

Tests: `ComponentBuilderTest.elm` — baseline construction. Verifies that `defineComponent` produces a value usable as a `ComponentDef` and accepts the expected input record. `embed` and `include` land in Slice 4, so their tests belong there.

### Slice 3 — `withInstance` + ID/key namespacing

Public `withInstance` that mounts a `ComponentDef` into a parent builder, advancing IDs and extending the key prefix.

Tests: `ComponentInstanceTest.elm` — single instance, two instances (disjoint IDs + keys), nested instance (double-namespace).

### Slice 4 — `embed` + `include`

Public `embed` and `include` dispatching to the `ComponentDef`'s view and reactions.

Tests: `ComponentDispatchTest.elm` — view call-through and reactions list pass-through.

### Slice 5 — Validated cells inside components

No new code. Verifies Layer 4 + Layer 6 compose.

Tests: `ComponentValidatedTest.elm` — `withValidated` inside a component's `init`; `validationReactions cells.field` inside the component's `reactions`; `Rad.validate cells.field` dispatched at the parent mutates the correctly-namespaced slot.

### Slice 6 — `counter-component` example

Parameterized component mounted twice with different configs. Two HTML entries + vite config + index link? **No** — single HTML entry showing both instances on one page.

Browser smoke: both counters increment independently; steps differ.

### Slice 7 — `tagpicker-component` example + docs sweep

Component using `DebouncedCell` + `Rad.Http` internally. Single HTML entry showing two instances (Category + Tag pickers) on one page.

Plus: append **Implementation notes** subsection to the Components section of `docs/design-elm-rad.md` recording the six Layer 6 decisions (lazy CellBuilder, CellBuilder pipeline reuse, cells as plain data, embed/include as dispatch helpers, namespaced keys at build time, no new Msg variants).

---

## 10. Success criteria

Layer 6 is complete when:

- `Rad`, `Rad.Engine`, `Rad.Http`, `Rad.Read`, `Rad.View` all compile cleanly via `elm make --docs`.
- Every `elm-test` suite in Section 7 passes (four new suites, roughly 15-18 new tests; 78 pre-Layer-6 tests pass unchanged after the Slice 1 refactor).
- All pre-Layer-6 example apps still render and behave correctly (16 existing examples).
- Both new Layer 6 example apps render and behave correctly.
- `npm run build` in `examples/` produces a multi-entry production build for all **19 entries** (16 pre-Layer-6 example apps + 2 new Layer 6 apps + the landing page).
- Commit history is granular: one coherent change per commit, ordered such that each commit individually compiles and passes whatever tests exist at that point.
- `docs/design-elm-rad.md`'s Components section gains an Implementation notes subsection recording the six Layer 6 decisions.
