# elm-rad Layers 0 & 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver Layers 0 (Foundation) and 1 (Reactivity) of the `elm-rad` DSL defined in [`docs/design-elm-rad.md`](../design-elm-rad.md), sync-only, with six example apps that each exercise a named subset of primitives, and a second view engine (`SimpleView`) in the examples folder that proves the `ViewEngine` abstraction.

**Architecture:** Cells are opaque references holding `{ id, key, codec }`. Values live in a runtime-managed `Registry = Dict Int Json.Value`. Actions are `Registry -> Registry` functions. The user's model record is a *static* record of cell references (not values); values are fetched through `toSource` / `watch`. `run` wraps `Browser.element` with `Cmd.none` / `Sub.none` so later layers can add effects without switching the harness.

**Tech Stack:** Elm 0.19.1 (package), `elm-explorations/test` 2.x, Vite 6, `vite-plugin-elm`, `npx elm` / `npx elm-test`.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per project preference — see memory `feedback_commit_cadence.md`).
- Every task is a single commit unless explicitly split.
- Verification command for the package: `cd /Users/bcardiff/Projects/bcardiff/elm-rad && npx --yes elm-test`.
- Verification command for examples: `cd /Users/bcardiff/Projects/bcardiff/elm-rad/examples && npm run build` (smoke) and `npm run dev` (visual).

**Module layout at the end:**
```
src/
  Rad.elm                    ← core: Cell, Source, Codec, Action, CellBuilder, AppDef, actions, codecs, watch, run
  Rad/
    View.elm                 ← htmlEngine, HTML primitives, Attribute, bind, onClick
    Read.elm                 ← Read monad (Slice 5)
    Engine.elm               ← engine-author API: Msg, fromAction, ViewEngine
tests/
  CodecTest.elm
  CellBuilderTest.elm
  ActionTest.elm
  ReadTest.elm               ← Slice 5
examples/
  index.html                 ← landing page
  greeting-html.html, greeting.html, counter.html, swap.html, full-name.html, temperature.html
  src/
    GreetingHtml.elm, Greeting.elm, Counter.elm, Swap.elm, FullName.elm, Temperature.elm
    SimpleView.elm
  elm.json, package.json, vite.config.js, README.md
```

---

## Slice 1 — Runtime skeleton + `greeting-html` ships

**Objective:** When done, `examples/greeting-html.html` renders an input bound to a `Cell String` and a live-updating greeting below it, built on the shipped `htmlEngine`. elm-test covers codecs, CellBuilder, and action semantics.

### Task 1.1: Bootstrap elm-test

**Files:**
- Modify: `elm.json` (add test-dependencies)
- Create: `tests/CodecTest.elm` (sanity test)

**Step 1: Edit `elm.json`** — replace `"test-dependencies": {}` with:

```json
"test-dependencies": {
    "elm-explorations/test": "2.0.0 <= v < 3.0.0"
}
```

**Step 2: Create `tests/CodecTest.elm`** with a trivial test to prove the harness runs:

```elm
module CodecTest exposing (suite)

import Expect
import Test exposing (..)


suite : Test
suite =
    test "elm-test harness works" <|
        \_ -> Expect.equal 1 1
```

**Step 3: Run `npx --yes elm-test`.** Expected: `TEST RUN PASSED`, 1 test.

**Step 4: Commit.**

```bash
git add elm.json tests/CodecTest.elm
git commit -m "Bootstrap elm-test harness"
```

---

### Task 1.2: Codec type and basic codecs

**Files:**
- Modify: `src/Rad.elm` (replace placeholder with `Codec` + basic codecs)
- Modify: `tests/CodecTest.elm` (round-trip tests)

**Step 1: Write failing tests in `tests/CodecTest.elm`:**

```elm
module CodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec)
import Test exposing (..)


suite : Test
suite =
    describe "Codec round-trips"
        [ test "stringCodec" <|
            \_ -> roundTrip stringCodec "hello" |> Expect.equal (Ok "hello")
        , test "intCodec" <|
            \_ -> roundTrip intCodec 42 |> Expect.equal (Ok 42)
        , test "floatCodec" <|
            \_ -> roundTrip floatCodec 3.14 |> Expect.equal (Ok 3.14)
        , test "boolCodec" <|
            \_ -> roundTrip boolCodec True |> Expect.equal (Ok True)
        , test "listCodec of strings" <|
            \_ -> roundTrip (listCodec stringCodec) [ "a", "b" ] |> Expect.equal (Ok [ "a", "b" ])
        , test "maybeCodec Just" <|
            \_ -> roundTrip (maybeCodec intCodec) (Just 7) |> Expect.equal (Ok (Just 7))
        , test "maybeCodec Nothing" <|
            \_ -> roundTrip (maybeCodec intCodec) Nothing |> Expect.equal (Ok Nothing)
        ]


roundTrip : { encode : a -> Decode.Value, decode : Decode.Decoder a } -> a -> Result Decode.Error a
roundTrip codec value =
    codec.encode value |> Decode.decodeValue codec.decode
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.stringCodec` etc. not exposed).

**Step 3: Implement in `src/Rad.elm`:**

```elm
module Rad exposing
    ( Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    )

{-| elm-rad — reactive cell DSL.

@docs Codec
@docs boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| A pair of encoder and decoder for serializing cell values.
-}
type alias Codec a =
    { encode : a -> Decode.Value
    , decode : Decode.Decoder a
    }


{-| -}
stringCodec : Codec String
stringCodec =
    { encode = Encode.string, decode = Decode.string }


{-| -}
intCodec : Codec Int
intCodec =
    { encode = Encode.int, decode = Decode.int }


{-| -}
floatCodec : Codec Float
floatCodec =
    { encode = Encode.float, decode = Decode.float }


{-| -}
boolCodec : Codec Bool
boolCodec =
    { encode = Encode.bool, decode = Decode.bool }


{-| -}
listCodec : Codec a -> Codec (List a)
listCodec inner =
    { encode = Encode.list inner.encode
    , decode = Decode.list inner.decode
    }


{-| -}
maybeCodec : Codec a -> Codec (Maybe a)
maybeCodec inner =
    { encode =
        \m ->
            case m of
                Just v ->
                    inner.encode v

                Nothing ->
                    Encode.null
    , decode = Decode.nullable inner.decode
    }
```

**Step 4: Run `npx --yes elm-test`** — expected: all tests pass.

**Step 5: Commit.**

```bash
git add src/Rad.elm tests/CodecTest.elm
git commit -m "Add Codec type and basic codecs"
```

---

### Task 1.3: Internal Registry + Cell type

**Files:**
- Create: `src/Rad/Internal/Registry.elm`
- Modify: `src/Rad.elm` (add `Cell` opaque type)
- Modify: `elm.json` (no change — `Rad.Internal.*` stays unexposed)

No tests yet — covered indirectly by Task 1.4's CellBuilder tests.

**Step 1: Create `src/Rad/Internal/Registry.elm`:**

```elm
module Rad.Internal.Registry exposing (Registry, empty, get, insert)

import Dict exposing (Dict)
import Json.Decode as Decode


type alias Registry =
    Dict Int Decode.Value


empty : Registry
empty =
    Dict.empty


insert : Int -> Decode.Value -> Registry -> Registry
insert =
    Dict.insert


get : Int -> Registry -> Maybe Decode.Value
get =
    Dict.get
```

**Step 2: Extend `src/Rad.elm`** — add the opaque `Cell a` type (internally a record). Do **not** expose the constructor yet; expose only the type:

Add to the module declaration:

```elm
module Rad exposing
    ( Cell
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    )
```

Add to the docs block: `@docs Cell`.

Append the type definition at the bottom of the file:

```elm
{-| A reactive state cell holding a value of type `a`.
-}
type Cell a
    = Cell
        { id : Int
        , key : String
        , codec : Codec a
        }
```

**Step 3: Run `npx --yes elm-test`** — expected: still passes (no test changes, nothing uses `Cell` yet; `Rad.Internal.Registry` must compile).

**Step 4: Commit.**

```bash
git add src/Rad/Internal/Registry.elm src/Rad.elm
git commit -m "Add internal Registry module and opaque Cell type"
```

---

### Task 1.4: CellBuilder + `build` + `with`

**Files:**
- Modify: `src/Rad.elm` (add `CellBuilder`, `build`, `with`, internal `runBuilder`)
- Create: `tests/CellBuilderTest.elm`

**Step 1: Write failing tests in `tests/CellBuilderTest.elm`:**

```elm
module CellBuilderTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Cell, build, intCodec, stringCodec, with)
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { name : Cell String
    , age : Cell Int
    }


suite : Test
suite =
    describe "CellBuilder"
        [ test "assigns distinct cell IDs" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                -- We can't read internal IDs directly, so we assert via Registry population.
                Expect.pass
        , test "registry has one entry per cell at their declared initial value" <|
            \_ ->
                let
                    ( _, registry ) =
                        Rad.runBuilder init

                    decoded =
                        ( Registry.get 0 registry |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)
                        , Registry.get 1 registry |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                        )
                in
                Expect.equal ( Just "alice", Just 30 ) decoded
        ]


init : Rad.CellBuilder Model
init =
    build Model
        |> with "name" "alice" stringCodec
        |> with "age" 30 intCodec
```

(Note: this test reaches into `Rad.runBuilder` and `Rad.Internal.Registry` — both must be exposed for tests. We expose `runBuilder` under `Rad` temporarily; consider moving to `Rad.Internal` later if we want to keep the public API minimal.)

**Step 2: Run `npx --yes elm-test`** — expected: compile errors (`Rad.build`, `Rad.with`, `Rad.CellBuilder`, `Rad.runBuilder` missing).

**Step 3: Implement in `src/Rad.elm`.** Add to the module exposing list: `CellBuilder`, `build`, `with`, `runBuilder`. Add to docs: `@docs CellBuilder, build, with`.

```elm
{-| An applicative builder for constructing a model made of cells.
-}
type CellBuilder a
    = CellBuilder
        { nextId : Int
        , metas : List ( Int, Decode.Value )  -- (id, initial-as-json) in reverse order
        , ctor : a
        }


{-| Start a CellBuilder from a model constructor.
-}
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        { nextId = 0
        , metas = []
        , ctor = ctor
        }


{-| Add one cell to the builder, consuming one argument of the constructor.
-}
with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder b) =
    let
        cell =
            Cell { id = b.nextId, key = key, codec = codec }
    in
    CellBuilder
        { nextId = b.nextId + 1
        , metas = ( b.nextId, codec.encode initial ) :: b.metas
        , ctor = b.ctor cell
        }


{-| Extract the finished model and the initial registry.

Exposed for test access and for the `run` function. Not part of the user-facing
DSL in typical usage.
-}
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder b) =
    ( b.ctor
    , b.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty
    )
```

Import `Rad.Internal.Registry as Registry exposing (Registry)` at the top. Import `Json.Decode as Decode`.

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Commit.**

```bash
git add src/Rad.elm tests/CellBuilderTest.elm
git commit -m "Add CellBuilder with build and with"
```

---

### Task 1.5: `Source` type + `toSource`

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/CellBuilderTest.elm` (add toSource assertions)

**Step 1: Write failing test** — add to `tests/CellBuilderTest.elm`:

```elm
, test "toSource reads the current value of a cell from the registry" <|
    \_ ->
        let
            ( model, registry ) =
                Rad.runBuilder init

            source =
                Rad.toSource model.name
        in
        Expect.equal "alice" (Rad.readSource source registry)
```

Also import `readSource` from `Rad` (see below).

**Step 2: Run tests** — expected: compile error.

**Step 3: Implement.** In `src/Rad.elm`, add to exposing: `Source`, `toSource`, `readSource`:

```elm
{-| Anything readable. Cells, derived values, and later debounced/validated
accessors all convert to `Source`.
-}
type Source a
    = Source (Registry -> a)


{-| Convert a cell into a readable source.
-}
toSource : Cell a -> Source a
toSource (Cell c) =
    Source
        (\registry ->
            case Registry.get c.id registry of
                Just v ->
                    case Decode.decodeValue c.codec.decode v of
                        Ok a ->
                            a

                        Err _ ->
                            -- Invariant: the registry was written by this cell's
                            -- codec, so decode must succeed.
                            -- This branch should be unreachable in normal use.
                            Debug.todo "registry codec mismatch"

                Nothing ->
                    Debug.todo "registry missing cell"
        )


{-| Read a source against a registry. Exposed for tests and for the runtime.
-}
readSource : Source a -> Registry -> a
readSource (Source f) registry =
    f registry
```

**Step 4: Run tests** — expected: all pass.

**Step 5: Commit.**

```bash
git add src/Rad.elm tests/CellBuilderTest.elm
git commit -m "Add Source type and toSource"
```

---

### Task 1.6: `Action` type + `set`

**Files:**
- Modify: `src/Rad.elm`
- Create: `tests/ActionTest.elm`

**Step 1: Write failing tests in `tests/ActionTest.elm`:**

```elm
module ActionTest exposing (suite)

import Expect
import Rad exposing (Cell, build, set, stringCodec, with)
import Test exposing (..)


type alias Model =
    { name : Cell String }


init : Rad.CellBuilder Model
init =
    build Model |> with "name" "alice" stringCodec


suite : Test
suite =
    describe "Actions"
        [ test "set replaces the cell's value" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (set model.name "bob") registry0

                    source =
                        Rad.toSource model.name
                in
                Expect.equal "bob" (Rad.readSource source registry1)
        ]
```

**Step 2: Run tests** — compile error (`set`, `applyAction` missing).

**Step 3: Implement** — add to exposing in `src/Rad.elm`: `Action`, `set`, `applyAction`.

```elm
{-| A synchronous action against the cell registry. Phantom `model` parameter
reserves type-level differentiation for later layers.
-}
type Action model
    = Action (Registry -> Registry)


{-| Set a cell to a given value.
-}
set : Cell a -> a -> Action model
set (Cell c) value =
    Action (Registry.insert c.id (c.codec.encode value))


{-| Apply an action to a registry. Exposed for tests and the runtime.
-}
applyAction : Action model -> Registry -> Registry
applyAction (Action f) registry =
    f registry
```

**Step 4: Run tests** — expected: all pass.

**Step 5: Commit.**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add Action type and set"
```

---

### Task 1.7: `Rad.Engine` module

**Files:**
- Create: `src/Rad/Engine.elm`
- Modify: `elm.json` (expose `Rad.Engine`)

No tests yet — covered when `run` lands.

**Step 1: Edit `elm.json` exposed-modules:**

```json
"exposed-modules": [
    "Rad",
    "Rad.Engine"
]
```

**Step 2: Create `src/Rad/Engine.elm`:**

```elm
module Rad.Engine exposing (Msg, ViewEngine, fromAction)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction

-}

import Html exposing (Html)
import Rad exposing (Action)


{-| The runtime message type. Opaque. Engines construct values via `fromAction`.
Later layers add internal variants without breaking engines.
-}
type Msg model
    = ApplyAction (Action model)


{-| Convert a user-level action into a runtime message that engines can attach
to event handlers.
-}
fromAction : Action model -> Msg model
fromAction =
    ApplyAction


{-| A view engine transforms the engine's view type into `Html (Msg model)`
for the Elm runtime to render.
-}
type alias ViewEngine view model =
    { toHtml : view -> Html (Msg model)
    }
```

**Step 3: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles (both modules documented).

**Step 4: Commit.**

```bash
git add elm.json src/Rad/Engine.elm
git commit -m "Add Rad.Engine with Msg, ViewEngine, and fromAction"
```

---

### Task 1.8: `Rad.View` module — `Attribute`, `bind`, `htmlEngine`, HTML primitives

**Files:**
- Create: `src/Rad/View.elm`
- Modify: `elm.json` (expose `Rad.View`)

No automated tests — verified via `greeting-html`. Internal sanity: compile smoke.

**Step 1: Edit `elm.json` exposed-modules:**

```json
"exposed-modules": [
    "Rad",
    "Rad.Engine",
    "Rad.View"
]
```

**Step 2: Create `src/Rad/View.elm`:**

```elm
module Rad.View exposing
    ( Attribute, HtmlView
    , bind
    , col, input, text
    , htmlEngine
    )

{-| The HTML view engine and its primitives.

@docs Attribute, HtmlView
@docs bind
@docs col, input, text
@docs htmlEngine

-}

import Html
import Html.Attributes
import Html.Events
import Rad exposing (Cell, set)
import Rad.Engine exposing (Msg, ViewEngine, fromAction)


{-| An attribute applied to an HTML primitive. Encodes reactive intent (bind,
onClick, etc.) that `htmlEngine` wires into real `Html.Attribute`s at render
time.
-}
type Attribute model
    = BindString (Cell String)


{-| The HTML view value produced by the primitives below.
-}
type HtmlView model
    = HtmlView (Html.Html (Msg model))


{-| Two-way bind an input's value to a `Cell String`.
-}
bind : Cell String -> Attribute model
bind =
    BindString


{-| A vertical stack.
-}
col : List (Attribute model) -> List (HtmlView model) -> HtmlView model
col _ children =
    HtmlView (Html.div [] (List.map unwrapHtmlView children))


{-| An HTML `<input>`.
-}
input : List (Attribute model) -> List (HtmlView model) -> HtmlView model
input attrs _ =
    let
        bindAttrs =
            List.concatMap
                (\a ->
                    case a of
                        BindString cell ->
                            [ Html.Events.onInput (\v -> fromAction (set cell v))
                            , Html.Attributes.value "" -- overridden at render by the reactive read; Slice 1 uses defaultValue behaviour
                            ]
                )
                attrs
    in
    HtmlView (Html.input bindAttrs [])


{-| Plain text.
-}
text : String -> HtmlView model
text s =
    HtmlView (Html.text s)


{-| The shipped HTML engine.
-}
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = unwrapHtmlView }


unwrapHtmlView : HtmlView model -> Html.Html (Msg model)
unwrapHtmlView (HtmlView h) =
    h
```

**Note on `input`'s value:** Layer 0+1 `bind` wires an `onInput` dispatcher. The input's *displayed* value falls out because we re-render on every registry change (Task 1.10). The current registry value is used to populate `Html.Attributes.value`. We'll refine this in Task 1.10 when `run` is in place.

**Step 3: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 4: Commit.**

```bash
git add elm.json src/Rad/View.elm
git commit -m "Add Rad.View with htmlEngine and primitives"
```

---

### Task 1.9: `watch` primitive

**Files:**
- Modify: `src/Rad.elm` (add `watch`)
- Modify: `src/Rad/View.elm` (refine `input` to use current registry value)

**Note:** `watch` is generic over the view type. Since it must produce a `view`, it needs to be supplied with a way to render — but for Layer 0+1 we only have HTML and (soon) SimpleView. The cleanest way: `watch` takes the current registry as hidden state. For the simplest implementation, the *engines* are responsible for threading registry reads. We'll implement `watch` as a function that captures a `Source` and a continuation, to be evaluated at render time by the engine.

A straightforward realization: `watch` returns a view-engine-specific value. Since we can't polymorphically return `view`, we use the fact that `HtmlView` and `SimpleView` both carry the `Msg model` type. We'll define `watch` *inside the engine* rather than as a Rad primitive at this phase — meaning `Rad.View.watch` and `SimpleView.watch`, each with the same signature:

```elm
watch : Source a -> (a -> HtmlView model) -> HtmlView model
```

This keeps `watch` truly engine-aware (it must know how to construct a reactive wrapper node for that engine) without pretending to be fully generic. If we later want a single generic `watch`, we can introduce a typeclass-like pattern at that point.

**Revision for clarity:** make `watch` live in each view engine's module. Document this as an explicit design note.

**Step 1: Add `watch` to `src/Rad/View.elm`.** Since re-rendering the whole tree on every registry change is how we get reactivity (Task 1.10), `watch` simply *reads* from the registry at render time. But the primitives don't have a registry in scope.

The pragmatic solution: `HtmlView model` becomes a thunk over the registry.

Replace the definition of `HtmlView`:

```elm
type HtmlView model
    = HtmlView (Registry -> Html.Html (Msg model))
```

(Import `Rad.Internal.Registry exposing (Registry)`.)

Refactor `col`, `text`:

```elm
col _ children =
    HtmlView
        (\r ->
            Html.div [] (List.map (\(HtmlView f) -> f r) children)
        )


text s =
    HtmlView (\_ -> Html.text s)
```

Refactor `input` to read the bound cell's current value from the registry:

```elm
input attrs _ =
    HtmlView
        (\registry ->
            let
                ( bindCell, evtAttrs ) =
                    List.foldl
                        (\a ( mc, evts ) ->
                            case a of
                                BindString cell ->
                                    ( Just cell
                                    , Html.Events.onInput (\v -> fromAction (set cell v)) :: evts
                                    )
                        )
                        ( Nothing, [] )
                        attrs

                valueAttr =
                    case bindCell of
                        Just cell ->
                            [ Html.Attributes.value (Rad.readSource (Rad.toSource cell) registry) ]

                        Nothing ->
                            []
            in
            Html.input (valueAttr ++ evtAttrs) []
        )
```

Add `watch`:

```elm
{-| Subscribe a view region to a source. Re-renders when the source's value
changes (achieved via whole-tree re-render on any registry change in Layer 0+1).
-}
watch : Source a -> (a -> HtmlView model) -> HtmlView model
watch source f =
    HtmlView
        (\registry ->
            let
                (HtmlView g) =
                    f (Rad.readSource source registry)
            in
            g registry
        )
```

Update `htmlEngine` to apply the registry:

```elm
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = \(HtmlView f) -> f (Rad.Engine.currentRegistry) }
```

**Wait** — the engine's `toHtml : view -> Html (Msg model)` doesn't have access to the registry. The registry lives inside the Elm runtime's model. So the signature of `toHtml` must change, or the engine must bundle registry access.

**Step 1 (revised):** The cleanest refactor is: `ViewEngine` changes to carry a render function that takes the registry, not just the view. This changes `Rad.Engine` and `run`.

Update `Rad/Engine.elm`:

```elm
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
```

(Import `Rad.Internal.Registry exposing (Registry)`.)

Update `Rad/View.elm`'s `htmlEngine`:

```elm
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = \registry (HtmlView f) -> f registry }
```

**Step 2: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 3: Commit.**

```bash
git add src/Rad.elm src/Rad/Engine.elm src/Rad/View.elm
git commit -m "Add watch and thread Registry through ViewEngine.toHtml"
```

---

### Task 1.10: `AppDef` + `run`

**Files:**
- Modify: `src/Rad.elm` (add `AppDef`, `run`)

**Step 1: Add `AppDef`:**

```elm
{-| An application definition. Grows additional fields in later layers
(`reactions`, `persist`).
-}
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    }
```

**Step 2: Add `run`:**

```elm
{-| Run an application. Wraps `Browser.element` so later layers can add
effects without changing the harness.
-}
run : Rad.Engine.ViewEngine view model -> AppDef view model computed -> Program () ( model, Registry ) (Rad.Engine.Msg model)
run engine app =
    let
        ( model, initialRegistry ) =
            runBuilder app.init
    in
    Browser.element
        { init = \() -> ( ( model, initialRegistry ), Cmd.none )
        , update =
            \msg ( m, registry ) ->
                case msg of
                    Rad.Engine.ApplyAction action ->
                        ( ( m, applyAction action registry ), Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
```

**Note:** `Rad.Engine.ApplyAction` is the internal `Msg` constructor. To pattern-match, either expose it or add a helper `Rad.Engine.applyMsg : Msg model -> Registry -> Registry`.

**Alternative (cleaner):** add a helper in `Rad.Engine`:

```elm
applyMsg : Msg model -> Rad.Internal.Registry.Registry -> Rad.Internal.Registry.Registry
applyMsg (ApplyAction action) registry =
    Rad.applyAction action registry
```

Then `run` does `applyMsg msg registry`.

Decision: expose `applyMsg` in `Rad.Engine` (it's already an engine/runtime-boundary concern).

**Step 3: Expose in `Rad`'s module declaration:** `AppDef`, `run`.

**Step 4: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 5: Run `npx --yes elm-test`** — expected: still all green.

**Step 6: Commit.**

```bash
git add src/Rad.elm src/Rad/Engine.elm
git commit -m "Add AppDef and run"
```

---

### Task 1.11: Restructure examples to multi-entry Vite

**Files:**
- Modify: `examples/vite.config.js` (multi-entry)
- Modify: `examples/package.json` (no script changes; deps unchanged)
- Modify: `examples/elm.json` (source-directories unchanged for now, but we'll rename Main.elm later)
- Create: `examples/index.html` (landing page)
- Delete: `examples/src/Main.elm`, `examples/src/main.js` (obsolete)
- Delete: `examples/index.html` (replaced by landing page — it was the single-entry one)

**Step 1: Replace `examples/index.html`** with a landing page:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>elm-rad examples</title>
  </head>
  <body>
    <h1>elm-rad examples</h1>
    <ul>
      <li><a href="greeting-html.html">greeting (htmlEngine)</a></li>
      <li><a href="greeting.html">greeting (SimpleView)</a></li>
      <li><a href="counter.html">counter</a></li>
      <li><a href="swap.html">swap</a></li>
      <li><a href="full-name.html">full-name</a></li>
      <li><a href="temperature.html">temperature</a></li>
    </ul>
    <p>Links are dead until each example lands in its slice.</p>
  </body>
</html>
```

**Step 2: Update `examples/vite.config.js` to list multi-entry inputs:**

```js
import { defineConfig } from "vite";
import { resolve } from "path";
import elm from "vite-plugin-elm";

export default defineConfig({
  plugins: [elm()],
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, "index.html"),
        "greeting-html": resolve(__dirname, "greeting-html.html"),
      },
    },
  },
});
```

(Only `index.html` and `greeting-html.html` are listed — we add entries as each example lands.)

**Step 3: Remove obsolete single-entry files:**

```bash
git rm examples/src/Main.elm examples/src/main.js
```

**Step 4: Verify `npm run build` fails because `greeting-html.html` doesn't exist yet** — expected: Vite reports a missing input. That's OK; we'll add it in Task 1.12. **Don't commit until Task 1.12.** Alternatively, defer the Vite config change until 1.12 so each commit compiles.

**Refinement: split into two commits.** Move the Vite config update into Task 1.12 so this task ends in a compiling state.

Commit just the landing page replacement + deletions:

```bash
git add examples/index.html
git rm examples/src/Main.elm examples/src/main.js
git commit -m "Replace single-entry placeholder with landing page"
```

---

### Task 1.12: Create `greeting-html` app

**Files:**
- Create: `examples/greeting-html.html`
- Create: `examples/src/GreetingHtml.elm`
- Modify: `examples/vite.config.js` (add greeting-html input)

**Step 1: Create `examples/src/GreetingHtml.elm`:**

```elm
module GreetingHtml exposing (main)

import Rad exposing (AppDef, Cell, build, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import Rad.View exposing (HtmlView, bind, col, htmlEngine, input, text, watch)


type alias Model =
    { name : Cell String }


app : AppDef (HtmlView Model) Model {}
app =
    { init = build Model |> with "name" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col []
                [ input [ bind model.name ] []
                , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))
                ]
    }


main : Program () ( Model, Rad.Internal.Registry.Registry ) (Msg Model)
main =
    run htmlEngine app
```

**Note:** `Rad.Internal.Registry` is not exposed in `elm.json`. Either expose it (bad — leaks internals) or introduce a public type alias in `Rad` like:

```elm
type alias AppModel model =
    ( model, Rad.Internal.Registry.Registry )
```

Add `AppModel` to the exposed API.

Then `main : Program () (AppModel Model) (Msg Model)`.

**Step 2: Create `examples/greeting-html.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>greeting (htmlEngine)</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/GreetingHtml.elm";
      Elm.GreetingHtml.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

**Step 3: Update `examples/vite.config.js`** to include `greeting-html` (see Task 1.11).

**Step 4: Run `cd examples && npm run build`** — expected: succeeds, outputs `dist/index.html`, `dist/greeting-html.html`, and chunked JS.

**Step 5: Run `cd examples && npm run dev`** and visit `http://localhost:5173/greeting-html.html`. Type in the input. Expected: the greeting below the input updates on every keystroke.

**Step 6: Commit.**

```bash
git add examples/greeting-html.html examples/src/GreetingHtml.elm examples/vite.config.js
git commit -m "Add greeting-html example"
```

---

### Slice 1 wrap-up

- All `elm-test` suites pass (`npx --yes elm-test`).
- `npm run build` in `examples/` produces multi-entry build.
- `greeting-html` renders and updates live in the browser.
- Package exposes: `Rad` (core + AppDef + run + AppModel + actions), `Rad.View` (htmlEngine + primitives), `Rad.Engine` (Msg + fromAction + applyMsg + ViewEngine).

---

## Slice 2 — `SimpleView` engine + `greeting` ships

**Objective:** Add an examples-local `SimpleView` engine; port the greeting example to it.

### Task 2.1: Create `SimpleView` module

**Files:**
- Create: `examples/src/SimpleView.elm`

**Step 1: Implement the module** with the shape:

```elm
module SimpleView exposing
    ( SimpleView
    , button, col, input, text, watch
    , simpleViewEngine
    )

import Html
import Html.Attributes
import Html.Events
import Rad exposing (Action, Cell, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction)
import Rad.Internal.Registry exposing (Registry)


type SimpleView model
    = SimpleView (Registry -> Html.Html (Msg model))


col : List (SimpleView model) -> SimpleView model
col children =
    SimpleView
        (\r ->
            Html.div [] (List.map (\(SimpleView f) -> f r) children)
        )


input : { label : String, cell : Cell String } -> SimpleView model
input { label, cell } =
    SimpleView
        (\registry ->
            Html.label []
                [ Html.text (label ++ ": ")
                , Html.input
                    [ Html.Attributes.value (Rad.readSource (toSource cell) registry)
                    , Html.Events.onInput (\v -> fromAction (set cell v))
                    ]
                    []
                ]
        )


button : { label : String, onClick : Action model } -> SimpleView model
button { label, onClick } =
    SimpleView
        (\_ ->
            Html.button
                [ Html.Events.onClick (fromAction onClick) ]
                [ Html.text label ]
        )


text : String -> SimpleView model
text s =
    SimpleView (\_ -> Html.text s)


watch : Rad.Source a -> (a -> SimpleView model) -> SimpleView model
watch source f =
    SimpleView
        (\registry ->
            let
                (SimpleView g) =
                    f (Rad.readSource source registry)
            in
            g registry
        )


simpleViewEngine : ViewEngine (SimpleView model) model
simpleViewEngine =
    { toHtml = \registry (SimpleView f) -> f registry }
```

**Note:** `button` is included even though Slice 3 is where it's first consumed. Including it here keeps `SimpleView.elm` internally complete — later slices don't touch this file.

**Step 2: Run `cd examples && npm run build`** — expected: succeeds (SimpleView.elm compiles, unused for now).

**Step 3: Commit.**

```bash
git add examples/src/SimpleView.elm
git commit -m "Add SimpleView engine in examples"
```

### Task 2.2: Port greeting to SimpleView

**Files:**
- Create: `examples/src/Greeting.elm`
- Create: `examples/greeting.html`
- Modify: `examples/vite.config.js` (add `greeting` input)

**Step 1: Create `Greeting.elm`:**

```elm
module Greeting exposing (main)

import Rad exposing (AppDef, AppModel, Cell, build, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { name : Cell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "name" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = model.name }
                , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))
                ]
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

**Step 2: Create `examples/greeting.html`** (same template as `greeting-html.html`, pointing to `Greeting.elm`, module name `Greeting`).

**Step 3: Update vite.config.js** with `greeting: resolve(__dirname, "greeting.html")`.

**Step 4: Run `npm run build`, then `npm run dev`, visit `/greeting.html`.** Expected: identical behavior to `greeting-html`, label says "Name:".

**Step 5: Commit.**

```bash
git add examples/greeting.html examples/src/Greeting.elm examples/vite.config.js
git commit -m "Add greeting example on SimpleView"
```

---

## Slice 3 — `counter` ships

**Objective:** Add `modify`, `onClick`, HTML `button`. Counter example uses SimpleView.

### Task 3.1: `modify` action

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/ActionTest.elm`

**Step 1: Write failing test** — append to `ActionTest`:

```elm
, test "modify applies a function to the cell's value" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder init

            registry1 =
                Rad.applyAction (Rad.set model.name "hi") registry0

            registry2 =
                Rad.applyAction (Rad.modify model.name (\s -> s ++ "!")) registry1
        in
        Expect.equal "hi!" (Rad.readSource (Rad.toSource model.name) registry2)
```

**Step 2: Run tests** — compile error.

**Step 3: Implement `modify`:**

```elm
modify : Cell a -> (a -> a) -> Action model
modify ((Cell c) as cell) f =
    Action
        (\registry ->
            let
                current =
                    Rad.readSource (toSource cell) registry
            in
            Registry.insert c.id (c.codec.encode (f current)) registry
        )
```

Add to exposing list.

**Step 4: Run tests** — pass.

**Step 5: Commit.**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add modify action"
```

### Task 3.2: HTML `button` primitive + `onClick`

**Files:**
- Modify: `src/Rad/View.elm`

**Step 1: Add an `OnClick` constructor to `Attribute`:**

```elm
type Attribute model
    = BindString (Cell String)
    | OnClick (Action model)
```

**Step 2: Add `onClick`:**

```elm
onClick : Action model -> Attribute model
onClick =
    OnClick
```

**Step 3: Add `button`:**

```elm
button : List (Attribute model) -> List (HtmlView model) -> HtmlView model
button attrs children =
    HtmlView
        (\registry ->
            let
                clickAttrs =
                    List.concatMap
                        (\a ->
                            case a of
                                OnClick action ->
                                    [ Html.Events.onClick (fromAction action) ]

                                _ ->
                                    []
                        )
                        attrs
            in
            Html.button clickAttrs
                (List.map (\(HtmlView f) -> f registry) children)
        )
```

**Step 4: Update `input`'s `foldl` case to ignore `OnClick`** (pattern-match exhaustively).

**Step 5: Export in module declaration:** `onClick`, `button`.

**Step 6: Run `elm make --docs`** — expected: compiles.

**Step 7: Commit.**

```bash
git add src/Rad/View.elm
git commit -m "Add onClick attribute and button primitive"
```

### Task 3.3: Counter example

**Files:**
- Create: `examples/src/Counter.elm`
- Create: `examples/counter.html`
- Modify: `examples/vite.config.js`

**Step 1: `Counter.elm`:**

```elm
module Counter exposing (main)

import Rad exposing (AppDef, AppModel, Cell, build, intCodec, modify, run, set, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


type alias Model =
    { n : Cell Int }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "n" 0 intCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.n) (\n -> text ("Count: " ++ String.fromInt n))
                , button { label = "−", onClick = modify model.n (\n -> n - 1) }
                , button { label = "+", onClick = modify model.n (\n -> n + 1) }
                , button { label = "reset", onClick = set model.n 0 }
                ]
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

**Step 2: `counter.html`** (template).

**Step 3: Update `vite.config.js`.**

**Step 4: `npm run build && npm run dev`, visit `/counter.html`.** Click buttons, verify counts.

**Step 5: Commit.**

```bash
git add examples/counter.html examples/src/Counter.elm examples/vite.config.js
git commit -m "Add counter example"
```

---

## Slice 4 — `swap` ships

**Objective:** Add `copy`, `batch`. Swap example uses `batch` + intermediate temp cell.

### Task 4.1: `copy` action

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/ActionTest.elm`

**Test:**

```elm
, test "copy reads source then writes to target" <|
    \_ ->
        let
            -- Two cells a and b. Copy a->b after setting a. Expect b == original a value.
            ...
```

**Implementation:**

```elm
copy : Source a -> Cell a -> Action model
copy source (Cell c) =
    Action
        (\registry ->
            Registry.insert c.id (c.codec.encode (Rad.readSource source registry)) registry
        )
```

(Note: `readSource` is already exposed; `copy`'s source type is `Source a`, so the codec for encoding must be the target cell's — same type, so it round-trips through the target's codec. Slight subtlety: if source and target cells had different codecs for the same `a`, encoding is via target's. Layer 0+1 typically uses identical codecs so this is fine.)

**Commit:**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add copy action"
```

### Task 4.2: `batch` action

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/ActionTest.elm`

**Tests:**
- Empty batch is a no-op.
- Batch applies actions in list order (first applied first).
- Nested batch flattens (execution order preserved).

**Implementation:**

```elm
batch : List (Action model) -> Action model
batch actions =
    Action
        (\registry ->
            List.foldl (\(Action f) -> f) registry actions
        )
```

Flattening happens naturally because `Action` is just a function composition.

**Commit:**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add batch action"
```

### Task 4.3: Swap example

**Files:**
- Create: `examples/src/Swap.elm`, `examples/swap.html`
- Modify: `examples/vite.config.js`

**View shape:**

```elm
col
    [ input { label = "A", cell = model.a }
    , input { label = "B", cell = model.b }
    , button
        { label = "swap"
        , onClick =
            batch
                [ copy (toSource model.a) model.tmp
                , copy (toSource model.b) model.a
                , copy (toSource model.tmp) model.b
                ]
        }
    ]
```

Model has three `Cell String`s: `a`, `b`, `tmp`.

**Commit:**

```bash
git add examples/swap.html examples/src/Swap.elm examples/vite.config.js
git commit -m "Add swap example"
```

---

## Slice 5 — `full-name` ships *(Layer 1 begins)*

**Objective:** Add `Rad.Read` module with `Read`, `read`, `Read.map`, `Read.map2`, `derive`. Full-name example demonstrates derived values.

### Task 5.1: `Rad.Read` module

**Files:**
- Create: `src/Rad/Read.elm`
- Create: `tests/ReadTest.elm`
- Modify: `elm.json` (expose `Rad.Read`)

**Implementation sketch:**

```elm
module Rad.Read exposing (Read, map, map2, read)


type Read a
    = Read (Rad.Internal.Registry.Registry -> a)


read : Rad.Source a -> Read a
read source =
    Read (Rad.readSource source)


map : (a -> b) -> Read a -> Read b
map f (Read g) =
    Read (\r -> f (g r))


map2 : (a -> b -> c) -> Read a -> Read b -> Read c
map2 f (Read g) (Read h) =
    Read (\r -> f (g r) (h r))
```

### Task 5.2: `derive` (in `Rad`)

`derive : Read a -> Source a` — turns a Read into a Source.

```elm
derive : Rad.Read.Read a -> Source a
derive readValue =
    Source (\registry -> Rad.Read.runRead readValue registry)
```

(Requires exposing an internal `runRead` from `Rad.Read`.)

### Task 5.3: Thread `computed` through `run` / `view`

No change to `run` or `AppDef` — they already pass `app.computed model` to `view`. Verify this is wired.

### Task 5.4: Full-name example

**Files:**
- Create: `examples/src/FullName.elm`, `examples/full-name.html`
- Modify: `examples/vite.config.js`

**View shape:**

```elm
type alias Model =
    { first : Cell String, last : Cell String }


type alias Computed =
    { full : Source String }


app : AppDef (SimpleView Model) Model Computed
app =
    { init =
        build Model
            |> with "first" "" stringCodec
            |> with "last" "" stringCodec
    , computed =
        \model ->
            { full =
                derive
                    (Read.map2 (\f l -> f ++ " " ++ l)
                        (Read.read (toSource model.first))
                        (Read.read (toSource model.last))
                    )
            }
    , view =
        \model c ->
            col
                [ input { label = "First", cell = model.first }
                , input { label = "Last", cell = model.last }
                , watch c.full (\name -> text ("Full name: " ++ name))
                ]
    }
```

**Tests in `ReadTest.elm`:**
- `map` preserves the underlying registry read.
- `map2` combines two sources.
- `derive`-wrapped value reflects both dependencies' current values.

**Commits:** one per task (5.1, 5.2, 5.3 — bundled since trivial, 5.4).

---

## Slice 6 — `temperature` ships

**Objective:** One °C input, two derived displays (°F, K). No new primitives.

### Task 6.1: Temperature example

**Files:**
- Create: `examples/src/Temperature.elm`, `examples/temperature.html`
- Modify: `examples/vite.config.js`

**View shape:**

```elm
type alias Model =
    { celsius : Cell String }  -- String because inputs are strings; parse on read


type alias Computed =
    { fahrenheit : Source String
    , kelvin : Source String
    }


app : AppDef (SimpleView Model) Model Computed
app =
    { init = build Model |> with "celsius" "0" stringCodec
    , computed =
        \model ->
            { fahrenheit =
                derive
                    (Read.map
                        (\s -> formatTemp (toFahrenheit s))
                        (Read.read (toSource model.celsius))
                    )
            , kelvin =
                derive
                    (Read.map
                        (\s -> formatTemp (toKelvin s))
                        (Read.read (toSource model.celsius))
                    )
            }
    , view = ...
    }


toFahrenheit : String -> Maybe Float
toFahrenheit s =
    String.toFloat s |> Maybe.map (\c -> c * 9 / 5 + 32)

-- etc.
```

**Commit:**

```bash
git add examples/temperature.html examples/src/Temperature.elm examples/vite.config.js
git commit -m "Add temperature example"
```

---

## Final verification

After all six slices, run these in order and confirm each:

1. `cd /Users/bcardiff/Projects/bcardiff/elm-rad && npx --yes elm-test` — all suites pass.
2. `cd /Users/bcardiff/Projects/bcardiff/elm-rad && npx --yes elm make --docs /tmp/docs.json` — package docs generate without error.
3. `cd /Users/bcardiff/Projects/bcardiff/elm-rad/examples && npm run build` — multi-entry build succeeds.
4. `cd /Users/bcardiff/Projects/bcardiff/elm-rad/examples && npm run dev` — visit each of the six examples from the landing page at `/`. For each:
   - `/greeting-html.html` — typing updates greeting below input.
   - `/greeting.html` — same, via SimpleView label.
   - `/counter.html` — +/−/reset buttons update displayed count.
   - `/swap.html` — swap button exchanges two input values.
   - `/full-name.html` — typing in first/last updates "Full name" display.
   - `/temperature.html` — typing °C value updates °F and K displays.
5. Verify hot reload: with `npm run dev` running, edit one of the example's Elm files (e.g. change the greeting text). Expected: browser updates without losing current cell values. If state is lost, update `examples/README.md` to note the limitation (risk #4 from the design doc).

Commit any README updates from step 5.

---

## Risks that will be resolved during execution

- **Cell storage representation** (design doc §8, risk 1): resolved in Task 1.3 (Registry) + Task 1.5 (toSource via codec decode). Using JSON-in-registry — accepted as pragmatic for Layer 0+1.
- **Engine dispatch plumbing** (design doc §8, risk 2): resolved in Task 1.7 + Task 1.9 — `Rad.Engine.Msg` carries actions, `ViewEngine.toHtml` takes the registry.
- **CellBuilder plumbing** (design doc §8, risk 3): resolved in Task 1.4.
- **Hot reload state preservation** (design doc §8, risk 4): verified empirically in the final step.
- **`watch` as engine-aware, not truly generic** (new, discovered in Task 1.9): each view engine defines its own `watch` with the same signature. If Slice 6 is done and this feels awkward, consider a single typeclass-style `Watchable view` wrapper in a later layer.

---

**End of plan.**
