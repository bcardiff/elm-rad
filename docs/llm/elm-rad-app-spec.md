# elm-rad — Application Spec for LLMs

This document is the canonical reference for an LLM tasked with producing well-formed `elm-rad` applications. Read sections 1–12 to understand the framework, then consult the view engine section (13) for the primitives available in your target environment.

The framework portion is fixed. The view-engine portion is parameterized — see section 13.

---

## 1. Overview

`elm-rad` is an Elm 0.19 package that lets you build reactive applications by declaring **cells**, **derivations**, **actions**, and **reactions**. You do not write `Msg` types, `update` functions, or `subscriptions`. The runtime interprets your declarations into a standard `Browser.element` program.

**Mental model:**
- **Cells** hold mutable state. Each cell has a codec (encode/decode) and a persistence key.
- **Sources** are read-only views into one or more cells.
- **Reactions** declare "when this source changes, run this effect; write the result here."
- **Actions** are atomic registry transformations dispatched in response to UI events.

The runtime maintains a **Registry** (`Dict Int Json.Value`). Every cell is a slot in the registry. Cells are typed; the registry is type-erased. Codecs bridge the two.

---

## 2. Type primer

These are the load-bearing types. All except the explicitly opaque ones are aliases.

```elm
type alias Codec a =
    { encode : a -> Json.Encode.Value
    , decode : Json.Decode.Decoder a
    }

type Cell a                 -- opaque
type DebouncedCell a        -- opaque; allocates 3 registry slots
type ValidatedCell err a    -- opaque; allocates 3 registry slots
type Source a               -- opaque; cell-derived read view

type Action model           -- opaque (sum type internally)
type Reaction model         -- opaque (sum-type internally)
type Request err r          -- opaque (effect-library produced)

type CellBuilder ctor       -- opaque, applicative-style builder
```

Common helper types:

```elm
type Remote err r
    = Idle
    | Loading
    | Failed err
    | Done r

type Validation err a
    = Dormant
    | Checking
    | Valid a
    | Invalid (List err)
```

The `Reaction model` and `Action model` types carry a phantom `model` type variable — it does not appear in any field. At use sites it unifies with the outer app's model type.

---

## 3. Building a model — the `CellBuilder` pipeline

A model is built from a record-constructor function plus a chain of `with`-style calls. Each call allocates registry slots and stores a `Cell` reference in the resulting record.

```elm
build : ctor -> CellBuilder ctor

with :
    String                  -- persistence key
    -> a                    -- initial value
    -> Codec a
    -> CellBuilder (Cell a -> rest)
    -> CellBuilder rest

withDebounced :
    String                  -- persistence key
    -> Float                -- debounce delay (ms)
    -> a                    -- initial value
    -> Codec a
    -> CellBuilder (DebouncedCell a -> rest)
    -> CellBuilder rest

withValidated :
    String                  -- persistence key
    -> a                    -- initial value
    -> Codec a
    -> Codec err
    -> Validator err a
    -> CellBuilder (ValidatedCell err a -> rest)
    -> CellBuilder rest

runBuilder : CellBuilder model -> ( model, Registry )
```

Bundled codecs: `boolCodec`, `intCodec`, `floatCodec`, `stringCodec`, `listCodec`, `maybeCodec`, `remoteCodec`.

**Example — basic model:**

```elm
type alias Model =
    { name : Cell String
    , page : Cell Int
    , draft : Cell (Maybe String)
    }

init : CellBuilder Model
init =
    build Model
        |> with "name" "" stringCodec
        |> with "page" 1 intCodec
        |> with "draft" Nothing (maybeCodec stringCodec)
```

**Field order in the record must match the call order in the pipeline.** The builder is applicative: each `with` consumes one constructor argument from the left.

---

## 4. Reading state

### Sources

A `Source a` reads a value out of the registry. Convert a `Cell a` to a `Source a`:

```elm
toSource : Cell a -> Source a
readSource : Source a -> Registry -> a
```

Combine sources via the `Read` monad:

```elm
derive : Read a -> Source a   -- materialize a Read as a Source
```

### The `Read` monad (`Rad.Read`)

```elm
type Read a                                       -- opaque, applicative
read : Source a -> Read a
map  : (a -> b) -> Read a -> Read b
map2 : (a -> b -> c) -> Read a -> Read b -> Read c
run  : Read a -> Registry -> a
```

**Example — derived source:**

```elm
fullName : Source String
fullName =
    derive
        (Read.map2
            (\first last -> first ++ " " ++ last)
            (Read.read (toSource model.first))
            (Read.read (toSource model.last))
        )
```

### Computed values (per-render derivations)

`AppDef.computed : model -> computed` produces a record of derived values rebuilt on every render. The `view` and `reactions` callbacks receive `computed` as their second argument.

```elm
computed = \model ->
    { isEmpty = ...
    , itemCount = ...
    }
```

Use `computed` for cheap pure derivations referenced multiple times. Use `derive`/`Source` when you need reactive participation (e.g., to drive a `watch`).

### Watching a source from a view

`watch` is a view-engine primitive (defined by your view engine — see §13). Its conventional signature is:

```elm
watch : Source a -> (a -> view) -> view
```

---

## 5. Synchronous actions

An `Action model` is an opaque atomic registry transformation. Dispatched from UI events (typically `onClick`).

```elm
set    : Cell a -> a -> Action model
modify : Cell a -> (a -> a) -> Action model
copy   : Cell a -> Cell a -> Action model      -- copy value from source cell to target
batch  : List (Action model) -> Action model   -- compose atomically
noAction : Action model                        -- identity (useful as a default)

applyAction : Action model -> Registry -> Registry   -- mostly for tests
```

Validation lifecycle (Layer 4):

```elm
validate         : ValidatedCell err a -> Action model    -- activate (re-runs validator)
resetValidation  : ValidatedCell err a -> Action model    -- back to Dormant
```

Debounced-cell commit triggers (Layer 3):

```elm
commit : DebouncedCell a -> Action model      -- promote raw -> settled now
revert : DebouncedCell a -> Action model      -- discard raw, snap to settled
```

Persistence (Layer 7):

```elm
persistNow : Action model       -- request an immediate persist save
```

---

## 6. Asynchronous effects — Reactions

A `Reaction model` declares: when this source's value changes, run a `Request err r` and write the result into a target `Cell (Remote err r)`.

```elm
on :
    Source a
    -> (a -> Request err r)
    -> Cell (Remote err r)
    -> Reaction model

noRequest : Request err a            -- "produce no effect this trigger"
```

Reactions self-handle:
- **Latest-wins**: stale results from earlier triggers are dropped.
- **Loading state**: the target cell receives `Loading` while the request is in flight.
- **Crash recovery** (when `persist = Just`): on restore, reactions whose targets are `Loading` re-fire automatically.

**The `Remote err r` lifecycle** (target cells must be `Cell (Remote err r)`):

```elm
type Remote err r
    = Idle              -- never fired
    | Loading           -- request in flight
    | Failed err        -- request returned error
    | Done r            -- request returned value

remoteCodec : Codec err -> Codec r -> Codec (Remote err r)
```

### `Rad.Http`

The first-party HTTP effect library (other effect libraries can be added):

```elm
type Handler                                       -- opaque
prodHandler : Handler

type RequestError = Timeout | NetworkError | BadStatus Int | BadBody String | UnknownError String
requestErrorCodec : Codec RequestError

httpGet  : Handler -> String -> Decoder a -> Request RequestError a
httpPost : Handler -> String -> Encode.Value -> Decoder a -> Request RequestError a
```

**Example — search reaction:**

```elm
reactions = \model _ ->
    [ on
        (toSource model.query)
        (\q ->
            if String.trim q == "" then
                noRequest

            else
                Http.httpGet prodHandler ("/api/search?q=" ++ q) resultsDecoder
        )
        model.results
    ]
```

### Request combinators

```elm
mapRequestError : (e1 -> e2) -> Request e1 r -> Request e2 r
andThenRequest  : (a -> Result err b) -> Request err a -> Request err b
```

---

## 7. Debounced cells

A `DebouncedCell a` is a cell with TWO observable values (`raw` and `settled`) and a timer-seq. Useful for search-as-you-type and similar.

```elm
withDebounced "search" 500 "" stringCodec
```

```elm
raw     : DebouncedCell a -> Source a   -- updates on every change
settled : DebouncedCell a -> Source a   -- updates on commit / timer / revert
synced  : DebouncedCell a -> Source Bool -- true when raw == settled
```

**Use `settled` to gate effects** — reactions that hit the network watch `settled`, not `raw`, to avoid firing on every keystroke.

Commit triggers (passed to view engines that support them):

```elm
type CommitTrigger
    = OnEnter
    | OnBlur
    | OnTimeout
    | OnChange
```

---

## 8. Validated cells

A `ValidatedCell err a` wraps a `Cell a` (the input) and a reactive `Validation err a` state.

```elm
withValidated "email" "" stringCodec stringCodec (sync emailValidator)
```

Helpers:

```elm
input      : ValidatedCell err a -> Cell a
validation : ValidatedCell err a -> Source (Validation err a)

validationReactions : ValidatedCell err a -> List (Reaction model)
-- Returns one reaction per ValidatedCell. Concatenate into your app's reactions list.

validate         : ValidatedCell err a -> Action model
resetValidation  : ValidatedCell err a -> Action model
```

### Building validators

```elm
type Validator err a   -- opaque

sync    : (a -> Result (List err) a) -> Validator err a
async   : (a -> Request (List err) a) -> Validator err a
compose : List (Validator err a) -> Validator err a   -- short-circuits on first failure
```

**Example — required + format:**

```elm
emailValidator : Validator String String
emailValidator =
    compose
        [ sync
            (\s ->
                if String.trim s == "" then
                    Err [ "Email is required" ]

                else
                    Ok s
            )
        , sync
            (\s ->
                if String.contains "@" s then
                    Ok s

                else
                    Err [ "Invalid email" ]
            )
        ]
```

### Validation state

```elm
type Validation err a
    = Dormant            -- not yet activated (the default; no errors shown)
    | Checking           -- async validator in flight
    | Valid a            -- ok; carries the typed clean value
    | Invalid (List err)
```

Validation activates on `validate` action; from then on, it re-runs on every input change.

`validationCodec : Codec err -> Codec a -> Codec (Validation err a)` — handy when needing to manually inspect/build validation values.

---

## 9. Components

A `ComponentDef model view cells computed` packages a reusable cells record + view + reactions.

```elm
type ComponentDef model view cells computed   -- opaque

defineComponent :
    { init : CellBuilder cells
    , computed : cells -> computed
    , view : cells -> computed -> view
    , reactions : cells -> computed -> List (Reaction model)
    }
    -> ComponentDef model view cells computed

withInstance :
    String                                         -- namespace prefix
    -> ComponentDef model view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest

embed :
    ComponentDef model view cells computed
    -> cells
    -> view

include :
    ComponentDef model view cells computed
    -> cells
    -> List (Reaction model)
```

**Persistence key namespacing:** `withInstance "primary" def` runs the component's `init` with prefix `"primary."`. A `with "selected"` inside the component produces a cell whose `.key` is `"primary.selected"`. Same prefix applies to `withDebounced` and `withValidated` keys.

**Recommended pattern:** bind parameterized `ComponentDef` values at module level to avoid reconstruction at each use site (`withInstance`, `embed`, `include` each take the def).

**Cell key accessor:**

```elm
cellKey            : Cell a -> String              -- namespaced persistence key
cellId             : Cell a -> Int                 -- runtime id (low-level)
cellCodec          : Cell a -> Codec a             -- for low-level integration
cellEncodedInitial : Cell a -> Json.Encode.Value
```

---

## 10. Forms (`Rad.Form`)

Layer 5 — orthogonal transaction boundary over an existing cells record. Import as:

```elm
import Rad.Form as Form exposing (Form, Status(..))
```

### State allocation + value construction

```elm
type Form fields     -- opaque
type Member          -- opaque
type alias State = ...

withState : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest
stateCodec : Codec State

over : Cell State -> fields -> List Member -> Form fields
field          : Cell a              -> Member
validatedField : ValidatedCell err a -> Member
```

The `Form fields` value is built per render (pure record construction):

```elm
theForm : Model -> Form ProfileFields
theForm m =
    Form.over m.formState
        { name = m.name, email = m.email, bio = m.bio }
        [ Form.validatedField m.name
        , Form.validatedField m.email
        , Form.field m.bio
        ]
```

### Behaviors

```elm
dirty     : Form fields -> Source Bool
submit    : Form fields -> Action model        -- bumps submitSeq; dispatches validate to all members
reset     : Form fields -> Action model        -- restores all members to pristine; clears validations
reactions : Form fields -> List (Reaction model)  -- per-member validation reactions
```

### Status

```elm
type Status = Pristine | Editable | HasErrors | Validating | Submitting

status        : Form fields -> Source Status
canSubmit     : Form fields -> Source Bool
submitPending : Form fields -> Source Bool
invalid       : Form fields -> Source Bool
checking      : Form fields -> Source Bool
```

`Form.invalid` always wins over `Submitting` in `Form.status` — late-arriving Invalid surfaces as `HasErrors`.

### Validated groups + submit gating

`ValidatedGroup fields clean` bundles N validated-field getters; gates submission on all-Valid.

```elm
type ValidatedGroup fields clean    -- opaque

validators1 : (fields -> ValidatedCell err a) -> ValidatedGroup fields a
validators2 : (fields -> ValidatedCell err1 a) -> (fields -> ValidatedCell err2 b) -> ValidatedGroup fields ( a, b )
validators3 : ... -> ValidatedGroup fields ( a, b, c )
-- validators4..8 take a PACKER function as the first arg (Elm tuples max at arity 3):
validators4 : (a -> b -> c -> d -> clean) -> (fields -> ValidatedCell err1 a) -> ... -> ValidatedGroup fields clean
-- validators5/6/7/8 follow the same pattern.

mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
readGroup    : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
```

Gating reactions:

```elm
onSubmit :
    Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Request err r)
    -> Cell (Remote err r)
    -> Reaction model

onValid :
    Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Action model)
    -> Reaction model
```

`onSubmit` fires the `Request` when `submitSeq > lastResolvedSubmitSeq` AND every validator is `Valid`. On `Done` it advances the form's snapshot and `lastResolvedSubmitSeq`. `onValid` is the Action-running variant for non-network flows.

Compose into your app:

```elm
reactions = \model _ ->
    Form.reactions (theForm model)
        ++ [ Form.onSubmit (theForm model)
                (Form.validators2 .name .email)
                (\( name, email ) -> postProfile name email)
                model.submitResult
           ]
```

---

## 11. Persistence

Layer 7 — opt-in localStorage persistence.

```elm
type alias PersistConfig msg =
    { key : String                            -- localStorage key
    , version : Int                           -- schema version (always 1 unless migrating; no migrations in MVP)
    , save : ( String, String ) -> Cmd msg    -- user-supplied outgoing port
    }
```

Wire into `AppDef.persist`:

```elm
port persistSave : ( String, String ) -> Cmd msg

app : AppDef ...
app =
    { ...
    , persist = Just { key = "myapp", version = 1, save = persistSave }
    }
```

**JS glue (one-time):**

```javascript
const stored = localStorage.getItem("myapp");
const app = Elm.Main.init({ node, flags: stored });
app.ports.persistSave.subscribe(([key, json]) =>
    localStorage.setItem(key, json)
);
```

**Behavior:**
- Save: any registry mutation schedules a debounced save (500ms). `Rad.persistNow` skips the debounce.
- Restore: at boot, flags (a `Json.Decode.Value`) are interpreted as either `null` (no restore), a string (parsed as JSON), or an object envelope. Strict policy: any decode failure or version mismatch discards the entire restore and falls back to init defaults.
- Missing-cell rule: a cell absent from the stored blob is decoded as `null` via its value codec. Null-tolerant codecs accept (graceful schema drift); strict codecs reject (force re-init).
- Crash recovery: reactions whose targets are `Loading` / `Checking` re-fire after restore.

`persist = Nothing` → flags ignored, no save ever fires. Use this for non-persistent apps.

---

## 12. `AppDef` + `run`

```elm
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
    , persist : Maybe (PersistConfig (Rad.Engine.Msg model))
    }

type alias AppModel model =
    -- Opaque record: { model, registry, reactions, dirtyCounter }
    ...

run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program Json.Decode.Value (AppModel model) (Rad.Engine.Msg model)
```

The `Rad.Engine.ViewEngine view model` interface is supplied by your view engine (see §13). For non-persistent apps, set `persist = Nothing` and ignore the `flags` argument in your JS init.

**`main` signature:**

```elm
main : Program Json.Decode.Value (AppModel Model) (Rad.Engine.Msg Model)
main =
    run myViewEngine app
```

---

## 13. View engine

`elm-rad` is engine-agnostic. A view engine provides:
- A view type (`view` in the type parameters above).
- A `Rad.Engine.ViewEngine view model` value.
- Primitive constructors for that view type (text, layout, inputs, buttons, etc.).

The package ships one HTML-based view engine in `Rad.View` (used by the bundled examples), but you can write your own (svg, terminal, server-rendered, etc.) by implementing `Rad.Engine.ViewEngine`.

The skill that generated this doc has a slot for the chosen view engine. **Replace the marker below with your view-engine's primitives** (or run `elm-rad-docgen --view-engine path/to/spec.md` to have the skill fill it for you).

<!-- VIEW_ENGINE_SLOT -->

> **No view engine attached.** Provide a view-engine spec to the doc generator, or insert the primitives you have available here. The spec should include: the `view` type, the `ViewEngine view model` value, view constructors (text, layout, inputs, buttons), how to watch reactive sources, how to bind plain and debounced cells, and a small idiomatic snippet.

<!-- /VIEW_ENGINE_SLOT -->

---

## 14. Complete app skeleton

```elm
module Main exposing (main)

import Json.Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , build
        , intCodec
        , modify
        , persistNow
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http exposing (RequestError, requestErrorCodec)
-- View engine imports go here (see §13).


-- 1. Model — every field is a `Cell ...` or component-instance record.

type alias Model =
    { name : Cell String
    , page : Cell Int
    , submitResult : Cell (Remote RequestError ())
    }


-- 2. App definition.

app : AppDef YourView Model {}
app =
    { init =
        build Model
            |> with "name" "" stringCodec
            |> with "page" 1 intCodec
            |> with "submit-result" Idle (remoteCodec requestErrorCodec yourUnitCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            -- Use the view engine's combinators. See §13.
            yourViewEngineCombinator
                [ -- text, watch, button, input, ...
                ]
    , reactions = \_ _ -> []
    , persist = Nothing
    }


-- 3. Main — `Program Json.Decode.Value (AppModel Model) (Msg Model)` is mandatory.

main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run yourViewEngine app
```

---

## 15. Anti-patterns

1. **Do not write `Msg` / `update` / `subscriptions`.** The runtime owns these. If you find yourself needing one, you're fighting the framework.

2. **Do not store derived values in cells.** Use `derive` + `Source` or `computed` for anything that's a function of other cells.

3. **Do not bypass codecs.** Every cell value flows through its codec. Custom serialization belongs in a `Codec a` value, not in ad-hoc encode/decode at the call site.

4. **Do not put effects in actions.** Actions are pure registry transformations. All effects go through `Reaction model` + `Request err r`.

5. **Do not reach into `Rad.Internal.*`.** These modules are private to the package. Use the public `Rad`, `Rad.Form`, etc.

6. **Do not forget `validationReactions` (or `Form.reactions`).** Validated cells DO NOT validate themselves; their reactions must be in `AppDef.reactions`.

7. **Do not gate `Rad.on` on `raw` for network effects.** Watch `settled` (from `DebouncedCell`) to avoid firing on every keystroke.

8. **Do not use a strict `intCodec` for a cell you add post-deploy** if you have `persist = Just` — strict restore will discard the entire saved state. Use `maybeCodec intCodec` (or similar null-tolerant codec) for fields that may not exist in older saved blobs.

9. **Do not destructure `AppModel`.** It is a record (not a tuple) and its fields are private. The only legitimate references are in your `main`'s `Program ... (AppModel Model) ...` type.

10. **Do not put state in `computed`.** `computed` is recomputed per render. It must be a pure function of `model`. Anything stateful belongs in a `Cell`.

11. **Do not enable persistence on apps that hold secrets.** Persistence (`persist = Just ...`) writes every cell's current value to `localStorage`. Passwords, access tokens, and similar sensitive values WILL be written in plaintext. Either keep `persist = Nothing` for forms that touch secrets, or split the app so the secret-holding part has no `PersistConfig`.

---

## 16. Type-signature reference (alphabetical)

```elm
-- Rad
applyAction       : Action model -> Registry -> Registry
andThenRequest    : (a -> Result err b) -> Request err a -> Request err b
async             : (a -> Request (List err) a) -> Validator err a
batch             : List (Action model) -> Action model
boolCodec         : Codec Bool
build             : ctor -> CellBuilder ctor
cellCodec         : Cell a -> Codec a
cellEncodedInitial: Cell a -> Json.Encode.Value
cellFromInternal  : { id : Int, key : String, codec : Codec a, initial : a } -> Cell a
cellId            : Cell a -> Int
cellKey           : Cell a -> String
commit            : DebouncedCell a -> Action model
compose           : List (Validator err a) -> Validator err a
copy              : Cell a -> Cell a -> Action model
defineComponent   : { init, computed, view, reactions } -> ComponentDef model view cells computed
derive            : Read a -> Source a
embed             : ComponentDef model view cells computed -> cells -> view
floatCodec        : Codec Float
httpGet           : Handler -> String -> Decoder a -> Request RequestError a   -- Rad.Http
httpPost          : Handler -> String -> Encode.Value -> Decoder a -> Request RequestError a -- Rad.Http
include           : ComponentDef model view cells computed -> cells -> List (Reaction model)
input             : ValidatedCell err a -> Cell a
intCodec          : Codec Int
listCodec         : Codec a -> Codec (List a)
mapRequestError   : (e1 -> e2) -> Request e1 r -> Request e2 r
maybeCodec        : Codec a -> Codec (Maybe a)
modify            : Cell a -> (a -> a) -> Action model
noAction          : Action model
noRequest         : Request err a
on                : Source a -> (a -> Request err r) -> Cell (Remote err r) -> Reaction model
persistNow        : Action model
raw               : DebouncedCell a -> Source a
readSource        : Source a -> Registry -> a
remoteCodec       : Codec err -> Codec a -> Codec (Remote err a)
resetValidation   : ValidatedCell err a -> Action model
revert            : DebouncedCell a -> Action model
run               : ViewEngine view model -> AppDef view model computed -> Program Json.Decode.Value (AppModel model) (Msg model)
runBuilder        : CellBuilder model -> ( model, Registry )
runSyncOnly       : ValidatedCell err a -> Registry -> Maybe (Validation err a)
set               : Cell a -> a -> Action model
settled           : DebouncedCell a -> Source a
stringCodec       : Codec String
sync              : (a -> Result (List err) a) -> Validator err a
synced            : DebouncedCell a -> Source Bool
toSource          : Cell a -> Source a
validate          : ValidatedCell err a -> Action model
validation        : ValidatedCell err a -> Source (Validation err a)
validationCodec   : Codec err -> Codec a -> Codec (Validation err a)
validationReactions : ValidatedCell err a -> List (Reaction model)
with              : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
withDebounced     : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withInstance      : String -> ComponentDef model view cells computed -> CellBuilder (cells -> rest) -> CellBuilder rest
withValidated     : String -> a -> Codec a -> Codec err -> Validator err a -> CellBuilder (ValidatedCell err a -> rest) -> CellBuilder rest

-- Rad.Form (qualified as `Form.X` at use sites)
canSubmit         : Form fields -> Source Bool
checking          : Form fields -> Source Bool
dirty             : Form fields -> Source Bool
field             : Cell a -> Member
invalid           : Form fields -> Source Bool
mapValidated      : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
memberCount       : Form fields -> Int
onSubmit          : Form fields -> ValidatedGroup fields clean -> (clean -> Request err r) -> Cell (Remote err r) -> Reaction model
onValid           : Form fields -> ValidatedGroup fields clean -> (clean -> Action model) -> Reaction model
over              : Cell State -> fields -> List Member -> Form fields
reactions         : Form fields -> List (Reaction model)
readGroup         : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
reset             : Form fields -> Action model
stateCodec        : Codec State
status            : Form fields -> Source Status
submit            : Form fields -> Action model
submitPending     : Form fields -> Source Bool
validatedField    : ValidatedCell err a -> Member
validators1..8    : (see §10)
withState         : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest

-- Rad.Read
map               : (a -> b) -> Read a -> Read b
map2              : (a -> b -> c) -> Read a -> Read b -> Read c
read              : Source a -> Read a
run               : Read a -> Registry -> a

-- Rad.Http
prodHandler       : Handler
requestErrorCodec : Codec RequestError
```
