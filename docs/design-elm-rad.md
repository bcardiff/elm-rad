# Reactive Cell DSL — Design Document

## Overview

This document specifies a declarative DSL for building interactive UI applications in Elm. The DSL eliminates the need to hand-write `Msg` types, `update` functions, or `subscriptions`. Instead, applications are defined as a reactive graph of typed cells, computed derivations, view bindings, and effect reactions.

The runtime interprets this graph to produce a standard Elm `Program`.

## Motivation

In standard Elm Architecture (TEA), every user interaction requires:

1. A variant in a `Msg` union type
2. A case branch in `update`
3. Wiring in the `view` to emit that `Msg`

For applications with many interactive fields (forms, search UIs, dashboards), this creates a large amount of boilerplate where each field needs its own message, its own update branch, and often its own subscriptions for debouncing or async effects. The actual *intent* — "this input controls this piece of state, and when it changes, fetch new data" — is spread across three disconnected locations.

This DSL collapses that intent into a single declaration.

## Design Principles

1. **Cells are state, Sources are reads.** The type system enforces write/read direction.
2. **Buttons do sync, reactions do async.** A button click mutates cells. A reaction watches cells and performs effects. The path from user interaction to IO always passes through a cell change.
3. **Effects are data, handlers are injected.** The app declares what effects to perform; the runtime decides how. Swap the handler for testing.
4. **Components are definitions + cell records.** Definitions are code at module level (hot-reloadable). Cell records are plain data in the model (serializable, debugger-friendly). No functions are stored in the model.
5. **Persistence is structural.** Codecs and keys travel with cells. Restore is strict. Migrations are explicit JSON transforms.
6. **View engines are pluggable.** The runtime is view-agnostic. Each engine provides a `toHtml` transform. Mounting across engines is a plain function call.

---

## Core State Types

```elm
type Cell a
```

The primitive mutable state container. Created via `CellBuilder`, mutated via `Action`, read via `Source` conversion.

```elm
type Source a
```

Anything readable. The common interface for watching values in the view and reacting to changes. Cells convert to Sources; computed values are Sources; DebouncedCell/ValidatedCell expose Source accessors.

```elm
type DebouncedCell a
```

A cell with settle semantics. Maintains two internal values: `raw` (updates immediately on every write) and `settled` (updates after a timeout, or on explicit commit via enter/blur). See the Debounce section for full semantics.

```elm
type ValidatedCell a
```

A cell with a validation lifecycle. Wraps a `Cell a` (the input) and a reactive `Validation a` state. See the Validation section for full semantics.

```elm
type Form fields
```

A transaction boundary around a group of cells. Tracks dirty/pristine state, supports atomic reset/clear, and gates effects on collective validation. See the Forms section.

```elm
type Remote a
    = Idle
    | Loading
    | Failed String
    | Done a
```

The standard async data lifecycle. Used as the value type for cells that are targets of async reactions. The runtime manages transitions automatically: sets `Loading` when a reaction fires, `Done value` on success, `Failed error` on failure.

```elm
type Validation a
    = Dormant
    | Checking
    | Valid a
    | Invalid (List String)
```

The validation lifecycle. Stays `Dormant` until `validate` is called. After activation, re-runs on every input change. `resetValidation` returns to `Dormant`.

---

## Codecs

```elm
type alias Codec a =
    { encode : a -> Json.Value
    , decode : Decoder a
    }
```

Every cell carries a codec, provided at declaration time. The runtime uses these for persistence. Users write codecs for custom types only.

Built-in codecs:

```elm
stringCodec : Codec String
intCodec    : Codec Int
floatCodec  : Codec Float
boolCodec   : Codec Bool
listCodec   : Codec a -> Codec (List a)
maybeCodec  : Codec a -> Codec (Maybe a)
remoteCodec : Codec a -> Codec (Remote a)
```

### Why codecs are bundled with cell declarations

Codecs travel with cells so persistence is zero-config for v1. The alternative — a separate `extract`/`restore` pair that mirrors the model structure — duplicates the model definition and drifts out of sync. By attaching the codec at creation, the runtime has everything it needs to serialize/deserialize automatically.

---

## Cell Creation — The CellBuilder

The `CellBuilder` uses an applicative pattern to construct the model record with auto-assigned cell IDs. The model constructor is applied incrementally via `with` and its variants.

```elm
build : constructor -> CellBuilder constructor

with :
    String -> a -> Codec a
    -> CellBuilder (Cell a -> rest)
    -> CellBuilder rest

withDebounced :
    String -> Float -> a -> Codec a
    -> CellBuilder (DebouncedCell a -> rest)
    -> CellBuilder rest

withValidated :
    String -> a -> Codec a -> Validator a
    -> CellBuilder (ValidatedCell a -> rest)
    -> CellBuilder rest

withForm :
    String -> (FormBuilder -> fields)
    -> CellBuilder (Form fields -> rest)
    -> CellBuilder rest

withInstance :
    String -> ComponentDef view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest
```

The `String` argument is the persistence key. The `CellBuilder` threads an incrementing integer ID counter internally for runtime cell identity, but persistence uses the string key exclusively. This means declaration order can change between versions without invalidating stored data.

### Why string keys for persistence

Positional IDs (assigned by declaration order) break when fields are reordered or inserted. If v1 declares `query(0), results(1)` and v2 inserts `page` between them, the stored `"1"` (results) loads into `page`. String keys are stable across reorderings. They only appear at the persistence boundary — runtime cell identity still uses integer IDs for performance.

Example:

```elm
type alias Model =
    { query : Cell String
    , page : Cell Int
    , results : Cell (Remote (List SearchResult))
    }

init : CellBuilder Model
init =
    build Model
        |> with "query" "" stringCodec
        |> with "page" 1 intCodec
        |> with "results" Idle (remoteCodec (listCodec searchResultCodec))
```

---

## Conversions — Reading Cells

```elm
toSource : Cell a -> Source a

-- DebouncedCell
raw     : DebouncedCell a -> Source a     -- instant, every keystroke
settled : DebouncedCell a -> Source a     -- after timeout or commit
synced  : DebouncedCell a -> Source Bool  -- raw == settled

-- ValidatedCell
input      : ValidatedCell a -> Cell a              -- the raw input, writable
validation : ValidatedCell a -> Source (Validation a) -- the validation state

-- Form
fields   : Form f -> f
dirty    : Form f -> Source Bool
pristine : Form f -> Source Bool
```

### Why `toSource` exists

A `Cell a` can be read and written. A `Source a` can only be read. Functions like `watch` and `on` accept `Source a`, which means they work uniformly with cells, computed values, and DebouncedCell/ValidatedCell accessors. The type system prevents writing to a computed value or a settled accessor.

---

## Computed Values — The Read Monad

Computed values derive from other cells and recompute automatically when dependencies change.

```elm
read : Cell a -> Read a
read : Source a -> Read a

Read.map  : (a -> b) -> Read a -> Read b
Read.map2 : (a -> b -> c) -> Read a -> Read b -> Read c
Read.map3 : (a -> b -> c -> d) -> Read a -> Read b -> Read c -> Read d

derive : Read a -> Source a
```

The `Read` monad is internally a `Writer (Set CellId)` over the state — it accumulates dependencies while computing the value. The runtime tracks these dependencies and recomputes in topological order.

Computed values are declared in the `computed` field of the app definition:

```elm
, computed = \model ->
    { searchUrl =
        derive
            (Read.map2
                (\q p -> "/search?q=" ++ q ++ "&page=" ++ String.fromInt p)
                (read (settled model.searchInput))
                (read (toSource model.page))
            )
    }
```

### Why a separate computed record instead of inline derivations

Computed values live in a separate record (not in the model) because they are functions, not data. Storing functions in the model breaks the Elm debugger (which needs to serialize the model) and hot reload (which replaces code but preserves the model — stale closures would remain). The computed record is rebuilt every cycle from the current model.

### Multi-cell watching

There is no `watch2` or `watch3` combinator. Watching multiple cells is solved by deriving a computed tuple:

```elm
{ state = derive (Read.map2 Tuple.pair (read sourceA) (read sourceB)) }

-- then in the view:
watch computed.state (\(a, b) -> ...)
```

This composes without new primitives.

---

## Sync Actions — What Buttons Do

Actions are synchronous, immediate cell mutations. They never perform IO.

```elm
set    : Cell a -> a -> Action model
modify : Cell a -> (a -> a) -> Action model
copy   : Source a -> Cell a -> Action model
batch  : List (Action model) -> Action model

-- DebouncedCell
commit : DebouncedCell a -> Action model   -- force raw → settled immediately
revert : DebouncedCell a -> Action model   -- reset raw ← settled

-- ValidatedCell
validate        : ValidatedCell a -> Action model  -- activate validation
resetValidation : ValidatedCell a -> Action model  -- return to Dormant

-- Form
submitForm : Form f -> Action model
resetForm  : Form f -> Action model   -- revert to last snapshot
clearForm  : Form f -> Action model   -- revert to initial values

-- Persistence
persistNow : Action model              -- force immediate save
```

### Why buttons never trigger effects directly

If a button could directly fire an HTTP request, crash recovery would need to persist "this button was clicked" as state. By routing everything through cell mutations, the persisted cell values are sufficient to re-derive what effects should be in flight. The click materializes as a cell write before any effect fires, and that cell write is what gets persisted.

This is the core invariant that makes persistence and crash recovery work without storing effect metadata.

---

## Debounce

A `DebouncedCell a` manages two internal values and exposes them as sources:

- `raw` — updates immediately on every write (every keystroke)
- `settled` — updates after the timeout expires, or on explicit commit

### Commit triggers

`bindDebounced` attaches default commit triggers: `OnEnter`, `OnBlur`, and `OnTimeout`. Custom triggers are available via `bindDebouncedWith`:

```elm
type CommitTrigger = OnEnter | OnBlur | OnTimeout

bindDebounced     : DebouncedCell String -> Attribute model
bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> Attribute model
```

### The synced source

`synced : DebouncedCell a -> Source Bool` reports whether `raw == settled`. This enables common UI patterns without new primitives:

- Show a "pending" indicator while the user is typing
- Dim stale results while waiting for fresh ones
- Disable actions until input settles
- Show "press enter to search" hints

### Persistence of debounced state

Both `raw` and `settled` are persisted, plus whether a timer was pending. On restore, if a timer was pending, the runtime resumes it (or commits immediately if the remaining time has elapsed). This means a user can refresh mid-type and resume exactly where they were.

### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **Three Registry slots per `DebouncedCell`.** `withDebounced` allocates raw, settled, and a per-cell timer sequence counter. The raw and settled slots hold encoded `a` values; the timer-sequence slot holds an `Int`.

2. **Seq-based supersession.** Each `fromDebouncedInput` bumps the timer sequence; the scheduled `Process.sleep` task captures the seq it was created with. On fire, the runtime compares: if the fire's seq is less than the current seq, the fire is stale and the update is dropped. Latest input always wins without cancelling tasks.

3. **`commit` and `revert` are pure Actions.** They copy between raw and settled via the Registry. They do **not** touch the timer sequence. A pending timer fire after `commit` or `revert` finds raw and settled equal and performs a no-op copy. If the user typed again, that input bumped the seq and the pending fire is already stale.

4. **`synced` is derived.** Reads raw and settled via the cell's codec, compares their JSON-encoded forms. No stored flag — the source of truth is `raw == settled`. A stored flag would require every raw/settled write site to maintain it; the drift risk outweighed any observable win.

5. **Per-binding trigger sets.** `bindDebouncedWith` decides its `onInput` handler at attribute-wiring time: if the trigger list contains `OnTimeout`, the handler uses `Rad.Engine.fromDebouncedInput` (schedules a timer); otherwise it uses an internal `Action` that writes raw and bumps the seq without scheduling. `OnEnter` and `OnBlur` attach commit handlers regardless of whether `OnTimeout` is present.

### Why debounce is a cell type, not a reaction modifier

Debounce is fundamentally about the *value lifecycle* — two versions of the same data (immediate vs settled) that the view and reactions consume differently. Making it a cell type means `raw` and `settled` are both available as sources. If debounce were a reaction modifier, the view couldn't distinguish between the instant and settled values.

---

## Validation

A `ValidatedCell a` wraps a `Cell a` (the input) and a reactive `Validation a` state.

```elm
type Validator a
    = Sync (a -> Result (List String) a)
    | Async (a -> Request (Result (List String) a))
    | Compose (List (Validator a))
```

`Compose` runs validators in sequence. If a sync validator fails, subsequent async validators don't fire.

### Lifecycle

1. Initially `Dormant` — no errors shown, user hasn't triggered validation
2. `validate` action activates it — runs the validator, shows result
3. After activation, every change to `input` re-runs the validator immediately
4. `resetValidation` returns to `Dormant`

### Why validation starts Dormant

On fresh input, you don't want to warn the user — error messages on an empty form are hostile. Validation activates only on explicit trigger (typically a submit button calling `validate`). After that, it becomes reactive so fixing an error immediately clears the message.

### Async validation

Async validators (e.g., checking username availability) follow the same pattern as `Remote`: the validation state goes `Dormant → Checking → Valid/Invalid`. The runtime handles superseding — if input changes while an async check is in flight, the old check is discarded.

### Persistence of validation state

Both the input value and the validation state are persisted. On restore, `Checking` states re-fire the async validator (same as `Loading` cells re-fire their reactions).

### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **Three Registry slots per `ValidatedCell`.** `withValidated` allocates input, validation state, and a per-cell activation sequence counter. The input slot holds the encoded `a`; the validation slot holds encoded `Validation err a`; the activation seq slot holds an `Int` (0 when Dormant, >0 when active).

2. **Validator constructors are opaque.** Users build validators via `sync`, `async`, `compose`. The internal `Validator` constructors live in `Rad.Internal.Validated` and are not re-exported. This keeps the public surface small and lets later layers add validator variants (e.g., `deferred`, `whenDirty`) without breaking call sites.

3. **Reactions are reused; no new Msg variants.** Each `ValidatedCell` produces one `Reaction` (built by hand, not via `Rad.on`, because `on` writes to `Cell (Remote err r)` and we need to write to `Cell (Validation err a)`). The reaction's trigger is `[input value, activation seq]` encoded as a JSON list. Layer 2's reaction-seq handles latest-wins.

4. **Sync validators dispatch through the Cmd loop.** A pure-sync validator briefly shows `Checking` (one render frame) before landing on `Valid` / `Invalid`. Uniform dispatch through the reaction was chosen over a sync fast-path because the flash is imperceptible in practice; fast-path deferred if measured as a problem.

5. **Activation via an `Int` counter, not a `Bool`.** `validate` bumps the counter (0 → 1 → 2 → ...), which changes the reaction's trigger. Repeated `validate` clicks against unchanged input still re-run the validator — supporting "re-validate to pick up server-side state" UX. A Bool would miss the second click.

6. **`validationReactions` is composed manually by the user.** A user's `reactions` function concatenates `validationReactions vcell` with their own reactions. Auto-wiring was rejected to keep Layer 2's runtime surface unchanged and to keep control flow grep-able. Layer 5 Forms will collect field reactions and pre-compose.

---

## Forms

A `Form fields` is a transaction boundary around a group of cells.

```elm
withForm :
    String -> (FormBuilder -> fields)
    -> CellBuilder (Form fields -> rest)
    -> CellBuilder rest
```

The `FormBuilder` creates cells scoped to the form, with namespaced persistence keys:

```elm
|> withForm "profile" (\f ->
    { name = f.validated "name" "" stringCodec nameValidator
    , bio = f.cell "bio" "" stringCodec
    })
```

Persistence keys become `"profile.name"`, `"profile.bio"`.

### Snapshots

The form tracks a "pristine" snapshot of all cell values. `dirty` becomes `True` when any cell diverges. `resetForm` restores the snapshot. After a successful submit, current values become the new snapshot.

### Gating effects on validation

Forms integrate with the validation system to gate async effects:

```elm
onFormValid :
    Form f
    -> ValidatedGroup f clean
    -> (clean -> Action model)
    -> Reaction model

onFormSubmit :
    Form f
    -> ValidatedGroup f clean
    -> (clean -> Request r)
    -> Cell r
    -> Reaction model

valid1 : ValidatedCell a -> ValidatedGroup f a
valid2 : ValidatedCell a -> ValidatedCell b -> ValidatedGroup f ( a, b )
valid3 : ValidatedCell a -> ValidatedCell b -> ValidatedCell c -> ValidatedGroup f ( a, b, c )
```

`onFormSubmit` validates all cells in the group, waits for all to settle as `Valid`, then fires the effect with the unwrapped clean values — fully typed, no `Maybe` at the call site. If any validation fails, the effect doesn't fire.

### Use cases beyond wizards

- **Auto-save drafts**: form knows which fields are dirty, can trigger periodic saves of changed fields
- **Optimistic UI with rollback**: submit, show new state immediately, revert all fields if server rejects
- **Conditional field visibility**: field B appears only if field A has a certain value; form preserves B's value if A toggles back
- **Undo at form level**: form can snapshot state on each commit

---

## Reactions — Async Effects

Reactions declare relationships between cell changes and async effects. They are the only way to perform IO.

```elm
on :
    Source a
    -> (a -> Request r)
    -> Cell r
    -> Reaction model

include :
    ComponentDef view cells computed
    -> cells
    -> List (Reaction model)
```

### Semantics of `on`

When the source value changes:

1. The target cell is set to `Loading`
2. The request function is called with the new source value
3. On success, the target is set to `Done value`
4. On failure, the target is set to `Failed error`
5. If the source changes again while a request is in flight, the in-flight request is cancelled (latest wins)

### Why latest-wins is the default

For data-fetching UIs (which are the target use case), you almost always want the result of the *latest* trigger. Search-as-you-type, filtering, pagination — in all cases, a new request supersedes the previous one. The runtime implements this with a monotonic sequence number per reaction.

### The Request DSL

```elm
type Request a

httpGet   : String -> Decoder a -> Request a
httpPost  : String -> Json.Value -> Decoder a -> Request a
noRequest : Request a
```

Requests are data — descriptions of what to perform, never the execution itself.

### The Effect Handler

```elm
type alias Handler =
    { httpGet  : String -> Task Http.Error String
    , httpPost : String -> Json.Value -> Task Http.Error String
    }
```

The handler is injected at `run`. For testing, swap with a mock:

```elm
mockHandler : Handler
mockHandler =
    { httpGet = \url ->
        if String.contains "search" url then
            Task.succeed """[{"title":"mock"}]"""
        else
            Task.succeed "[]"
    , httpPost = \_ _ -> Task.succeed "{}"
    }
```

---

## View

The view is a function from model and computed values to a view type. The view type is polymorphic — the runtime is view-engine-agnostic.

```elm
watch : Source a -> (a -> view) -> view

bind              : Cell String -> Attribute model
bindDebounced     : DebouncedCell String -> Attribute model
bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> Attribute model
onClick           : Action model -> Attribute model

embed : ComponentDef view cells computed -> cells -> view
```

`watch` is generic over the view type. It works the same regardless of engine. The runtime intercepts it at the reactivity level (tracking which sources were read) and delegates rendering to the engine.

### HTML engine primitives (example)

```elm
col      : List (Attribute model) -> List (HtmlView model) -> HtmlView model
row      : List (Attribute model) -> List (HtmlView model) -> HtmlView model
input    : List (Attribute model) -> List (HtmlView model) -> HtmlView model
button   : List (Attribute model) -> List (HtmlView model) -> HtmlView model
textarea : List (Attribute model) -> List (HtmlView model) -> HtmlView model
select   : List (Attribute model) -> List (HtmlView model) -> HtmlView model
option   : String -> String -> HtmlView model
text     : String -> HtmlView model
```

### Implicit persistence on blur

All bindings trigger `persistNow` on blur by default. Buttons trigger `persistNow` after their action completes. This means tabbing through a form and clicking buttons never loses work. The user would have to crash within the debounced save window (default 500ms) to lose anything typed mid-field.

---

## View Engines

The runtime doesn't care about the view type. Each engine provides a single transform:

```elm
type alias ViewEngine view model =
    { toHtml : view -> Html model
    }
```

There is one runner:

```elm
run : Handler -> ViewEngine view model -> AppDef view model computed -> Program
```

Built-in engines:

```elm
htmlEngine   : ViewEngine (HtmlView model) model
svgEngine    : { width : Int, height : Int } -> ViewEngine (SvgView model) model
canvasEngine : CanvasConfig -> ViewEngine (CanvasView model) model
```

### Cross-engine mounting

Mounting one engine inside another is a plain function call, not a framework concept:

```elm
Svg.toHtmlView    : { width : Int, height : Int } -> SvgView model -> HtmlView model
Canvas.toHtmlView : CanvasConfig -> CanvasView model -> HtmlView model
```

Example — an SVG chart embedded in an HTML app:

```elm
view = \model _ ->
    col []
        [ text "Dashboard"
        , Svg.toHtmlView { width = 600, height = 400 }
            (embed scatterPlot model.scatter)
        , button [ onClick (set model.page 1) ] [ text "Reset" ]
        ]
```

### Why a single runner

The runtime's job is managing cells, reactions, persistence, and the reactive dependency graph. None of that depends on the view type. Having per-engine runners (`runHtml`, `runSvg`, `runCanvas`) duplicates the entire runtime for no reason. The engine is just the last mile — converting the view value into `Html` for the browser.

---

## Components

A component is a reusable bundle of cells, computed values, a view, and reactions.

### Definition (module-level, code)

```elm
type ComponentDef view cells computed

defineComponent :
    { init : ComponentBuilder -> cells
    , computed : cells -> computed
    , view : cells -> computed -> view
    , reactions : cells -> computed -> List (Reaction model)
    }
    -> ComponentDef view cells computed
```

### Instance (in-model, pure data)

The component's cells record embeds directly in the parent model. There is no `Instance` wrapper type — it would add noise with no benefit. The cells record is plain data: serializable, debugger-friendly, survives hot reload.

```elm
type alias Model =
    { title : Cell String
    , category : TagPickerCells    -- just the cells record, no wrapper
    , tags : TagPickerCells
    }
```

### Why no Instance wrapper

`Instance cells` would be `Instance { selected : Cell String, search : DebouncedCell String, ... }` — a wrapper around a record of cells. The type system already enforces correctness: `embed` and `include` require a `ComponentDef view cells computed` whose `cells` type matches the record. Passing a random record that doesn't match is a compile error. The wrapper adds indirection without adding safety.

### Mounting

```elm
withInstance :
    String -> ComponentDef view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest
```

Persistence keys are namespaced automatically: `"primary.selected"`, `"primary.search"`, etc.

### Rendering and reactions

```elm
embed   : ComponentDef view cells computed -> cells -> view
include : ComponentDef view cells computed -> cells -> List (Reaction model)
```

The parent passes the component definition and the cells record. `embed` calls the component's view function; `include` calls its reactions function.

### Parameterization

A parameterized component is a function returning a `ComponentDef`:

```elm
tagPicker : { endpoint : String, placeholder : String } -> ComponentDef (HtmlView model) TagPickerCells {}
tagPicker config =
    defineComponent
        { init = \b ->
            { selected = b.cell "selected" "" stringCodec
            , search = b.debounced "search" 300 "" stringCodec
            , suggestions = b.cell "suggestions" Idle (remoteCodec (listCodec stringCodec))
            , open = b.cell "open" False boolCodec
            }
        , computed = \_ -> {}
        , view = \c _ ->
            col []
                [ input [ bindDebounced c.search, attr "placeholder" config.placeholder ] []
                , ...
                ]
        , reactions = \c _ ->
            [ on (settled c.search)
                (\q -> httpGet (config.endpoint ++ "?q=" ++ q) (listCodec stringCodec).decode)
                c.suggestions
            ]
        }
```

Bind configurations at module level to avoid repeating them:

```elm
categoryPicker : ComponentDef (HtmlView model) TagPickerCells {}
categoryPicker = tagPicker { endpoint = "/api/categories", placeholder = "Category..." }
```

### Hot reload correctness

On hot reload: code updates replace the `ComponentDef` (including view and reaction functions). The model survives — it's just cells, pure data. Next render calls the *new* view function with the *old* cells. Everything works because no functions are stored in the model.

### Accessing component cells from the parent

Normal record access:

```elm
read (toSource model.category.selected)

watch (toSource model.tags.selected) (\tag -> text ("Tagged: " ++ tag))
```

---

## Persistence

### Configuration

```elm
type alias PersistConfig =
    { key : String
    , version : Int
    , migrations : List Migration  -- defaults to []
    }
```

For a first version, this is all you need:

```elm
, persist = Just { key = "myapp", version = 1, migrations = [] }
```

Codecs and persistence keys are already attached to cells via `CellBuilder`. The runtime serializes everything automatically.

### What gets persisted

Everything. All cell types persist their full state:

- `Cell a` — the current value
- `DebouncedCell a` — raw value, settled value, and whether a timer was pending
- `ValidatedCell a` — input value and validation state
- `Remote a` — all four variants including `Loading` and `Done` with payload
- `Form fields` — all child cells plus the pristine snapshot

### Stored format

```json
{
  "version": 1,
  "cells": {
    "query": { "type": "debounced", "raw": "cats", "settled": "cats", "pending": false },
    "page": { "type": "cell", "value": 3 },
    "results": { "type": "cell", "value": { "tag": "Done", "value": [...] } },
    "category.selected": { "type": "cell", "value": "photos" },
    "category.search": { "type": "debounced", "raw": "", "settled": "", "pending": false }
  }
}
```

### Restore behavior (strict)

1. Read `localStorage[key]`
2. If missing → use init defaults
3. If stored version ≠ current version and no migration chain covers the gap → discard everything, use init defaults
4. Apply migration chain if needed
5. Decode every cell using its codec
6. If any cell fails to decode → discard everything, use init defaults
7. If all cells decode → populate all cells
8. Re-fire reactions for any cells in `Loading` or `Checking` state (see Crash Recovery below)

### Why strict, not best-effort

Partial restore can leave the app in an inconsistent state — a form half-populated, a filter applied without its dependent data loaded. For crash recovery, a clean restart is preferable to a confusing half-state. The user loses at most their most recent session's work (which is often seconds of typing given the aggressive auto-save).

### Save triggers

- Debounced timer (default 500ms after last cell change)
- On blur of any bound input (implicit)
- After any button action completes (implicit)
- On page visibility change (browser tab hidden)
- Explicit `persistNow` action

### Crash recovery — re-firing reactions

On restore, the runtime does not persist any effect metadata (no pending effect queue, no request descriptions). Instead, it re-derives what should be in flight from the reactive graph:

For each `on source transform target` reaction:
- If `target` contains `Loading` → re-fire `transform (current source)`
- If `target` contains any other state → do nothing

For each async `Validator`:
- If validation state is `Checking` → re-fire the validator with current input

This works because the reaction declaration is still in the code, and the source cell has the value that originally triggered the effect. The key insight: effects are reactive ("when this cell has this value, this effect should be in flight"), not imperative ("this button was clicked"). So the question on restore is "what should be happening given the current cell state?" — which the reaction graph answers directly.

### Size considerations

Persisting `Remote (Done payload)` with large payloads can approach localStorage limits (typically 5-10MB). For apps with large result sets, consider using an ephemeral cell variant (future work) that persists only the `Loading`/`Idle`/`Failed` status and re-fetches on restore.

### Migrations

Not needed for v1. When the schema changes in a future version, bump the version number and add a migration:

```elm
, persist = Just
    { key = "myapp"
    , version = 2
    , migrations =
        [ { from = 1
          , to = 2
          , migrate = \v1 -> v1 |> insertField "theme" (Encode.string "light")
          }
        ]
    }
```

Migrations operate on raw `Json.Value` — the old Elm types may no longer exist in the codebase. The runtime chains migrations: stored v1 → current v3 runs `1→2` then `2→3`.

Migration helpers:

```elm
insertField : String -> Json.Value -> Json.Value -> Result String Json.Value
removeField : String -> Json.Value -> Result String Json.Value
renameField : String -> String -> Json.Value -> Result String Json.Value
mapField    : String -> (Json.Value -> Json.Value) -> Json.Value -> Result String Json.Value
```

---

## The App Definition

```elm
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
    , persist : Maybe PersistConfig
    }

run : Handler -> ViewEngine view model -> AppDef view model computed -> Program
```

---

## Complete Example

```elm
module Main exposing (main)

-- Component definition

type alias TagPickerCells =
    { selected : Cell String
    , search : DebouncedCell String
    , suggestions : Cell (Remote (List String))
    , open : Cell Bool
    }

tagPicker :
    { endpoint : String, placeholder : String }
    -> ComponentDef (HtmlView model) TagPickerCells {}
tagPicker config =
    defineComponent
        { init = \b ->
            { selected = b.cell "selected" "" stringCodec
            , search = b.debounced "search" 300 "" stringCodec
            , suggestions = b.cell "suggestions" Idle (remoteCodec (listCodec stringCodec))
            , open = b.cell "open" False boolCodec
            }
        , computed = \_ -> {}
        , view = \c _ ->
            col []
                [ watch (toSource c.open) (\isOpen ->
                    if isOpen then
                        col []
                            [ input
                                [ bindDebounced c.search
                                , attr "placeholder" config.placeholder
                                ]
                                []
                            , watch c.suggestions (\r ->
                                case r of
                                    Done tags ->
                                        col [] (List.map (\t ->
                                            button
                                                [ onClick
                                                    (batch
                                                        [ set c.selected t
                                                        , set c.open False
                                                        ]
                                                    )
                                                ]
                                                [ text t ]
                                        ) tags)
                                    Loading -> spinner
                                    _ -> text ""
                              )
                            ]
                    else
                        watch (toSource c.selected) (\t ->
                            button [ onClick (set c.open True) ]
                                [ text
                                    (if t == "" then
                                        config.placeholder
                                     else
                                        t
                                    )
                                ]
                        )
                  )
                ]
        , reactions = \c _ ->
            [ on (settled c.search)
                (\q ->
                    httpGet
                        (config.endpoint ++ "?q=" ++ q)
                        (listCodec stringCodec).decode
                )
                c.suggestions
            ]
        }

categoryPicker : ComponentDef (HtmlView model) TagPickerCells {}
categoryPicker =
    tagPicker { endpoint = "/api/categories", placeholder = "Category..." }

tagsPicker : ComponentDef (HtmlView model) TagPickerCells {}
tagsPicker =
    tagPicker { endpoint = "/api/tags", placeholder = "Tags..." }


-- App

type alias Model =
    { searchInput : DebouncedCell String
    , category : TagPickerCells
    , tags : TagPickerCells
    , page : Cell Int
    , results : Cell (Remote (List SearchResult))
    }

type alias Computed =
    { searchUrl : Source String
    }

app : AppDef (HtmlView Model) Model Computed
app =
    { init =
        build Model
            |> withDebounced "search" 300 "" stringCodec
            |> withInstance "category" categoryPicker
            |> withInstance "tags" tagsPicker
            |> with "page" 1 intCodec
            |> with "results" Idle (remoteCodec (listCodec searchResultCodec))
    , computed = \model ->
        { searchUrl =
            derive
                (Read.map3
                    (\q cat p ->
                        "/search?q=" ++ q
                            ++ "&cat=" ++ cat
                            ++ "&page=" ++ String.fromInt p
                    )
                    (read (settled model.searchInput))
                    (read (toSource model.category.selected))
                    (read (toSource model.page))
                )
        }
    , view = \model computed ->
        col []
            [ row []
                [ input [ bindDebounced model.searchInput ] []
                , watch (synced model.searchInput) (\s ->
                    if not s then
                        spinner
                    else
                        text ""
                  )
                ]
            , row []
                [ embed categoryPicker model.category
                , embed tagsPicker model.tags
                ]
            , watch model.results (\r ->
                case r of
                    Idle ->
                        text "Search something"

                    Loading ->
                        spinner

                    Failed e ->
                        text e

                    Done rs ->
                        col [] (List.map viewResult rs)
              )
            , watch model.results (\r ->
                case r of
                    Done _ ->
                        row []
                            [ button
                                [ onClick (modify model.page (\n -> max 1 (n - 1))) ]
                                [ text "←" ]
                            , watch (toSource model.page) (\p ->
                                text (String.fromInt p)
                              )
                            , button
                                [ onClick (modify model.page (\n -> n + 1)) ]
                                [ text "→" ]
                            ]

                    _ ->
                        text ""
              )
            ]
    , reactions = \model computed ->
        include categoryPicker model.category
            ++ include tagsPicker model.tags
            ++ [ on computed.searchUrl
                    (\url ->
                        httpGet url (listCodec searchResultCodec).decode
                    )
                    model.results
               ]
    , persist = Just { key = "search-app", version = 1, migrations = [] }
    }


main : Program
main =
    run prodHandler htmlEngine app
```

---

## Summary of Non-Obvious Decisions

| Decision | Reasoning |
|---|---|
| String keys for persistence, integer IDs for runtime | String keys survive field reordering across versions. Integer IDs are faster for runtime dispatch. |
| Codecs bundled with cell declarations | Eliminates a separate persistence layer that would mirror and drift from the model definition. |
| No functions in the model | Required for Elm debugger serialization and hot reload correctness. Component definitions live at module level; cell records in the model are pure data. |
| No `Instance` wrapper type | The cells record embeds directly. Type safety comes from `embed`/`include` requiring a matching `ComponentDef`, not from a wrapper. |
| Buttons never trigger effects directly | Effects fire as reactions to cell changes. This means persisted cell values are sufficient to re-derive in-flight effects on crash recovery — no effect metadata needs to be stored. |
| Strict restore (all or nothing) | Partial restore can produce inconsistent state. A clean restart is safer than a confusing half-populated UI. |
| Debounce as a cell type, not a reaction modifier | The view needs both the raw and settled values simultaneously. A modifier would only expose one. |
| Validation starts Dormant | Error messages on untouched fields are hostile UX. Validation activates on explicit trigger, then becomes reactive. |
| Latest-wins cancellation as the default for `on` | The target use case is data-fetching UIs where the latest trigger value is always the relevant one. |
| Single generic `run` with pluggable `ViewEngine` | The runtime manages cells, reactions, and persistence — none of which depend on the view type. Per-engine runners would duplicate all of that. |
| Computed values in a separate record, not the model | They are derived from functions and would break debugger serialization and hot reload if stored in the model. |
| `watch` is generic over view type | Reactivity tracking is engine-agnostic. The engine only needs to render the final value. |
| Migrations operate on raw JSON | Old Elm types may not exist in the new codebase. JSON-to-JSON transforms are always valid and testable in isolation. |
| Persistence saves on blur and after actions by default | Crash recovery should lose at most a few hundred milliseconds of typing. Explicit `persistNow` is available for critical moments. |

---

## Future Work

- **ListOf**: Dynamic lists of component instances with runtime cell allocation, stable identity, and reordering support.
- **Routing**: URL as a bidirectional cell — parsing URL → model state and generating URL ← model state from a single route definition.
- **Ephemeral cells**: Cells whose `Remote Done` payload is not persisted — only the status is stored, and the reaction re-fires on restore. Useful for large result sets approaching localStorage limits.
- **Form auto-save**: Periodic persistence of dirty form fields without explicit user action, using the form's dirty tracking.
- **Animation**: Time-varying sources for transitions and animated values.
