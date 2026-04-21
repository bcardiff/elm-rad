# elm-rad Layer 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 6 — reusable component definitions. Introduce `ComponentDef`, `defineComponent`, `withInstance`, `embed`, `include`. Refactor `CellBuilder` into a lazy recipe so components can be mounted at arbitrary ID offsets with namespaced keys. Ship two example apps and four new test suites. Purely additive on top of Layer 4.

**Architecture:** `CellBuilder ctor` becomes `CellBuilder (BuildState -> BuildResult ctor)` — a function from a starting `{nextId, prefix}` to a result record. `build`, `with`, `runBuilder`, `withDebounced`, `withValidated` keep their public signatures; only their bodies change. `ComponentDef` lives in a new internal module and gets a thin public alias + constructor in `Rad`. `withInstance` threads parent state into a component's `CellBuilder` recipe, extending the prefix. `embed` and `include` are trivial dispatches through the def. No new `Msg` variants; no runtime state changes.

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x. No new package dependencies. Vite 6 + `vite-plugin-elm` for the example host.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per memory `feedback_commit_cadence.md`). Each commit must be reviewable on its own and must leave the tree green.
- **One task = one commit** unless a header says otherwise.
- **Before every commit that touches `.elm` files, run `elm-format`** (per memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes` (from repo root).
  - Examples: `npx --yes elm-format src --yes` (from `examples/`).
  - Stage any reformatting in the same commit.
- Verification: `npx --yes elm-test` (from repo root). `cd examples && npm run build` for examples build.
- **Commit messages are single-line imperative** (`Add X`, `Ship Y`, `Refactor X`). No Co-Authored-By trailers unless explicitly requested.

**Design-doc correction (applied throughout):**
The Layer 6 design doc's Section 3 writes the public type as `ComponentDef view cells computed` (3 params). Elm requires free type variables inside record fields to be bound by the enclosing type constructor, so `reactions : cells -> computed -> List (Reaction model)` forces a `model` type parameter. This plan uses the corrected 4-param form:

```elm
type ComponentDef model view cells computed
```

Public signatures thread `model` through:

```elm
defineComponent : { ... } -> ComponentDef model view cells computed
withInstance : String -> ComponentDef model view cells computed -> CellBuilder (cells -> rest) -> CellBuilder rest
embed : ComponentDef model view cells computed -> cells -> view
include : ComponentDef model view cells computed -> cells -> List (Reaction model)
```

**Scope narrowing vs. design doc:**
The design doc's Section 4 sketch computes `fullKey = state.prefix ++ key` inside `withDebounced`/`withValidated` refits. This plan does NOT thread keys into `DebouncedCell` or `ValidatedCell` — only plain `Cell.key` gets the namespaced value. Rationale: `DebouncedCell` and `ValidatedCell` don't store a `key` field today; adding one is Layer 7's call when it designs the persistence format for multi-slot cell types. Layer 6 keeps the `key` argument to `withDebounced`/`withValidated` as the current `_` (ignored) for those primitives — consistent with pre-Layer-6 behavior. The key is still *available* via `state.prefix` at build time and can be added later without breaking callers.

**Module layout at the end:**

```
src/
  Rad.elm                         ← CellBuilder refactored to lazy-recipe;
                                    + ComponentDef alias, defineComponent,
                                    withInstance, embed, include
  Rad/
    Engine.elm, Http.elm, Read.elm, View.elm  ← unchanged
    Internal/
      Action.elm, Debounced.elm, Msg.elm, Reaction.elm, Registry.elm,
      Request.elm, Source.elm, Validated.elm ← unchanged
      Component.elm               ← NEW: ComponentDef(..), accessors
tests/
  <Layer 0-4 suites unchanged>
  ComponentBuilderTest.elm        ← NEW (Slice 2)
  ComponentInstanceTest.elm       ← NEW (Slice 3)
  ComponentDispatchTest.elm       ← NEW (Slice 4)
  ComponentValidatedTest.elm      ← NEW (Slice 5)
examples/
  elm.json, package.json          ← unchanged
  vite.config.js                  ← + 2 new entries
  mock-api-plugin.js              ← unchanged (reuses /api/search)
  index.html                      ← + 2 new links
  counter-component.html          ← NEW
  tagpicker-component.html        ← NEW
  src/
    CounterComponent.elm          ← NEW
    TagpickerComponent.elm        ← NEW
    SimpleView.elm                ← unchanged
docs/
  design-elm-rad.md               ← Components section gains Implementation notes subsection
```

**Expected test count after Layer 6:** 78 pre + ~16 new = **~94**. Exact counts per-task below.

**Expected example count after Layer 6:** 17 pre + 2 new = **19 entries** (index + 18 examples).

---

## Slice 1 — `CellBuilder` lazy-recipe refactor

### Task 1.1: Refactor `CellBuilder`, `build`, `with`, `runBuilder`, `withDebounced`, `withValidated` atomically

**Atomic commit.** All five functions + the type change to `CellBuilder` must land together or the tree won't compile. No new public surface; no new tests.

**Files:**
- Modify: `src/Rad.elm` (type `CellBuilder`, `build`, `with`, `runBuilder`, `withDebounced`, `withValidated` bodies)

- [ ] **Step 1: Verify the 78-test baseline** before any change.

Run: `npx --yes elm-test`
Expected: `TEST RUN PASSED`, 78 passed.

- [ ] **Step 2: Replace the `CellBuilder` type declaration** in `src/Rad.elm`. Find:

```elm
type CellBuilder a
    = CellBuilder
        { nextId : Int
        , metas : List ( Int, Decode.Value )
        , ctor : a
        }
```

Replace with:

```elm
type CellBuilder ctor
    = CellBuilder (BuildState -> BuildResult ctor)


type alias BuildState =
    { nextId : Int
    , prefix : String
    }


type alias BuildResult ctor =
    { nextId : Int
    , metas : List ( Int, Decode.Value )
    , ctor : ctor
    }
```

`BuildState` and `BuildResult` are module-private (not exported from `Rad`). No change to the `Rad` exposing list.

- [ ] **Step 3: Replace `build`** in `src/Rad.elm`. Find:

```elm
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        { nextId = 0
        , metas = []
        , ctor = ctor
        }
```

Replace with:

```elm
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        (\state ->
            { nextId = state.nextId
            , metas = []
            , ctor = ctor
            }
        )
```

- [ ] **Step 4: Replace `with`.** Find:

```elm
with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder b) =
    let
        cell =
            Cell { id = b.nextId, key = key, codec = codec, initial = initial }
    in
    CellBuilder
        { nextId = b.nextId + 1
        , metas = ( b.nextId, codec.encode initial ) :: b.metas
        , ctor = b.ctor cell
        }
```

Replace with:

```elm
with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                id =
                    parent.nextId

                cell =
                    Cell { id = id, key = state.prefix ++ key, codec = codec, initial = initial }
            in
            { nextId = id + 1
            , metas = ( id, codec.encode initial ) :: parent.metas
            , ctor = parent.ctor cell
            }
        )
```

Note the change: `Cell.key` is now `state.prefix ++ key`. At top level (called from `runBuilder`), `state.prefix` is `""`, so the key is just the user-supplied string — same as pre-refactor behavior. Inside a component via `withInstance`, `state.prefix` is non-empty — that's the new capability.

- [ ] **Step 5: Replace `runBuilder`.** Find:

```elm
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder b) =
    ( b.ctor
    , b.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty
    )
```

Replace with:

```elm
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder f) =
    let
        result =
            f { nextId = 0, prefix = "" }
    in
    ( result.ctor
    , result.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty
    )
```

- [ ] **Step 6: Replace `withDebounced`.** Find the body of `withDebounced` (starts around line 239 at the time of writing) and replace it. Full new form:

```elm
withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withDebounced _ delayMs initial codec (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                rawId =
                    parent.nextId

                settledId =
                    parent.nextId + 1

                timerSeqId =
                    parent.nextId + 2

                cell =
                    IDebounced.DebouncedCell
                        { rawId = rawId
                        , settledId = settledId
                        , timerSeqId = timerSeqId
                        , codec = codec
                        , delayMs = delayMs
                        , initial = initial
                        }

                encodedInitial =
                    codec.encode initial
            in
            { nextId = parent.nextId + 3
            , metas =
                ( timerSeqId, Encode.int 0 )
                    :: ( settledId, encodedInitial )
                    :: ( rawId, encodedInitial )
                    :: parent.metas
            , ctor = parent.ctor cell
            }
        )
```

Key: the first `String` argument stays `_` (ignored). Layer 6 does not thread it into `DebouncedCell` (Layer 7 will decide).

- [ ] **Step 7: Replace `withValidated`.** Full new form:

```elm
withValidated :
    String
    -> a
    -> Codec a
    -> Codec err
    -> IValidated.Validator err a
    -> CellBuilder (ValidatedCell err a -> rest)
    -> CellBuilder rest
withValidated _ initial codec errCodec validator (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                inputId =
                    parent.nextId

                validationId =
                    parent.nextId + 1

                activationSeqId =
                    parent.nextId + 2

                valCodec =
                    validationCodec errCodec codec

                cell =
                    IValidated.ValidatedCell
                        { inputId = inputId
                        , validationId = validationId
                        , activationSeqId = activationSeqId
                        , codec = codec
                        , errCodec = errCodec
                        , validator = validator
                        , initial = initial
                        }

                encodedInitial =
                    codec.encode initial

                encodedDormant =
                    valCodec.encode Dormant
            in
            { nextId = parent.nextId + 3
            , metas =
                ( activationSeqId, Encode.int 0 )
                    :: ( validationId, encodedDormant )
                    :: ( inputId, encodedInitial )
                    :: parent.metas
            , ctor = parent.ctor cell
            }
        )
```

Same convention: `_` for key.

- [ ] **Step 8: Verify the 78-test baseline survives the refactor.**

Run: `npx --yes elm-test`
Expected: `TEST RUN PASSED`, **78 passed, 0 failed**. Same count as pre-refactor.

If any test fails, the refactor has a regression. Bisect by reverting individual function bodies until the failure is isolated.

- [ ] **Step 9: Verify `examples` still build.**

Run: `cd examples && npm run build`
Expected: all 17 entries build successfully (index + 16 examples).

- [ ] **Step 10: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 11: Commit.**

```bash
git add src/Rad.elm
git commit -m "Refactor CellBuilder to lazy recipe"
```

---

## Slice 2 — `ComponentDef` + `defineComponent`

**Architectural note:** The Layer 6 design doc's Section 2 lists a `Rad.Internal.Component` module. In practice, `ComponentDef`'s record field `init : CellBuilder cells` references `CellBuilder`, which lives in `Rad.elm`. An internal module importing `Rad` would create a cycle. The clean resolution is either extracting `CellBuilder` to its own internal module (larger refactor) or defining `ComponentDef` directly in `Rad.elm` (simpler, keeps the existing layering).

**This plan keeps `ComponentDef` in `Rad.elm`.** The `Rad.Internal.Component` module is NOT created. `ComponentDef` is a regular `type` in `Rad.elm`; its constructor is not exposed publicly but `Rad.elm`'s local helpers (`withInstance`, `embed`, `include`) pattern-match on it directly.

### Task 2.1: Add `ComponentDef` and `defineComponent` to `Rad` + `ComponentBuilderTest`

**Files:**
- Modify: `src/Rad.elm` (exposing list, @docs, type definition, `defineComponent`)
- Create: `tests/ComponentBuilderTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/ComponentBuilderTest.elm`:

```elm
module ComponentBuilderTest exposing (suite)

import Expect
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , defineComponent
        , intCodec
        , with
        )
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model (String -> String) CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> \s -> s
        , reactions = \_ _ -> []
        }


suite : Test
suite =
    describe "defineComponent"
        [ test "constructs a ComponentDef usable as a type alias" <|
            \_ ->
                -- Simply exercising the constructor is enough; the type-check
                -- is the assertion.
                let
                    _ =
                        counterComponent
                in
                Expect.pass
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ComponentBuilderTest.elm`
Expected: compile error — `Rad.ComponentDef`, `Rad.defineComponent` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `ComponentDef` and `defineComponent` to the exposing list — place them alongside `AppDef, AppModel, run`. Find the line:

```elm
    , AppDef, AppModel, run
```

Replace with:

```elm
    , AppDef, AppModel, run
    , ComponentDef, defineComponent
```

Update `@docs` similarly — find `@docs AppDef, AppModel, run` and add a new line after:

```elm
@docs ComponentDef, defineComponent
```

- [ ] **Step 4: Add the `ComponentDef` type + `defineComponent` function** in the body of `src/Rad.elm`. Place at the end of the file (after the existing helpers):

```elm
{-| A reusable bundle of cells, computed values, a view, and reactions. Build
via `defineComponent`, mount via `withInstance`, render via `embed`, and
compose reactions via `include`. Opaque.

The `model` type parameter carries through to the `Reaction model` values the
component produces. At use sites, `model` unifies with the outer app's model
type.
-}
type ComponentDef model view cells computed
    = ComponentDef
        { init : CellBuilder cells
        , computed : cells -> computed
        , view : cells -> computed -> view
        , reactions : cells -> computed -> List (Reaction model)
        }


{-| Build a `ComponentDef` from its parts.

    tagPicker : { endpoint : String } -> ComponentDef model (SimpleView model) TagPickerCells {}
    tagPicker config =
        defineComponent
            { init = build TagPickerCells |> with "query" "" stringCodec |> ...
            , computed = \_ -> {}
            , view = \c _ -> ...
            , reactions = \c _ -> [ ... ]
            }

Recommended pattern: bind parameterized `ComponentDef` values at module level
and reference them by name to avoid reconstructing at every use site
(`withInstance`, `embed`, `include`).

-}
defineComponent :
    { init : CellBuilder cells
    , computed : cells -> computed
    , view : cells -> computed -> view
    , reactions : cells -> computed -> List (Reaction model)
    }
    -> ComponentDef model view cells computed
defineComponent def =
    ComponentDef def
```

Note: `ComponentDef` is a regular `type` (not a type alias) with a single constructor. The constructor stays inside `Rad.elm` — not re-exposed (no `(..)`) — so users see only the opaque type. Other `Rad.elm`-local functions (`withInstance`, `embed`, `include` in later tasks) pattern-match via `(ComponentDef def) -> ...` within the same module.

- [ ] **Step 5: Run tests to confirm pass.**

Run: `npx --yes elm-test`
Expected: all suites pass — 78 + 1 new = **79 total**.

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm tests/ComponentBuilderTest.elm
git commit -m "Add ComponentDef and defineComponent"
```

---

## Slice 3 — `withInstance` + ID/key namespacing

### Task 3.1: Add `withInstance` + `ComponentInstanceTest`

**Files:**
- Modify: `src/Rad.elm` (exposing, @docs, body)
- Create: `tests/ComponentInstanceTest.elm`

**Test-helper note:** the tests assert on `Cell.key` strings. `Cell` is opaque (no `(..)` in `Rad`'s exposing list), so tests can't pattern-match on the constructor from outside. This plan adds a one-line public accessor `Rad.cellKey : Cell a -> String` so tests (and potential future Layer 7 persistence interop) can read the namespaced key without breaking `Cell`'s opacity. The accessor is documented as "mostly for integration/testing" and users shouldn't need it day-to-day.

Task 3.1 therefore adds three things in one commit:
1. `Rad.withInstance` (the main feature).
2. `Rad.cellKey` (the accessor helper).
3. `tests/ComponentInstanceTest.elm`.

- [ ] **Step 1: Write the failing test.** Create `tests/ComponentInstanceTest.elm`:

```elm
module ComponentInstanceTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , cellKey
        , defineComponent
        , intCodec
        , with
        , withInstance
        )
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model () CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \_ _ -> []
        }


type alias SingleInstance =
    { a : CounterCells }


type alias TwoInstances =
    { a : CounterCells, b : CounterCells }


type alias NestedCells =
    { outer : Cell Int, inner : CounterCells }


nestedComponent : ComponentDef model () NestedCells {}
nestedComponent =
    defineComponent
        { init =
            build NestedCells
                |> with "outer" 99 intCodec
                |> withInstance "inner" counterComponent
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \_ _ -> []
        }


type alias Outer =
    { nested : NestedCells }


suite : Test
suite =
    describe "withInstance"
        [ test "single instance produces namespaced key" <|
            \_ ->
                let
                    init_ =
                        build SingleInstance |> withInstance "a" counterComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal "a.n" (cellKey model.a.n)
        , test "two instances produce distinct namespaced keys" <|
            \_ ->
                let
                    init_ =
                        build TwoInstances
                            |> withInstance "a" counterComponent
                            |> withInstance "b" counterComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal
                    { a = "a.n", b = "b.n" }
                    { a = cellKey model.a.n, b = cellKey model.b.n }
        , test "nested instance produces doubly-namespaced keys" <|
            \_ ->
                let
                    init_ =
                        build Outer |> withInstance "outer" nestedComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal
                    { keyOuter = "outer.outer", keyInner = "outer.inner.n" }
                    { keyOuter = cellKey model.nested.outer
                    , keyInner = cellKey model.nested.inner.n
                    }
        , test "registry contains entries at the allocated IDs" <|
            \_ ->
                let
                    init_ =
                        build TwoInstances
                            |> withInstance "a" counterComponent
                            |> withInstance "b" counterComponent

                    ( model, registry ) =
                        Rad.runBuilder init_

                    valueFor cell =
                        Rad.readSource (Rad.toSource cell) registry
                in
                Expect.equal
                    { a = 0, b = 0 }
                    { a = valueFor model.a.n, b = valueFor model.b.n }
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ComponentInstanceTest.elm`
Expected: compile error — `Rad.withInstance` and `Rad.cellKey` not found.

- [ ] **Step 3: Add `cellKey` to `src/Rad.elm`.** Add to exposing list (near `Cell`):

```elm
    , Cell
    , cellKey
```

Add to `@docs`:

```elm
@docs Cell
@docs cellKey
```

Add the function body near the `Cell` type definition:

```elm
{-| Inspect a cell's persistence key. The key is the user-supplied string,
prefixed with any namespace segments introduced by `withInstance`. Useful for
Layer 7 persistence integration and testing.
-}
cellKey : Cell a -> String
cellKey (Cell c) =
    c.key
```

- [ ] **Step 4: Add `withInstance` to `src/Rad.elm`.** Add to exposing list (alongside `ComponentDef, defineComponent`):

```elm
    , ComponentDef, defineComponent, withInstance
```

Add to `@docs`:

```elm
@docs ComponentDef, defineComponent, withInstance
```

Add the function body (after `defineComponent`):

```elm
{-| Mount a component instance under the given namespace. Inside the
parent's `init` pipeline:

    build Model
        |> withInstance "primary" tagPicker
        |> withInstance "secondary" tagPicker

Each call extends the persistence-key prefix for the component's cells
(`"primary.selected"`, `"secondary.selected"`) and advances the parent's ID
counter past the component's cells.

Works inside another component's `init` too — nested components compose the
prefix (`"outer.inner.field"`).
-}
withInstance :
    String
    -> ComponentDef model view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest
withInstance name (ComponentDef def) (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                childPrefix =
                    state.prefix ++ name ++ "."

                (CellBuilder g) =
                    def.init

                child =
                    g { nextId = parent.nextId, prefix = childPrefix }
            in
            { nextId = child.nextId
            , metas = child.metas ++ parent.metas
            , ctor = parent.ctor child.ctor
            }
        )
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total is 79 + 4 new = **83**.

- [ ] **Step 6: Verify `examples` still build.**

Run: `cd examples && npm run build`
Expected: all 17 entries build.

- [ ] **Step 7: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 8: Commit.**

```bash
git add src/Rad.elm tests/ComponentInstanceTest.elm
git commit -m "Add withInstance and cellKey"
```

---

## Slice 4 — `embed` + `include`

### Task 4.1: Add `embed` + `include` + `ComponentDispatchTest`

**Files:**
- Modify: `src/Rad.elm` (exposing, @docs, body)
- Create: `tests/ComponentDispatchTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/ComponentDispatchTest.elm`:

```elm
module ComponentDispatchTest exposing (suite)

import Expect
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , defineComponent
        , embed
        , include
        , intCodec
        , with
        , withInstance
        )
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model String CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> "counter-view"
        , reactions = \_ _ -> []
        }


type alias Model =
    { counter : CounterCells }


init : Rad.CellBuilder Model
init =
    build Model |> withInstance "counter" counterComponent


suite : Test
suite =
    describe "embed and include"
        [ test "embed returns the component's view output" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal "counter-view" (embed counterComponent model.counter)
        , test "include returns the component's reactions list (empty here)" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 0 (List.length (include counterComponent model.counter))
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ComponentDispatchTest.elm`
Expected: compile error — `Rad.embed` and `Rad.include` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `embed, include` alongside `withInstance`:

```elm
    , ComponentDef, defineComponent, withInstance, embed, include
```

Update `@docs`:

```elm
@docs ComponentDef, defineComponent, withInstance, embed, include
```

- [ ] **Step 4: Add the two functions** at the end of `src/Rad.elm`:

```elm
{-| Render a component instance's view. Reads the component's cells via
`def.view cells (def.computed cells)`.
-}
embed : ComponentDef model view cells computed -> cells -> view
embed (ComponentDef def) cells =
    def.view cells (def.computed cells)


{-| Collect a component instance's reactions. Returns the list produced by
`def.reactions cells (def.computed cells)`. Concatenate with other reactions
in the parent's `reactions` function.
-}
include : ComponentDef model view cells computed -> cells -> List (Reaction model)
include (ComponentDef def) cells =
    def.reactions cells (def.computed cells)
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total is 83 + 2 new = **85**.

- [ ] **Step 6: Verify `examples` still build.**

Run: `cd examples && npm run build`
Expected: all 17 entries build.

- [ ] **Step 7: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 8: Commit.**

```bash
git add src/Rad.elm tests/ComponentDispatchTest.elm
git commit -m "Add embed and include"
```

---

## Slice 5 — Validated cells inside components

### Task 5.1: Add `ComponentValidatedTest`

**Files:**
- Create: `tests/ComponentValidatedTest.elm`

No new code. This slice verifies that Layer 4 and Layer 6 compose.

- [ ] **Step 1: Create `tests/ComponentValidatedTest.elm`:**

```elm
module ComponentValidatedTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( ComponentDef
        , Validation(..)
        , ValidatedCell
        , Validator
        , build
        , defineComponent
        , include
        , stringCodec
        , sync
        , validate
        , validationCodec
        , validationReactions
        , withInstance
        , withValidated
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias LoginCells =
    { username : ValidatedCell String String }


loginComponent : ComponentDef model () LoginCells {}
loginComponent =
    defineComponent
        { init =
            build LoginCells
                |> withValidated "username" "" stringCodec stringCodec (sync Ok)
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \cells _ -> validationReactions cells.username
        }


type alias Model =
    { login : LoginCells }


init : Rad.CellBuilder Model
init =
    build Model |> withInstance "login" loginComponent


suite : Test
suite =
    describe "Validated cells inside components"
        [ test "validated cell inside component is allocated at expected IDs" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init

                    ref =
                        IValidated.ref model.login.username
                in
                Expect.equal
                    { input = 0, validation = 1, activationSeq = 2 }
                    { input = ref.inputId
                    , validation = ref.validationId
                    , activationSeq = ref.activationSeqId
                    }
        , test "validated cell's initial values are registered correctly" <|
            \_ ->
                let
                    ( _, registry ) =
                        Rad.runBuilder init

                    decodeString id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)

                    decodeInt id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)

                    vc =
                        validationCodec stringCodec stringCodec

                    decodeValidation id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue vc.decode >> Result.toMaybe)
                in
                Expect.equal
                    { input = Just "", validation = Just Dormant, activationSeq = Just 0 }
                    { input = decodeString 0
                    , validation = decodeValidation 1
                    , activationSeq = decodeInt 2
                    }
        , test "include returns the component's validationReactions" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 1 (List.length (include loginComponent model.login))
        , test "validate action dispatched at parent mutates the component's activationSeq slot" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.login.username) registry0

                    ref =
                        IValidated.ref model.login.username

                    seqAfter =
                        Registry.get ref.activationSeqId registry1
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                in
                Expect.equal (Just 1) seqAfter
        , test "after validate, the component's reaction reports DispatchTask" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.login.username) registry0

                    reaction =
                        include loginComponent model.login |> List.head
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        case r.buildRequest registry1 of
                            IReaction.DispatchTask _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected DispatchTask after validate"

                    Nothing ->
                        Expect.fail "component produced no reaction"
        ]
```

- [ ] **Step 2: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total is 85 + 5 new = **90**.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add tests/ComponentValidatedTest.elm
git commit -m "Test validated cells inside components"
```

---

## Slice 6 — `counter-component` example

### Task 6.1: Ship the counter-component example

**Files:**
- Create: `examples/src/CounterComponent.elm`
- Create: `examples/counter-component.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/CounterComponent.elm`:**

```elm
module CounterComponent exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ComponentDef
        , build
        , defineComponent
        , embed
        , include
        , intCodec
        , modify
        , run
        , toSource
        , with
        , withInstance
        )
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


type alias CounterCells =
    { n : Cell Int }


counterComponent : { label : String, step : Int } -> ComponentDef model (SimpleView model) CounterCells {}
counterComponent config =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view =
            \c _ ->
                col
                    [ watch (toSource c.n) (\n -> text (config.label ++ ": " ++ String.fromInt n))
                    , button { label = "+ (" ++ String.fromInt config.step ++ ")", onClick = modify c.n (\v -> v + config.step) }
                    , button { label = "- (" ++ String.fromInt config.step ++ ")", onClick = modify c.n (\v -> v - config.step) }
                    ]
        , reactions = \_ _ -> []
        }


downloadsCounter : ComponentDef Model (SimpleView Model) CounterCells {}
downloadsCounter =
    counterComponent { label = "Downloads", step = 1 }


scaleCounter : ComponentDef Model (SimpleView Model) CounterCells {}
scaleCounter =
    counterComponent { label = "Scale", step = 10 }


type alias Model =
    { downloads : CounterCells
    , scale : CounterCells
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withInstance "downloads" downloadsCounter
            |> withInstance "scale" scaleCounter
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ embed downloadsCounter model.downloads
                , embed scaleCounter model.scale
                ]
    , reactions =
        \model _ ->
            include downloadsCounter model.downloads
                ++ include scaleCounter model.scale
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/counter-component.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>counter-component</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/CounterComponent.elm";
      Elm.CounterComponent.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after the last existing entry, e.g., `username-available`):

```javascript
"counter-component": resolve(__dirname, "counter-component.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`** after the last existing link:

```html
<li><a href="counter-component.html">counter-component</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 18 entries (index + 17 examples).

- [ ] **Step 7: Commit.**

```bash
git add examples/src/CounterComponent.elm examples/counter-component.html examples/vite.config.js examples/index.html
git commit -m "Ship counter-component example"
```

---

## Slice 7 — `tagpicker-component` example + docs sweep

### Task 7.1: Ship the tagpicker-component example

**Files:**
- Create: `examples/src/TagpickerComponent.elm`
- Create: `examples/tagpicker-component.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/TagpickerComponent.elm`:**

```elm
module TagpickerComponent exposing (main)

import Json.Decode as Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ComponentDef
        , DebouncedCell
        , Remote(..)
        , build
        , defineComponent
        , embed
        , include
        , listCodec
        , on
        , remoteCodec
        , run
        , settled
        , stringCodec
        , toSource
        , with
        , withDebounced
        , withInstance
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.View exposing (CommitTrigger(..))
import SimpleView
    exposing
        ( SimpleView
        , col
        , debouncedInput
        , simpleViewEngine
        , text
        , watch
        )


type alias TagPickerCells =
    { query : DebouncedCell String
    , suggestions : Cell (Remote RequestError (List String))
    }


matchesDecoder : Decode.Decoder (List String)
matchesDecoder =
    Decode.field "matches" (Decode.list Decode.string)


tagPicker : { endpoint : String, placeholder : String } -> ComponentDef model (SimpleView model) TagPickerCells {}
tagPicker config =
    defineComponent
        { init =
            build TagPickerCells
                |> withDebounced "query" 500 "" stringCodec
                |> with "suggestions" Idle (remoteCodec requestErrorCodec (listCodec stringCodec))
        , computed = \_ -> {}
        , view =
            \c _ ->
                col
                    [ debouncedInput
                        { label = config.placeholder
                        , cell = c.query
                        , triggers = [ OnEnter, OnBlur, OnTimeout ]
                        }
                    , watch (toSource c.suggestions) renderSuggestions
                    ]
        , reactions =
            \c _ ->
                [ on (settled c.query)
                    (\q ->
                        if String.trim q == "" then
                            Rad.noRequest

                        else
                            Http.httpGet prodHandler ("/api/search?q=" ++ q) matchesDecoder
                    )
                    c.suggestions
                ]
        }


renderSuggestions : Remote RequestError (List String) -> SimpleView model
renderSuggestions r =
    case r of
        Idle ->
            text "(type to search)"

        Loading ->
            text "searching…"

        Failed _ ->
            text "(error)"

        Done matches ->
            col (List.map (\m -> text (" • " ++ m)) matches)


categoryPicker : ComponentDef Model (SimpleView Model) TagPickerCells {}
categoryPicker =
    tagPicker { endpoint = "/api/search", placeholder = "Category…" }


tagPickerInstance : ComponentDef Model (SimpleView Model) TagPickerCells {}
tagPickerInstance =
    tagPicker { endpoint = "/api/search", placeholder = "Tag…" }


type alias Model =
    { category : TagPickerCells
    , tags : TagPickerCells
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withInstance "category" categoryPicker
            |> withInstance "tags" tagPickerInstance
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ embed categoryPicker model.category
                , embed tagPickerInstance model.tags
                ]
    , reactions =
        \model _ ->
            include categoryPicker model.category
                ++ include tagPickerInstance model.tags
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/tagpicker-component.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>tagpicker-component</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/TagpickerComponent.elm";
      Elm.TagpickerComponent.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after `counter-component`):

```javascript
"tagpicker-component": resolve(__dirname, "tagpicker-component.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="tagpicker-component.html">tagpicker-component</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 19 entries (index + 18 examples).

- [ ] **Step 7: Commit.**

```bash
git add examples/src/TagpickerComponent.elm examples/tagpicker-component.html examples/vite.config.js examples/index.html
git commit -m "Ship tagpicker-component example"
```

---

### Task 7.2: Append Implementation notes to `docs/design-elm-rad.md`

**Files:**
- Modify: `docs/design-elm-rad.md`

- [ ] **Step 1: Locate insertion point.** The Components section starts at `## Components` (around line 600). Its last subsection is `### Accessing component cells from the parent`. The next top-level section starts with `## Persistence` (around line 705). Insert a new `### Implementation notes` subsection immediately BEFORE `## Persistence`.

- [ ] **Step 2: Insert the subsection:**

```markdown
### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **`CellBuilder` is a lazy recipe.** Internally `CellBuilder ctor = CellBuilder (BuildState -> BuildResult ctor)` where `BuildState = { nextId, prefix }`. Nothing is allocated until a state flows in. This lets a component's `init` — written as a regular `build |> with |> ...` pipeline — be started at an arbitrary `nextId` and namespace prefix.

2. **`ComponentDef model view cells computed` has a `model` type parameter.** Elm requires free type variables inside record fields to be bound by the surrounding type constructor. The `reactions : cells -> computed -> List (Reaction model)` field forces `model` into the type. At use sites, `model` unifies with the outer app's model type.

3. **Cells record embeds directly in the parent model.** No `Instance` wrapper — cells are plain data, debugger-friendly, survive hot reload. Parent accesses via normal record access (`model.category.n`).

4. **Persistence keys namespace at build time, stamped only on `Cell.key`.** `withInstance "primary" componentDef` runs the component's init with an extended prefix; `with "selected"` stamps `"primary.selected"` on the `Cell` record's `.key`. `DebouncedCell` and `ValidatedCell` don't store a `key` today; Layer 7 will decide their persistence format.

5. **`embed` and `include` are dispatch helpers.** They take `ComponentDef` + `cells` and call the def's `view`/`reactions` with `computed` pre-applied. No component-scoped runtime state.

6. **No new `Msg` variants, no runtime changes.** Components dispatch through existing `ApplyAction` + `ReactionResult`. Engines stay unchanged. `AppModel model` tuple shape is unchanged.

7. **Recommended pattern: bind each parameterized `ComponentDef` at module level.** `ComponentDef` is written three times per use (`withInstance`, `embed`, `include`). Binding at module level (`downloadsCounter = counterComponent {label="Downloads", step=1}`) avoids reconstruction at each call site.
```

- [ ] **Step 3: Verify the file still reads coherently.** Scan around the insertion point.

- [ ] **Step 4: Commit.**

```bash
git add docs/design-elm-rad.md
git commit -m "docs: record Layer 6 implementation decisions"
```

---

## Final checkpoint — Task 8.1: Full verification sweep

- [ ] **Step 1: Package tests.**

Run: `npx --yes elm-test`
Expected: **90 tests pass** (78 pre-Layer-6 + 12 new Layer 6).

Actual breakdown: ComponentBuilderTest (1 test in Task 2.2) + ComponentInstanceTest (4 in Task 3.1) + ComponentDispatchTest (2 in Task 4.1) + ComponentValidatedTest (5 in Task 5.1) = 12 new tests.

- [ ] **Step 2: Package docs build.**

Run: `npx --yes elm make --docs docs.json`
Expected: success — `Rad`, `Rad.Engine`, `Rad.Http`, `Rad.Read`, `Rad.View` all documented.

- [ ] **Step 3: Examples build.**

Run: `cd examples && npm run build`
Expected: **19 HTML entries** (17 pre-Layer-6 entries, including the index page, plus 2 new Layer 6 examples).

- [ ] **Step 4: TestRunner still compiles.**

Run: `cd examples && npx --yes elm make src/TestRunner.elm --output=/dev/null`
Expected: success.

- [ ] **Step 5: Live smoke (if the dev server is running).**

```bash
for e in counter-component tagpicker-component; do
    echo "$e: $(curl -s -o /dev/null -w '%{http_code}' "http://localhost:5173/$e.html")"
done
```

Expected: `200` for both. Skip if dev server not running.

- [ ] **Step 6: Visual behavioral smoke (manual browser).**
- `counter-component`: click "+ (1)" next to Downloads → only Downloads increments by 1. Click "+ (10)" next to Scale → only Scale increments by 10. Isolation confirmed.
- `tagpicker-component`: type in the Category input → after 500ms → "searching…" → results. Type in the Tag input → same behavior, isolated state.

- [ ] **Step 7: Commit history sanity.**

Run: `git log --oneline 2ba74bf..HEAD`
Expected: ~10-11 commits — 1 design doc + 1 plan + 9 implementation commits (Task 1.1, 2.2, 3.1, 4.1, 5.1, 6.1, 7.1, 7.2, plus any follow-ups). All single-line imperative, no Co-Authored-By trailers.

- [ ] **Step 8: Clean tree.**

Run: `git status`
Expected: clean.

---

## Out-of-slice notes

- **If the CellBuilder refactor breaks any Layer 0-4 test:** bisect by reverting individual function bodies (`with`, `withDebounced`, `withValidated`) one at a time until the failure is isolated. The public API signatures haven't changed, so any failure is in the new body logic.
- **If `ComponentDef model view cells computed` type-annotation looks unwieldy in examples:** the `model` parameter is typically the outer app's model type. Users who write the type annotation only need to instantiate it at definition time (e.g., `ComponentDef Model (SimpleView Model) CounterCells {}`). Can be worked around with a type alias in user code if verbose.
- **If `cellKey` feels like it leaks internals:** this accessor was added for tests + potential Layer 7 persistence interop. It's a one-line function over an already-public field equivalent. If policy requires, it can be moved behind `Rad.Internal.CellAccess` in a future layer.
- **If a user forgets to include a component's reactions in `AppDef.reactions`:** the component's reactions simply don't fire. Same discoverability as forgetting `validationReactions` in Layer 4 — documented as consumer responsibility.
- **Design-doc correction reminder:** `ComponentDef` has 4 type parameters (`model view cells computed`) in the implementation, not 3 as the design doc sketches. If the design doc is ever updated, do not churn call sites here.
