# elm-rad Layers 0 & 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver Layers 0 (Foundation) and 1 (Reactivity) of the `elm-rad` DSL defined in [`docs/design-elm-rad.md`](../design-elm-rad.md), sync-only, with six example apps that each exercise a named subset of primitives, and a second view engine (`SimpleView`) in the examples folder that proves the `ViewEngine` abstraction.

**Architecture:** Cells are opaque references holding `{ id, key, codec }`. Values live in a runtime-managed `Registry = Dict Int Json.Value`. Actions are `Registry -> Registry` functions. The user's model record is a *static* record of cell references (not values); values are fetched through `toSource` / `watch`. `run` wraps `Browser.element` with `Cmd.none` / `Sub.none` so later layers can add effects without switching the harness.

**Tech Stack:** Elm 0.19.1 (package), `elm-explorations/test` 2.x, Vite 6, `vite-plugin-elm`, `npx elm` / `npx elm-test` / `npx elm-format`.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per project preference — see memory `feedback_commit_cadence.md`). Each commit should be reviewable on its own.
- Every task maps to **exactly one commit** unless split explicitly. Tasks that touch multiple concepts have been pre-split (e.g., `1.2a`/`1.2b`, `1.9a`/`1.9b`/`1.9c`, `1.12a`/`1.12b`, `3.2a`/`3.2b`). Do not bundle them.
- Before every commit that touches `.elm` files, run `elm-format` on the appropriate sources (see memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes` (from repo root)
  - Examples directory: `npx --yes elm-format src --yes` (from `examples/`)
  - The trailing `--yes` accepts the formatted output without an interactive prompt. If `elm-format` modifies files, stage those modifications with `git add` and include them in the same commit.
- Verification command for the package: `npx --yes elm-test` (from repo root).
- Verification command for examples: `npm run build` (from `examples/`) (smoke) and `npm run dev` (visual).

**Module layout at the end:**
```
src/
  Rad.elm                    ← core: Cell, Source, Codec, Action, CellBuilder, AppDef, AppModel, actions, codecs, watch, run
  Rad/
    View.elm                 ← htmlEngine, HTML primitives, Attribute, bind, onClick
    Read.elm                 ← Read monad (Slice 5)
    Engine.elm               ← engine-author API: Msg, fromAction, ViewEngine, applyMsg
    Internal/
      Registry.elm           ← unexposed Dict Int Json.Value
      Source.elm             ← unexposed Source constructor (shared by Rad and Rad.Read to avoid module cycle)
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

**Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

Stage any formatting modifications alongside the original changes.

**Step 5: Commit.**

```bash
git add elm.json tests/CodecTest.elm
git commit -m "Bootstrap elm-test harness"
```

---

### Task 1.2a: Codec type and primitive codecs (String, Int, Float, Bool)

**Files:**
- Modify: `src/Rad.elm` (replace placeholder with `Codec` + primitive codecs)
- Modify: `tests/CodecTest.elm` (round-trip tests for primitives)

**Step 1: Write failing tests in `tests/CodecTest.elm`:**

```elm
module CodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (boolCodec, floatCodec, intCodec, stringCodec)
import Test exposing (..)


suite : Test
suite =
    describe "Primitive codec round-trips"
        [ test "stringCodec" <|
            \_ -> roundTrip stringCodec "hello" |> Expect.equal (Ok "hello")
        , test "intCodec" <|
            \_ -> roundTrip intCodec 42 |> Expect.equal (Ok 42)
        , test "floatCodec" <|
            \_ -> roundTrip floatCodec 3.14 |> Expect.equal (Ok 3.14)
        , test "boolCodec" <|
            \_ -> roundTrip boolCodec True |> Expect.equal (Ok True)
        ]


roundTrip : { encode : a -> Decode.Value, decode : Decode.Decoder a } -> a -> Result Decode.Error a
roundTrip codec value =
    codec.encode value |> Decode.decodeValue codec.decode
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.stringCodec` etc. not exposed).

**Step 3: Implement in `src/Rad.elm`** (replace the existing placeholder):

```elm
module Rad exposing
    ( Codec
    , boolCodec, floatCodec, intCodec, stringCodec
    )

{-| elm-rad — reactive cell DSL.

@docs Codec
@docs boolCodec, floatCodec, intCodec, stringCodec

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
```

**Step 4: Run `npx --yes elm-test`** — expected: all four tests pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/CodecTest.elm
git commit -m "Add Codec type and primitive codecs"
```

---

### Task 1.2b: Container codecs (List, Maybe)

**Files:**
- Modify: `src/Rad.elm` (add `listCodec`, `maybeCodec`)
- Modify: `tests/CodecTest.elm` (round-trip tests for containers)

**Step 1: Extend `tests/CodecTest.elm`** — update the import and append tests to the `describe` list:

```elm
import Rad exposing (boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec)
```

Rename the `describe` label to `"Codec round-trips"` and append:

```elm
, test "listCodec of strings" <|
    \_ -> roundTrip (listCodec stringCodec) [ "a", "b" ] |> Expect.equal (Ok [ "a", "b" ])
, test "maybeCodec Just" <|
    \_ -> roundTrip (maybeCodec intCodec) (Just 7) |> Expect.equal (Ok (Just 7))
, test "maybeCodec Nothing" <|
    \_ -> roundTrip (maybeCodec intCodec) Nothing |> Expect.equal (Ok Nothing)
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`listCodec`, `maybeCodec` missing).

**Step 3: Implement in `src/Rad.elm`.** Add `listCodec` and `maybeCodec` to the exposing list and the `@docs` block. Append:

```elm
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

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/CodecTest.elm
git commit -m "Add list and maybe codecs"
```

---

### Task 1.3: Internal Registry + Cell type

**Files:**
- Create: `src/Rad/Internal/Registry.elm`
- Modify: `src/Rad.elm` (add `Cell` opaque type)
- No change to `elm.json` — `Rad.Internal.*` stays unexposed.

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

**Step 2: Extend `src/Rad.elm`** — add the opaque `Cell a` type. Do **not** expose the constructor yet; expose only the type.

Update the module declaration to include `Cell`:

```elm
module Rad exposing
    ( Cell
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    )
```

Add `@docs Cell` to the docs block.

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

**Step 3: Run `npx --yes elm-test`** — expected: still passes (`Rad.Internal.Registry` must compile; no test changes).

**Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 5: Commit.**

```bash
git add src/Rad/Internal/Registry.elm src/Rad.elm
git commit -m "Add internal Registry module and opaque Cell type"
```

---

### Task 1.4: CellBuilder + `build` + `with`

**Files:**
- Modify: `src/Rad.elm` (add `CellBuilder`, `build`, `with`, `runBuilder`)
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
        [ test "registry has one entry per cell at their declared initial value" <|
            \_ ->
                let
                    ( _, registry ) =
                        Rad.runBuilder init

                    decoded =
                        ( Registry.get 0 registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)
                        , Registry.get 1 registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
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

This test reaches into `Rad.runBuilder` and `Rad.Internal.Registry`. Both must be importable from tests; `Rad.runBuilder` is exposed by the package, and `Rad.Internal.Registry` is reachable from tests because `tests/` shares the same `source-directories` path.

**Step 2: Run `npx --yes elm-test`** — expected: compile errors (`Rad.build`, `Rad.with`, `Rad.CellBuilder`, `Rad.runBuilder` missing).

**Step 3: Implement in `src/Rad.elm`.** Add imports:

```elm
import Rad.Internal.Registry as Registry exposing (Registry)
```

Add to the module exposing list: `CellBuilder`, `build`, `with`, `runBuilder`. Add `@docs CellBuilder, build, with, runBuilder` entries.

Append to the bottom of the file:

```elm
{-| An applicative builder for constructing a model made of cells.
-}
type CellBuilder a
    = CellBuilder
        { nextId : Int
        , metas : List ( Int, Decode.Value )
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
-}
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder b) =
    ( b.ctor
    , b.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty
    )
```

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/CellBuilderTest.elm
git commit -m "Add CellBuilder with build and with"
```

---

### Task 1.5: `Source` type + `toSource` + `readSource`

**Files:**
- Create: `src/Rad/Internal/Source.elm` (the `Source` constructor lives here so `Rad.Read` can construct sources in Slice 5 without creating a cyclic import with `Rad`)
- Modify: `src/Rad.elm` (re-export `Source` opaquely and `readSource`; define `toSource`)
- Modify: `tests/CellBuilderTest.elm` (add `toSource` assertion)

**Step 1: Write failing test** — append to the `describe` list in `tests/CellBuilderTest.elm`:

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

Update the `Rad exposing` list in the test file to include `readSource` and `toSource`.

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`toSource`, `readSource`, `Source` missing).

**Step 3: Create `src/Rad/Internal/Source.elm`:**

```elm
module Rad.Internal.Source exposing (Source(..), readSource)

import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Source` opaque type with its constructor exposed so that
`Rad` and `Rad.Read` can both construct sources without depending on each
other. User code only sees `Rad.Source`, which is re-exported opaquely.
-}
type Source a
    = Source (Registry -> a)


readSource : Source a -> Registry -> a
readSource (Source f) registry =
    f registry
```

**Step 4: Update `src/Rad.elm`.** Add to the imports (use qualified access so the local type alias `Source` does not collide with `IS.Source`):

```elm
import Rad.Internal.Source as IS
```

Add to the module exposing list: `Source`, `toSource`, `readSource`. Add `@docs Source, toSource, readSource`.

Append:

```elm
{-| Anything readable. Cells, derived values, and later debounced/validated
accessors all convert to `Source`. The constructor is not re-exported from
`Rad`, keeping the type opaque to user code.
-}
type alias Source a =
    IS.Source a


{-| Convert a cell into a readable source.
-}
toSource : Cell a -> Source a
toSource (Cell c) =
    IS.Source
        (\registry ->
            case Registry.get c.id registry of
                Just v ->
                    case Decode.decodeValue c.codec.decode v of
                        Ok a ->
                            a

                        Err _ ->
                            -- Invariant: the registry was written by this cell's
                            -- codec, so decode must succeed.
                            Debug.todo "registry codec mismatch"

                Nothing ->
                    Debug.todo "registry missing cell"
        )


{-| Read a source against a registry. Exposed for tests and for the runtime.
-}
readSource : Source a -> Registry -> a
readSource =
    IS.readSource
```

Note: The local `type alias Source a = IS.Source a` re-exports just the type name. Because `Rad.Internal.Source` is not listed in `elm.json` `exposed-modules`, downstream users of the package can never obtain the constructor — so `Source` is effectively opaque to them while fully transparent within the package.

**Step 5: Run `npx --yes elm-test`** — expected: all pass.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 7: Commit.**

```bash
git add src/Rad/Internal/Source.elm src/Rad.elm tests/CellBuilderTest.elm
git commit -m "Add Source in Rad.Internal.Source with toSource and readSource"
```

---

### Task 1.6: `Action` type + `set` + `applyAction`

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

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`set`, `applyAction` missing).

**Step 3: Implement.** Add to exposing in `src/Rad.elm`: `Action`, `set`, `applyAction`. Add `@docs Action, set, applyAction`. Append:

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

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

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
module Rad.Engine exposing (Msg, ViewEngine, applyMsg, fromAction)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, applyMsg

-}

import Html exposing (Html)
import Rad exposing (Action)
import Rad.Internal.Registry exposing (Registry)


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


{-| Apply a runtime message to the registry. Used by `run`; not part of the
user-facing DSL.
-}
applyMsg : Msg model -> Registry -> Registry
applyMsg (ApplyAction action) registry =
    Rad.applyAction action registry


{-| A view engine transforms the engine's view type into `Html (Msg model)`
for the Elm runtime to render. The engine is given access to the current
registry so it can realize reactive reads.
-}
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
```

**Step 3: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles (both modules documented).

**Step 4: Run `npx --yes elm-test`** — expected: still green.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add elm.json src/Rad/Engine.elm
git commit -m "Add Rad.Engine with Msg, ViewEngine, fromAction, and applyMsg"
```

---

### Task 1.8: `Rad.View` module with registry-aware primitives

**Files:**
- Create: `src/Rad/View.elm`
- Modify: `elm.json` (expose `Rad.View`)

No automated tests — verified via the `greeting-html` example in Task 1.12b. This task commits `col`, `text`, `input`, `bind`, and `htmlEngine` in a **registry-threading** shape from day one (unlike the original split into 1.8 + 1.9). That avoids a later disruptive refactor and keeps every commit end-state compiling and meaningful.

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
import Rad exposing (Cell, readSource, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction)
import Rad.Internal.Registry exposing (Registry)


{-| An attribute applied to an HTML primitive. Encodes reactive intent (bind,
later onClick) that `htmlEngine` wires into real `Html.Attribute`s at render
time.
-}
type Attribute model
    = BindString (Cell String)


{-| The HTML view value produced by the primitives below. Internally a thunk
over the registry so each primitive can resolve reactive reads at render time.
-}
type HtmlView model
    = HtmlView (Registry -> Html.Html (Msg model))


{-| Two-way bind an input's value to a `Cell String`.
-}
bind : Cell String -> Attribute model
bind =
    BindString


{-| A vertical stack.
-}
col : List (Attribute model) -> List (HtmlView model) -> HtmlView model
col _ children =
    HtmlView
        (\r ->
            Html.div [] (List.map (\(HtmlView f) -> f r) children)
        )


{-| An HTML `<input>`. When a `bind` attribute is present, the input's value
is read from the registry and `onInput` dispatches a `set` action.
-}
input : List (Attribute model) -> List (HtmlView model) -> HtmlView model
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
                            [ Html.Attributes.value (readSource (toSource cell) registry) ]

                        Nothing ->
                            []
            in
            Html.input (valueAttr ++ evtAttrs) []
        )


{-| Plain text.
-}
text : String -> HtmlView model
text s =
    HtmlView (\_ -> Html.text s)


{-| The shipped HTML engine.
-}
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = \registry (HtmlView f) -> f registry }
```

**Step 3: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 4: Run `npx --yes elm-test`** — expected: still green.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add elm.json src/Rad/View.elm
git commit -m "Add Rad.View with htmlEngine and reactive primitives"
```

---

### Task 1.9: `watch` primitive

**Files:**
- Modify: `src/Rad/View.elm` (add `watch`)

**Context:** `watch` is engine-aware in Layer 0+1 — each view engine defines its own. See the "Risks resolved during execution" section for the rationale. Because `HtmlView` is already a `Registry -> Html ...` thunk (from Task 1.8), `watch` reduces to reading the source at render time and delegating to the inner view.

**Step 1: Add `watch` to the module exposing list and `@docs` block.** Update:

```elm
module Rad.View exposing
    ( Attribute, HtmlView
    , bind
    , col, input, text, watch
    , htmlEngine
    )
```

Add `watch` under the `col, input, text` docs line.

Also import `Source`:

```elm
import Rad exposing (Cell, Source, readSource, set, toSource)
```

Append to `src/Rad/View.elm`:

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
                    f (readSource source registry)
            in
            g registry
        )
```

**Step 2: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 4: Commit.**

```bash
git add src/Rad/View.elm
git commit -m "Add watch primitive to Rad.View"
```

---

### Task 1.10: `AppDef` + `AppModel` + `run`

**Files:**
- Modify: `src/Rad.elm` (add `AppDef`, `AppModel`, `run`)

**Step 1: Add imports.** At the top of `src/Rad.elm`, add:

```elm
import Browser
import Rad.Engine
```

**Step 2: Extend the module exposing list:** `AppDef`, `AppModel`, `run`. Add `@docs AppDef, AppModel, run`.

**Step 3: Append `AppDef`, `AppModel`, and `run`:**

```elm
{-| A public alias for the runtime's internal model tuple. Used as the model
type of a `Program` so user code does not have to name `Rad.Internal.Registry`.
-}
type alias AppModel model =
    ( model, Registry )


{-| An application definition. Grows additional fields in later layers
(`reactions`, `persist`).
-}
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    }


{-| Run an application. Wraps `Browser.element` so later layers can add
effects without changing the harness.
-}
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program () (AppModel model) (Rad.Engine.Msg model)
run engine app =
    let
        ( model, initialRegistry ) =
            runBuilder app.init
    in
    Browser.element
        { init = \() -> ( ( model, initialRegistry ), Cmd.none )
        , update =
            \msg ( m, registry ) ->
                ( ( m, Rad.Engine.applyMsg msg registry ), Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
```

**Step 4: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 5: Run `npx --yes elm-test`** — expected: still green.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 7: Commit.**

```bash
git add src/Rad.elm
git commit -m "Add AppDef, AppModel, and run"
```

---

### Task 1.11: Replace the single-entry example with a landing page

**Files:**
- Replace: `examples/index.html` (was the single-entry bootstrap, now a landing page)
- Delete: `examples/src/Main.elm`, `examples/src/main.js`

This task intentionally leaves the Vite config unchanged. The multi-entry config is added in Task 1.12b alongside the first real example, so every commit is in a building state.

**Step 1: Replace `examples/index.html`** with:

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

**Step 2: Delete the old single-entry source files:**

```bash
git rm examples/src/Main.elm examples/src/main.js
```

**Step 3: Verify `cd examples && npm run build`** still builds (Vite's default uses `index.html` as the sole entry; the landing page has no JS imports, so it builds as static HTML).

**Step 4: Commit** (no Elm files changed, so no elm-format pass needed).

```bash
git add examples/index.html
git commit -m "Replace single-entry bootstrap with examples landing page"
```

---

### Task 1.12a: Expose `AppModel` in the package docs index

**Files:**
- No code change required — `AppModel` was added in Task 1.10. This task is a docs-index sanity check that keeps the next commit focused solely on the example.

**Step 1: Confirm `AppModel` appears in the exposed API.** Run:

```bash
npx --yes elm make --docs /tmp/docs.json
```

Then inspect `/tmp/docs.json` for an entry describing `AppModel`. If present, skip to Step 2. If missing (because the `@docs` block was not updated when `AppModel` was added in Task 1.10), edit `src/Rad.elm` to add `@docs AppModel` on the appropriate line, re-run `elm make --docs`, re-run `npx --yes elm-test`, run `elm-format`, and commit:

```bash
git add src/Rad.elm
git commit -m "Document AppModel in Rad's exposed API"
```

**Step 2: If no change was needed,** this task is a no-op; proceed directly to Task 1.12b without a commit.

---

### Task 1.12b: Create the `greeting-html` example

**Files:**
- Create: `examples/src/GreetingHtml.elm`
- Create: `examples/greeting-html.html`
- Modify: `examples/vite.config.js` (convert to multi-entry)

**Step 1: Create `examples/src/GreetingHtml.elm`:**

```elm
module GreetingHtml exposing (main)

import Rad exposing (AppDef, AppModel, Cell, build, run, stringCodec, toSource, with)
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


main : Program () (AppModel Model) (Msg Model)
main =
    run htmlEngine app
```

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

**Step 3: Replace `examples/vite.config.js` with a multi-entry config:**

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

**Step 4: Run `cd examples && npm run build`** — expected: succeeds; `dist/index.html`, `dist/greeting-html.html`, and chunked JS are produced.

**Step 5: Run `cd examples && npm run dev`** and visit `http://localhost:5173/greeting-html.html`. Type in the input. Expected: the greeting below updates on every keystroke. Stop the dev server after verifying.

**Step 6: Run `elm-format` on the examples source.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

```bash
git add examples/greeting-html.html examples/src/GreetingHtml.elm examples/vite.config.js
git commit -m "Add greeting-html example on htmlEngine"
```

---

### Slice 1 wrap-up

- All `elm-test` suites pass (`npx --yes elm-test` (from repo root)).
- `cd examples && npm run build` produces a multi-entry build.
- `greeting-html` renders and updates live in the browser.
- Package exposes: `Rad` (core + AppDef + AppModel + run + actions), `Rad.View` (htmlEngine + primitives), `Rad.Engine` (Msg + fromAction + applyMsg + ViewEngine).

---

## Slice 2 — `SimpleView` engine + `greeting` ships

**Objective:** Add an examples-local `SimpleView` engine; port the greeting example to it. `SimpleView` is split across two commits (engine + input/col/text/watch, then `button`) so each commit is a single concept.

### Task 2.1: Create `SimpleView` module (engine, `col`, `input`, `text`, `watch`)

**Files:**
- Create: `examples/src/SimpleView.elm`

**Step 1: Create `examples/src/SimpleView.elm`:**

```elm
module SimpleView exposing
    ( SimpleView
    , col, input, text, watch
    , simpleViewEngine
    )

import Html
import Html.Attributes
import Html.Events
import Rad exposing (Cell, Source, readSource, set, toSource)
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
                    [ Html.Attributes.value (readSource (toSource cell) registry)
                    , Html.Events.onInput (\v -> fromAction (set cell v))
                    ]
                    []
                ]
        )


text : String -> SimpleView model
text s =
    SimpleView (\_ -> Html.text s)


watch : Source a -> (a -> SimpleView model) -> SimpleView model
watch source f =
    SimpleView
        (\registry ->
            let
                (SimpleView g) =
                    f (readSource source registry)
            in
            g registry
        )


simpleViewEngine : ViewEngine (SimpleView model) model
simpleViewEngine =
    { toHtml = \registry (SimpleView f) -> f registry }
```

**Step 2: Run `cd examples && npm run build`** — expected: succeeds (SimpleView.elm compiles, unused for now).

**Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 4: Commit.**

```bash
git add examples/src/SimpleView.elm
git commit -m "Add SimpleView engine with col, input, text, and watch"
```

---

### Task 2.2: Port greeting to SimpleView

**Files:**
- Create: `examples/src/Greeting.elm`
- Create: `examples/greeting.html`
- Modify: `examples/vite.config.js` (add `greeting` input)

**Step 1: Create `examples/src/Greeting.elm`:**

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

**Step 2: Create `examples/greeting.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>greeting (SimpleView)</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/Greeting.elm";
      Elm.Greeting.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

**Step 3: Update `examples/vite.config.js`** to add the new entry. Insert inside `rollupOptions.input`:

```js
greeting: resolve(__dirname, "greeting.html"),
```

**Step 4: Run `cd examples && npm run build`** — expected: both entries build.

**Step 5: Run `cd examples && npm run dev`**, visit `http://localhost:5173/greeting.html`. Expected: identical behavior to `greeting-html`, label says "Name:". Stop the dev server after verifying.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

```bash
git add examples/greeting.html examples/src/Greeting.elm examples/vite.config.js
git commit -m "Add greeting example on SimpleView"
```

---

## Slice 3 — `counter` ships

**Objective:** Add `modify`, `onClick`, HTML `button`, SimpleView `button`. Counter example uses SimpleView.

### Task 3.1: `modify` action

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/ActionTest.elm`

**Step 1: Write failing test.** Append to the `describe` list in `tests/ActionTest.elm`:

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

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.modify` missing).

**Step 3: Implement `modify`.** Add `modify` to the exposing list and `@docs`. Append to `src/Rad.elm`:

```elm
{-| Apply a function to the current value of a cell.
-}
modify : Cell a -> (a -> a) -> Action model
modify ((Cell c) as cell) f =
    Action
        (\registry ->
            let
                current =
                    readSource (toSource cell) registry
            in
            Registry.insert c.id (c.codec.encode (f current)) registry
        )
```

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add modify action"
```

---

### Task 3.2a: `onClick` attribute in `Rad.View`

**Files:**
- Modify: `src/Rad/View.elm`

**Step 1: Add an `OnClick` case to `Attribute`.** Replace:

```elm
type Attribute model
    = BindString (Cell String)
```

with:

```elm
type Attribute model
    = BindString (Cell String)
    | OnClick (Action model)
```

**Step 2: Add the `onClick` constructor** (and add it to the exposing list + `@docs`):

```elm
{-| Dispatch an action when an element is clicked.
-}
onClick : Action model -> Attribute model
onClick =
    OnClick
```

Also import `Action`:

```elm
import Rad exposing (Action, Cell, Source, readSource, set, toSource)
```

**Step 3: Update `input`'s attribute fold to ignore `OnClick`.** Extend the `case a of` to pattern-match exhaustively:

```elm
case a of
    BindString cell ->
        ( Just cell
        , Html.Events.onInput (\v -> fromAction (set cell v)) :: evts
        )

    OnClick _ ->
        ( mc, evts )
```

**Step 4: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 5: Run `npx --yes elm-test`** — expected: still green.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 7: Commit.**

```bash
git add src/Rad/View.elm
git commit -m "Add onClick attribute to Rad.View"
```

---

### Task 3.2b: HTML `button` primitive

**Files:**
- Modify: `src/Rad/View.elm`

**Step 1: Add `button` to the module exposing list and `@docs`.** Append:

```elm
{-| An HTML `<button>`.
-}
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

                                BindString _ ->
                                    []
                        )
                        attrs
            in
            Html.button clickAttrs
                (List.map (\(HtmlView f) -> f registry) children)
        )
```

**Step 2: Run `npx --yes elm make --docs /tmp/docs.json`** — expected: compiles.

**Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 4: Commit.**

```bash
git add src/Rad/View.elm
git commit -m "Add button primitive to Rad.View"
```

---

### Task 3.3: Add `button` to `SimpleView`

**Files:**
- Modify: `examples/src/SimpleView.elm`

**Step 1: Add `button` to the module exposing list:**

```elm
module SimpleView exposing
    ( SimpleView
    , button, col, input, text, watch
    , simpleViewEngine
    )
```

**Step 2: Also import `Action`:**

```elm
import Rad exposing (Action, Cell, Source, readSource, set, toSource)
```

**Step 3: Append `button`:**

```elm
button : { label : String, onClick : Action model } -> SimpleView model
button { label, onClick } =
    SimpleView
        (\_ ->
            Html.button
                [ Html.Events.onClick (fromAction onClick) ]
                [ Html.text label ]
        )
```

**Step 4: Run `cd examples && npm run build`** — expected: compiles.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 6: Commit.**

```bash
git add examples/src/SimpleView.elm
git commit -m "Add button to SimpleView"
```

---

### Task 3.4: Counter example

**Files:**
- Create: `examples/src/Counter.elm`
- Create: `examples/counter.html`
- Modify: `examples/vite.config.js`

**Step 1: Create `examples/src/Counter.elm`:**

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

**Step 2: Create `examples/counter.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>counter</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/Counter.elm";
      Elm.Counter.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

**Step 3: Update `examples/vite.config.js`.** Add inside `rollupOptions.input`:

```js
counter: resolve(__dirname, "counter.html"),
```

**Step 4: Run `cd examples && npm run build`** — expected: succeeds.

**Step 5: Run `cd examples && npm run dev`, visit `/counter.html`.** Click `+`, `−`, `reset`; verify displayed count updates correctly. Stop the dev server.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

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

**Step 1: Write failing test.** Append to `tests/ActionTest.elm`:

1. Change the test module's `Model` to have two cells, or add a second suite. For minimal churn, add a fresh helper model near the top of the file:

```elm
type alias TwoModel =
    { a : Cell String, b : Cell String }


twoInit : Rad.CellBuilder TwoModel
twoInit =
    build TwoModel
        |> with "a" "X" stringCodec
        |> with "b" "Y" stringCodec
```

2. Append to the `describe` list:

```elm
, test "copy reads source then writes to target" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder twoInit

            registry1 =
                Rad.applyAction (Rad.copy (Rad.toSource model.a) model.b) registry0
        in
        Expect.equal "X"
            (Rad.readSource (Rad.toSource model.b) registry1)
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.copy` missing).

**Step 3: Implement `copy`.** Add to the exposing list and `@docs`. Append to `src/Rad.elm`:

```elm
{-| Copy the current value of a source into a cell.

If the source and target have different codecs for the same value type, the
target's codec is used for encoding.
-}
copy : Source a -> Cell a -> Action model
copy source (Cell c) =
    Action
        (\registry ->
            Registry.insert c.id (c.codec.encode (readSource source registry)) registry
        )
```

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add copy action"
```

---

### Task 4.2: `batch` action

**Files:**
- Modify: `src/Rad.elm`
- Modify: `tests/ActionTest.elm`

**Step 1: Write failing tests.** Append to the `describe` list in `tests/ActionTest.elm`:

```elm
, test "batch with empty list is a no-op" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder init

            registry1 =
                Rad.applyAction (Rad.batch []) registry0
        in
        Expect.equal "alice"
            (Rad.readSource (Rad.toSource model.name) registry1)
, test "batch applies actions in list order" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder init

            registry1 =
                Rad.applyAction
                    (Rad.batch
                        [ Rad.set model.name "bob"
                        , Rad.modify model.name (\s -> s ++ "!")
                        ]
                    )
                    registry0
        in
        Expect.equal "bob!"
            (Rad.readSource (Rad.toSource model.name) registry1)
, test "nested batch preserves execution order" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder init

            registry1 =
                Rad.applyAction
                    (Rad.batch
                        [ Rad.batch
                            [ Rad.set model.name "bob"
                            , Rad.modify model.name (\s -> s ++ "1")
                            ]
                        , Rad.modify model.name (\s -> s ++ "2")
                        ]
                    )
                    registry0
        in
        Expect.equal "bob12"
            (Rad.readSource (Rad.toSource model.name) registry1)
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.batch` missing).

**Step 3: Implement `batch`.** Add to the exposing list and `@docs`. Append:

```elm
{-| Combine a sequence of actions, applied in list order.
-}
batch : List (Action model) -> Action model
batch actions =
    Action
        (\registry ->
            List.foldl (\(Action f) r -> f r) registry actions
        )
```

Flattening is automatic because `Action` is just function composition.

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/ActionTest.elm
git commit -m "Add batch action"
```

---

### Task 4.3: Swap example

**Files:**
- Create: `examples/src/Swap.elm`
- Create: `examples/swap.html`
- Modify: `examples/vite.config.js`

**Step 1: Create `examples/src/Swap.elm`:**

```elm
module Swap exposing (main)

import Rad exposing (AppDef, AppModel, Cell, batch, build, copy, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine)


type alias Model =
    { a : Cell String
    , b : Cell String
    , tmp : Cell String
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "a" "one" stringCodec
            |> with "b" "two" stringCodec
            |> with "tmp" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
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
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

**Step 2: Create `examples/swap.html`** (same template as earlier examples; module `Swap`, importing `./src/Swap.elm`).

**Step 3: Update `examples/vite.config.js`.** Add:

```js
swap: resolve(__dirname, "swap.html"),
```

**Step 4: Run `cd examples && npm run build`** — expected: succeeds.

**Step 5: Run `cd examples && npm run dev`, visit `/swap.html`.** Type values into A and B, click "swap"; expected: the two fields exchange values. Stop the dev server.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

```bash
git add examples/swap.html examples/src/Swap.elm examples/vite.config.js
git commit -m "Add swap example"
```

---

## Slice 5 — `full-name` ships *(Layer 1 begins)*

**Objective:** Add `Rad.Read` module with `Read`, `read`, `Read.map`, `Read.map2`, and a top-level `derive` in `Rad`. Full-name example demonstrates derived values.

### Task 5.1: `Rad.Read` module

**Files:**
- Create: `src/Rad/Read.elm`
- Create: `tests/ReadTest.elm`
- Modify: `elm.json` (expose `Rad.Read`)

**Step 1: Edit `elm.json` exposed-modules:**

```json
"exposed-modules": [
    "Rad",
    "Rad.Engine",
    "Rad.Read",
    "Rad.View"
]
```

**Step 2: Write failing tests in `tests/ReadTest.elm`:**

```elm
module ReadTest exposing (suite)

import Expect
import Rad exposing (Cell, build, stringCodec, with)
import Rad.Read as Read
import Test exposing (..)


type alias Model =
    { first : Cell String, last : Cell String }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "first" "ada" stringCodec
        |> with "last" "lovelace" stringCodec


suite : Test
suite =
    describe "Rad.Read"
        [ test "read returns the current value of a source" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "ada"
                    (Read.run (Read.read (Rad.toSource model.first)) registry)
        , test "map transforms the read value" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "ADA"
                    (Read.run
                        (Read.map String.toUpper (Read.read (Rad.toSource model.first)))
                        registry
                    )
        , test "map2 combines two sources" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    combined =
                        Read.map2 (\f l -> f ++ " " ++ l)
                            (Read.read (Rad.toSource model.first))
                            (Read.read (Rad.toSource model.last))
                in
                Expect.equal "ada lovelace"
                    (Read.run combined registry)
        ]
```

Note: the tests use `Read.run` to evaluate a `Read` against a registry. This is an exposed helper for testability and for the `derive` wrapper in Task 5.2.

**Step 3: Run `npx --yes elm-test`** — expected: compile error (module `Rad.Read` missing).

**Step 4: Create `src/Rad/Read.elm`:**

Note: this module imports `Source`/`readSource` from `Rad.Internal.Source` (not from `Rad`) so that `Rad` can import `Rad.Read` in Task 5.2 without creating a cyclic import.

```elm
module Rad.Read exposing (Read, map, map2, read, run)

{-| A read-only view into the cell registry. Values in `Read` are evaluated
at render time by the runtime and by `Rad.derive`.

@docs Read, read, map, map2, run

-}

import Rad.Internal.Registry exposing (Registry)
import Rad.Internal.Source exposing (Source, readSource)


{-| A deferred read against a registry.
-}
type Read a
    = Read (Registry -> a)


{-| Lift a source into a `Read`.
-}
read : Source a -> Read a
read source =
    Read (readSource source)


{-| Map a pure function over a `Read`.
-}
map : (a -> b) -> Read a -> Read b
map f (Read g) =
    Read (\r -> f (g r))


{-| Combine two `Read`s with a pure function.
-}
map2 : (a -> b -> c) -> Read a -> Read b -> Read c
map2 f (Read g) (Read h) =
    Read (\r -> f (g r) (h r))


{-| Evaluate a `Read` against a registry. Used by the runtime, tests, and
`Rad.derive`.
-}
run : Read a -> Registry -> a
run (Read f) registry =
    f registry
```

**Step 5: Run `npx --yes elm-test`** — expected: all pass.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 7: Commit.**

```bash
git add elm.json src/Rad/Read.elm tests/ReadTest.elm
git commit -m "Add Rad.Read with Read, read, map, map2, run"
```

---

### Task 5.2: `derive` in `Rad`

**Files:**
- Modify: `src/Rad.elm` (add `derive`)
- Modify: `tests/ReadTest.elm` (add derive test)

**Step 1: Append failing test to `tests/ReadTest.elm`'s `describe`:**

```elm
, test "derive produces a Source that reflects its Read's current value" <|
    \_ ->
        let
            ( model, registry0 ) =
                Rad.runBuilder init

            fullNameSource =
                Rad.derive
                    (Read.map2 (\f l -> f ++ " " ++ l)
                        (Read.read (Rad.toSource model.first))
                        (Read.read (Rad.toSource model.last))
                    )

            registry1 =
                Rad.applyAction (Rad.set model.first "grace") registry0
        in
        Expect.equal
            ( "ada lovelace", "grace lovelace" )
            ( Rad.readSource fullNameSource registry0
            , Rad.readSource fullNameSource registry1
            )
```

**Step 2: Run `npx --yes elm-test`** — expected: compile error (`Rad.derive` missing).

**Step 3: Implement `derive`.** Add `derive` to the exposing list and `@docs`. Import `Rad.Read` in `src/Rad.elm`:

```elm
import Rad.Read
```

Append (using the `IS` alias introduced in Task 1.5 so we can construct an `IS.Source` directly — the local `Source` is just a type alias):

```elm
{-| Turn a `Read` into a `Source`. The resulting source recomputes its value
from the registry on every read.
-}
derive : Rad.Read.Read a -> Source a
derive readValue =
    IS.Source (\registry -> Rad.Read.run readValue registry)
```

**Step 4: Run `npx --yes elm-test`** — expected: all pass.

**Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

**Step 6: Commit.**

```bash
git add src/Rad.elm tests/ReadTest.elm
git commit -m "Add derive: turn a Read into a Source"
```

---

### Task 5.3: Full-name example

**Files:**
- Create: `examples/src/FullName.elm`
- Create: `examples/full-name.html`
- Modify: `examples/vite.config.js`

**Step 1: Create `examples/src/FullName.elm`:**

```elm
module FullName exposing (main)

import Rad exposing (AppDef, AppModel, Cell, Source, build, derive, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import Rad.Read as Read
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { first : Cell String
    , last : Cell String
    }


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


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

**Step 2: Create `examples/full-name.html`** (template as before; module `FullName`, importing `./src/FullName.elm`).

**Step 3: Update `examples/vite.config.js`.** Add:

```js
"full-name": resolve(__dirname, "full-name.html"),
```

**Step 4: Run `cd examples && npm run build`** — expected: succeeds.

**Step 5: Run `cd examples && npm run dev`, visit `/full-name.html`.** Type in either field; expected: the "Full name:" line updates live to show the concatenation. Stop the dev server.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

```bash
git add examples/full-name.html examples/src/FullName.elm examples/vite.config.js
git commit -m "Add full-name example"
```

---

## Slice 6 — `temperature` ships

**Objective:** One °C input, two derived displays (°F, K). No new primitives.

### Task 6.1: Temperature example

**Files:**
- Create: `examples/src/Temperature.elm`
- Create: `examples/temperature.html`
- Modify: `examples/vite.config.js`

**Step 1: Create `examples/src/Temperature.elm`:**

```elm
module Temperature exposing (main)

import Rad exposing (AppDef, AppModel, Cell, Source, build, derive, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import Rad.Read as Read
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { celsius : Cell String }


type alias Computed =
    { fahrenheit : Source String
    , kelvin : Source String
    }


app : AppDef (SimpleView Model) Model Computed
app =
    { init =
        build Model |> with "celsius" "0" stringCodec
    , computed =
        \model ->
            { fahrenheit =
                derive
                    (Read.map (formatTemp << toFahrenheit)
                        (Read.read (toSource model.celsius))
                    )
            , kelvin =
                derive
                    (Read.map (formatTemp << toKelvin)
                        (Read.read (toSource model.celsius))
                    )
            }
    , view =
        \model c ->
            col
                [ input { label = "°C", cell = model.celsius }
                , watch c.fahrenheit (\f -> text ("°F: " ++ f))
                , watch c.kelvin (\k -> text ("K: " ++ k))
                ]
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app


toFahrenheit : String -> Maybe Float
toFahrenheit s =
    String.toFloat s |> Maybe.map (\c -> c * 9 / 5 + 32)


toKelvin : String -> Maybe Float
toKelvin s =
    String.toFloat s |> Maybe.map (\c -> c + 273.15)


formatTemp : Maybe Float -> String
formatTemp m =
    case m of
        Just f ->
            String.fromFloat f

        Nothing ->
            "—"
```

**Step 2: Create `examples/temperature.html`** (template as before; module `Temperature`, importing `./src/Temperature.elm`).

**Step 3: Update `examples/vite.config.js`.** Add:

```js
temperature: resolve(__dirname, "temperature.html"),
```

**Step 4: Run `cd examples && npm run build`** — expected: succeeds.

**Step 5: Run `cd examples && npm run dev`, visit `/temperature.html`.** Type `100` into the °C field; expected: °F shows `212` and K shows `373.15`. Type a non-numeric value; expected: both derived displays show `—`. Stop the dev server.

**Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src --yes
```

**Step 7: Commit.**

```bash
git add examples/temperature.html examples/src/Temperature.elm examples/vite.config.js
git commit -m "Add temperature example"
```

---

## Final verification

After all six slices, run these in order and confirm each:

1. `npx --yes elm-test` (from repo root) — all suites pass.
2. `npx --yes elm make --docs /tmp/docs.json` (from repo root) — package docs generate without error.
3. `npx --yes elm-format --validate src tests` (from repo root) — no formatting drift.
4. `npx --yes elm-format --validate src` (from `examples/`) — no formatting drift.
5. `npm run build` (from `examples/`) — multi-entry build succeeds.
6. `npm run dev` (from `examples/`) — visit each of the six examples from the landing page at `/`. For each:
   - `/greeting-html.html` — typing updates greeting below input.
   - `/greeting.html` — same, via SimpleView label.
   - `/counter.html` — +/−/reset buttons update displayed count.
   - `/swap.html` — swap button exchanges two input values.
   - `/full-name.html` — typing in first/last updates "Full name" display.
   - `/temperature.html` — typing °C value updates °F and K displays.
7. Verify hot reload: with `npm run dev` running, edit one of the example's Elm files (e.g. change the greeting text). Expected: browser updates without losing current cell values. If state is lost, update `examples/README.md` to note the limitation (risk #4 from the design doc). Run `elm-format` and commit any README update.

---

## Risks that will be resolved during execution

- **Cell storage representation** (design doc §8, risk 1): resolved in Task 1.3 (Registry) + Task 1.5 (toSource via codec decode). Using JSON-in-registry — accepted as pragmatic for Layer 0+1.
- **Engine dispatch plumbing** (design doc §8, risk 2): resolved in Task 1.7 — `Rad.Engine.Msg` carries actions; `ViewEngine.toHtml` takes the registry from the start.
- **CellBuilder plumbing** (design doc §8, risk 3): resolved in Task 1.4.
- **Hot reload state preservation** (design doc §8, risk 4): verified empirically in step 7 of Final verification.
- **`watch` as engine-aware, not truly generic** (discovered when designing `Rad.View`): each view engine defines its own `watch` with the same signature. If Slice 6 is done and this feels awkward, consider a single typeclass-style `Watchable view` wrapper in a later layer.

---

**End of plan.**
