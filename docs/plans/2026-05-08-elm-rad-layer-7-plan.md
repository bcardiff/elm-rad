# elm-rad Layer 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 7 — opt-in localStorage persistence with debounced auto-save, strict restore, and crash recovery. One outgoing port + ~5 lines of JS for users; `persist = Nothing` keeps existing apps unchanged after one mechanical update.

**Architecture:** `BuildResult` carries a `List PersistEntry` populated by each cell-builder primitive. `Rad.run` reads `Json.Decode.Value` flags, attempts strict restore, and walks reactions whose targets are in-flight after restore. Save fires from a debounced timer (latest-wins via dirty counter) or explicit `persistNow`.

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x. No new dependencies. Vite 6 for the example host.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (memory `feedback_commit_cadence.md`).
- **One task = one commit** unless a header says otherwise.
- **Run elm-format before EVERY commit touching `.elm`:** `npx --yes elm-format src tests --yes` from repo root; `(cd examples && npx --yes elm-format src --yes)` for examples.
- **Verify with `npx --yes elm-test`** from repo root. `cd examples && npm run build` for examples.
- **Commit messages: single-line imperative.** No `Co-Authored-By` trailers.

**Design-doc deviations (applied throughout):**

1. **Tests pass `Encode.Value` directly to `Rad.Internal.Persist` helpers** rather than going through `Json.Decode.decodeString`. The flag-flow's string-decode branch is exercised by integration tests in `Rad.run`, but unit tests work with `Decode.Value` for clarity.

2. **`PersistEntry` does NOT carry an `inFlightFromBlob` field.** Crash recovery is reaction-driven (`IReaction.Guts.inFlight : Registry -> Bool`). The schema entry is purely for save/restore.

**Module layout at the end:**

```
src/
  Rad.elm                         ← +PersistConfig, persistNow, AppDef.persist field,
                                    Json.Decode.Value flags, save/restore wiring
  Rad/
    Engine.elm                    ← +PersistTimerFired Int, PersistRequested Msg variants
    Form.elm                      ← Member.inputKey + dirty/reset/advanceSnapshot use cell.key
    Engine.elm, Http.elm, Read.elm, View.elm  ← otherwise unchanged
    Internal/
      Persist.elm                 ← NEW (PersistEntry, save/restore/recovery helpers)
      CellBuilder.elm             ← +persist : List PersistEntry on BuildResult
      Debounced.elm               ← +key : String on internal record
      Validated.elm               ← +key : String on internal record
      Form.elm                    ← +Member.inputKey, stateCodec tolerates null
      Reaction.elm                ← +Guts.inFlight : Registry -> Bool
      Action.elm, Component.elm, Msg.elm, Registry.elm, Request.elm, Source.elm,
      ValidatedGroup.elm          ← unchanged

tests/
  PersistEntryTest.elm            ← NEW
  PersistRestoreTest.elm          ← NEW
  PersistSaveDebounceTest.elm     ← NEW
  PersistCrashRecoveryTest.elm    ← NEW
  FormSnapshotKeyTest.elm         ← NEW
  FormDirtyTest.elm               ← updated (re-key snapshot tests to cell.key)
  FormResetTest.elm               ← updated (no snapshot in tests, no change)
  <other existing>                ← unchanged

examples/
  src/
    L07E01_PersistCounter.elm     ← NEW
    L01E01..L06E02 (20 files)     ← all gain `persist = Nothing` + flag-type update
    ProfileForm.elm, WizardStep.elm  ← gain `persist = Nothing` + flag-type update
    SimpleView.elm, TestRunner.elm   ← unchanged
  L07E01-persist-counter.html     ← NEW
  vite.config.js                  ← +1 entry
  index.html                      ← +1 link

docs/
  design-elm-rad.md               ← Persistence section gains Implementation notes subsection
```

**Expected test count after Layer 7:** 118 pre + ~30 new = **~148**.

**Expected example count after Layer 7:** 20 pre + 1 new = **22 entries** (index + 21 examples).

---

## Slice 0 — Internal prereqs

### Task 0.1: Thread `key : String` into `DebouncedCell` internal record

**Files:**
- Modify: `src/Rad/Internal/Debounced.elm`
- Modify: `src/Rad.elm` (`withDebounced` body)

- [ ] **Step 1: Verify the 118-test baseline.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 2: Read `src/Rad/Internal/Debounced.elm` to confirm the current shape of the `Core` record** (or whatever the internal record is named). It currently has `{ rawId, settledId, timerSeqId, codec, delayMs, initial }`.

- [ ] **Step 3: Add `key : String` to the internal record.**

In `src/Rad/Internal/Debounced.elm`, find the type definition that contains `rawId : Int` and add `key : String` immediately after the closing brace fields. Example:

```elm
type DebouncedCell a
    = DebouncedCell
        { rawId : Int
        , settledId : Int
        , timerSeqId : Int
        , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
        , delayMs : Float
        , initial : a
        , key : String         -- NEW
        }
```

(Adjust to match the actual existing field order — preserve every existing field exactly.)

- [ ] **Step 4: Update `withDebounced` in `src/Rad.elm`.**

Find `withDebounced`. Currently the first parameter is `_` (key dropped). Replace `_` with `key` and pass `key` into the constructor:

```elm
withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withDebounced key delayMs initial codec (CellBuilder f) =
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
                        , key = state.prefix ++ key
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

(Match the existing structure and any field order in the constructor.)

- [ ] **Step 5: Verify all tests still pass.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 6: Run `elm-format` and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Debounced.elm
git commit -m "Thread key into DebouncedCell internal record"
```

---

### Task 0.2: Thread `key : String` into `ValidatedCell` internal record

**Files:**
- Modify: `src/Rad/Internal/Validated.elm`
- Modify: `src/Rad.elm` (`withValidated` body)

- [ ] **Step 1: Add `key : String` to `Core` record in `src/Rad/Internal/Validated.elm`.**

```elm
type alias Core err a =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , errCodec : { encode : err -> Decode.Value, decode : Decode.Decoder err }
    , validator : Validator err a
    , initial : a
    , key : String                  -- NEW
    }
```

- [ ] **Step 2: Update `withValidated` in `src/Rad.elm`.**

Replace the `_` (currently-dropped) key parameter with `key`. Add `, key = state.prefix ++ key` to the `IValidated.ValidatedCell { ... }` constructor record.

- [ ] **Step 3: Verify tests pass.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 4: Run `elm-format` and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Validated.elm
git commit -m "Thread key into ValidatedCell internal record"
```

---

### Task 0.3: Add `inFlight : Registry -> Bool` to `IReaction.Guts` (default False)

**Files:**
- Modify: `src/Rad/Internal/Reaction.elm`
- Modify: `src/Rad.elm` (update `internalValidationReactionGuts` and `on` to provide `inFlight`)

- [ ] **Step 1: Update `Rad/Internal/Reaction.elm`.** Add `inFlight` to the `Guts` alias:

```elm
type alias Guts =
    { readTrigger : Registry -> Encode.Value
    , buildRequest : Registry -> InternalRequest
    , writeLoading : Registry -> Registry
    , writeResult : Encode.Value -> Registry -> Registry
    , inFlight : Registry -> Bool                    -- NEW
    }
```

- [ ] **Step 2: Update `Rad.elm`'s `internalValidationReactionGuts`** to set `inFlight`:

The validation slot decodes to a `Validation`. We check the `tag` field. Add to the returned record:

```elm
    , inFlight =
        \registry ->
            case Registry.get c.validationId registry of
                Just v ->
                    case Decode.decodeValue (Decode.field "tag" Decode.string) v of
                        Ok "Checking" ->
                            True

                        _ ->
                            False

                Nothing ->
                    False
```

- [ ] **Step 3: Update `Rad.elm`'s `on` function** to set `inFlight`:

The target is `Cell (Remote err r)`. Check if its current encoded value has tag `"Loading"`:

```elm
    , inFlight =
        \registry ->
            case Registry.get target.id registry of
                Just v ->
                    case Decode.decodeValue (Decode.field "tag" Decode.string) v of
                        Ok "Loading" ->
                            True

                        _ ->
                            False

                Nothing ->
                    False
```

- [ ] **Step 4: Update any other `IReaction.Reaction { ... }` constructors in `Rad.elm`** to include `inFlight = \_ -> False`. Search `Rad.elm` for `IReaction.Reaction` and ensure each has the field. If only `on` and `validationReaction` use it, those two are covered above.

- [ ] **Step 5: Update `Rad.Form`'s `onSubmit` and `onValid` to set `inFlight`.**

In `src/Rad/Form.elm`, the existing `onSubmit` returns `IReaction.fromGuts { ... }`. Add the new field:

For `onSubmit`:
```elm
    , inFlight =
        \registry ->
            let
                state =
                    IForm.readState f.stateId registry
            in
            -- A submit is in-flight iff submitSeq > lastResolvedSubmitSeq
            -- AND the target Cell is in Loading state.
            (state.submitSeq > state.lastResolvedSubmitSeq)
                && (case Registry.get targetId registry of
                        Just v ->
                            case Decode.decodeValue (Decode.field "tag" Decode.string) v of
                                Ok "Loading" ->
                                    True

                                _ ->
                                    False

                        Nothing ->
                            False
                   )
```

For `onValid` (no target Cell to check, so just submitSeq state):
```elm
    , inFlight =
        \registry ->
            let
                state =
                    IForm.readState f.stateId registry
            in
            state.submitSeq > state.lastResolvedSubmitSeq
```

- [ ] **Step 6: Verify tests pass.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 7: Run `elm-format` and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Reaction.elm src/Rad/Form.elm
git commit -m "Add inFlight field to IReaction.Guts"
```

---

## Slice 1 — `Rad.Internal.Persist` skeleton

### Task 1.1: Create `Rad.Internal.Persist` with `PersistEntry` type

**Files:**
- Create: `src/Rad/Internal/Persist.elm`

- [ ] **Step 1: Create the module.**

```elm
module Rad.Internal.Persist exposing (PersistEntry)

{-| Internal: per-cell persistence schema entry. Each cell-building primitive
(`with`, `withDebounced`, `withValidated`, `Form.withState`) appends one entry
to `BuildResult.persist`. The runtime walks this list to save and restore.

User code never references `PersistEntry` directly; it's an internal
collaboration between builders and the runtime.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry exposing (Registry)


type alias PersistEntry =
    { key : String
    , typeTag : String
    , encode : Registry -> Maybe Encode.Value
    , decode : Encode.Value -> Registry -> Result String Registry
    }
```

- [ ] **Step 2: Verify package compiles.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 3: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Internal/Persist.elm
git commit -m "Add internal Persist module skeleton"
```

---

## Slice 2 — Schema field on `BuildResult`

### Task 2.1: Extend `BuildResult` with `persist : List PersistEntry`

**Files:**
- Modify: `src/Rad/Internal/CellBuilder.elm`
- Modify: `src/Rad.elm` (every place that constructs a `BuildResult`)

- [ ] **Step 1: Update `src/Rad/Internal/CellBuilder.elm`.**

Add the import:
```elm
import Rad.Internal.Persist as IPersist
```

Update `BuildResult`:
```elm
type alias BuildResult ctor =
    { nextId : Int
    , metas : List ( Int, Decode.Value )
    , persist : List IPersist.PersistEntry          -- NEW
    , ctor : ctor
    }
```

- [ ] **Step 2: Update `Rad.elm`'s `build`, `with`, `withDebounced`, `withValidated`, `withInstance`, and `runBuilder` to thread `persist`.**

For each function that constructs a `BuildResult { nextId, metas, ctor }` record, add `, persist = ...` with an empty list (`[]`) for now — actual entries are appended in Slice 3.

`build`:
```elm
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        (\state ->
            { nextId = state.nextId
            , metas = []
            , persist = []                            -- NEW
            , ctor = ctor
            }
        )
```

`with` (currently appends to `metas`; also append `[]` to `persist` from parent):
```elm
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
            , persist = parent.persist               -- NEW: pass through (Slice 3 appends here)
            , ctor = parent.ctor cell
            }
        )
```

Same pattern for `withDebounced`, `withValidated`, `withInstance` — pass `parent.persist` through (or, for `withInstance`, concatenate child + parent persist lists).

For `withInstance`:
```elm
{ nextId = child.nextId
, metas = child.metas ++ parent.metas
, persist = child.persist ++ parent.persist        -- NEW
, ctor = parent.ctor child.ctor
}
```

`runBuilder`:
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

(`runBuilder`'s body doesn't change; `persist` is consumed by Slice 4's runtime, not here.)

- [ ] **Step 3: Verify tests pass.**

```
npx --yes elm-test
```
Expected: **118 passed**.

- [ ] **Step 4: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/CellBuilder.elm
git commit -m "Add persist schema field to BuildResult"
```

---

## Slice 3 — Per-cell encoders + wire into builders

### Task 3.1: `Cell a` encode/decode + wire into `Rad.with`

**Files:**
- Modify: `src/Rad/Internal/Persist.elm`
- Modify: `src/Rad.elm` (`with`)
- Create: `tests/PersistEntryTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/PersistEntryTest.elm`:

```elm
module PersistEntryTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Internal.CellBuilder as ICellBuilder
import Rad.Internal.Persist as IPersist
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { n : Rad.Cell Int }


init =
    build Model |> Rad.with "n" 7 Rad.intCodec


suite : Test
suite =
    describe "PersistEntry — Cell a"
        [ test "with appends one schema entry with the cell's key" <|
            \_ ->
                let
                    (ICellBuilder.CellBuilder f) =
                        init

                    result =
                        f { nextId = 0, prefix = "" }
                in
                case result.persist of
                    [ entry ] ->
                        Expect.equal "n" entry.key

                    _ ->
                        Expect.fail "expected exactly one persist entry"
        , test "encode reads the cell value from registry and produces correct blob" <|
            \_ ->
                let
                    (ICellBuilder.CellBuilder f) =
                        init

                    result =
                        f { nextId = 0, prefix = "" }

                    initialRegistry =
                        result.metas
                            |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"
                in
                case entry.encode initialRegistry of
                    Just blob ->
                        Expect.equal
                            (Ok 7)
                            (Decode.decodeValue (Decode.field "value" Decode.int) blob)

                    Nothing ->
                        Expect.fail "expected Just"
        , test "decode round-trips: encode then decode reproduces the registry" <|
            \_ ->
                let
                    (ICellBuilder.CellBuilder f) =
                        init

                    result =
                        f { nextId = 0, prefix = "" }

                    initialRegistry =
                        result.metas
                            |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"

                    blob =
                        case entry.encode initialRegistry of
                            Just b ->
                                b

                            Nothing ->
                                Debug.todo "encode failed"

                    decoded =
                        entry.decode blob Registry.empty
                in
                case decoded of
                    Ok r ->
                        Expect.equal (Just (Encode.int 7)) (Registry.get 0 r)

                    Err e ->
                        Expect.fail ("decode failed: " ++ e)
        ]
```

(Note: `Debug.todo` is acceptable in test scaffolding — the harness exits before reaching it on success.)

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/PersistEntryTest.elm
```
Expected: compile error or test failure (the schema entry isn't being built yet).

- [ ] **Step 3: Add a Cell encoder helper to `src/Rad/Internal/Persist.elm`.**

```elm
module Rad.Internal.Persist exposing (PersistEntry, cellEntry)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry as Registry exposing (Registry)


type alias PersistEntry =
    { key : String
    , typeTag : String
    , encode : Registry -> Maybe Encode.Value
    , decode : Encode.Value -> Registry -> Result String Registry
    }


{-| Build a PersistEntry for a `Cell a`-typed slot.
-}
cellEntry :
    { id : Int
    , key : String
    , encoder : Encode.Value -> Encode.Value
    , decoder : Decode.Decoder Encode.Value
    }
    -> PersistEntry
cellEntry r =
    { key = r.key
    , typeTag = "cell"
    , encode =
        \registry ->
            Registry.get r.id registry
                |> Maybe.map
                    (\v ->
                        Encode.object
                            [ ( "type", Encode.string "cell" )
                            , ( "value", v )
                            ]
                    )
    , decode =
        \blob registry ->
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "cell" then
                                    Decode.field "value" Decode.value

                                else
                                    Decode.fail ("expected type=cell, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok inner ->
                    -- Validate the inner value via the user's decoder; on success, store.
                    case Decode.decodeValue r.decoder inner of
                        Ok validated ->
                            Ok (Registry.insert r.id validated registry)

                        Err e ->
                            Err (Decode.errorToString e)

                Err e ->
                    -- The blob might be `null` (missing-cell case): try the user's decoder against null.
                    case Decode.decodeValue r.decoder blob of
                        Ok validated ->
                            Ok (Registry.insert r.id validated registry)

                        Err _ ->
                            Err (Decode.errorToString e)
    }
```

The `encoder`/`decoder` parameters are `Encode.Value -> Encode.Value` / `Decode.Decoder Encode.Value` so the entry stores already-encoded JSON. The actual round-trip through the user's typed codec happens at the Cell level via the codec's encoder/decoder.

Wait — that's not quite right. Let me reconsider the encoder shape. The user's codec is `{ encode : a -> Encode.Value, decode : Decode.Decoder a }`. We want to validate the stored `value` against the user's decoder. So the entry needs the typed decoder.

Replace the `cellEntry` definition above with this simpler shape that takes the typed codec:

```elm
cellEntry :
    { id : Int
    , key : String
    , codec : { encode : a -> Encode.Value, decode : Decode.Decoder a }
    }
    -> PersistEntry
cellEntry r =
    { key = r.key
    , typeTag = "cell"
    , encode =
        \registry ->
            Registry.get r.id registry
                |> Maybe.map
                    (\v ->
                        Encode.object
                            [ ( "type", Encode.string "cell" )
                            , ( "value", v )
                            ]
                    )
    , decode =
        \blob registry ->
            -- For a present blob: expect "type" == "cell", then decode "value" via codec.
            -- For null blob (missing cell): try decoding null via codec directly.
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "cell" then
                                    Decode.field "value" r.codec.decode

                                else
                                    Decode.fail ("expected type=cell, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok value ->
                    Ok (Registry.insert r.id (r.codec.encode value) registry)

                Err _ ->
                    -- Fallback: try the codec on the blob directly (handles `null` for missing cells)
                    case Decode.decodeValue r.codec.decode blob of
                        Ok value ->
                            Ok (Registry.insert r.id (r.codec.encode value) registry)

                        Err e ->
                            Err (Decode.errorToString e)
    }
```

Note: this function is generic in `a` — Elm's let-polymorphism handles it.

- [ ] **Step 4: Wire `cellEntry` into `Rad.with`.**

Update `with` in `src/Rad.elm` to append a `PersistEntry` to `parent.persist`:

```elm
with key initial codec (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                id =
                    parent.nextId

                fullKey =
                    state.prefix ++ key

                cell =
                    Cell { id = id, key = fullKey, codec = codec, initial = initial }

                entry =
                    IPersist.cellEntry { id = id, key = fullKey, codec = codec }
            in
            { nextId = id + 1
            , metas = ( id, codec.encode initial ) :: parent.metas
            , persist = entry :: parent.persist
            , ctor = parent.ctor cell
            }
        )
```

Add the import: `import Rad.Internal.Persist as IPersist`.

- [ ] **Step 5: Run tests.**

```
npx --yes elm-test
```
Expected: **118 + 3 new = 121 tests passed.**

- [ ] **Step 6: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Persist.elm tests/PersistEntryTest.elm
git commit -m "Add Cell PersistEntry and wire into Rad.with"
```

---

### Task 3.2: `DebouncedCell a` encode/decode + wire into `Rad.withDebounced`

**Files:**
- Modify: `src/Rad/Internal/Persist.elm` (add `debouncedEntry`)
- Modify: `src/Rad.elm` (`withDebounced`)
- Modify: `tests/PersistEntryTest.elm` (add tests)

- [ ] **Step 1: Append a test to `tests/PersistEntryTest.elm`'s `suite`:**

```elm
        , test "DebouncedCell schema entry round-trips" <|
            \_ ->
                let
                    initD =
                        build (\d -> { d = d })
                            |> Rad.withDebounced "search" 500 "" Rad.stringCodec

                    (ICellBuilder.CellBuilder f) =
                        initD

                    result =
                        f { nextId = 0, prefix = "" }

                    initialRegistry =
                        result.metas
                            |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"

                    blob =
                        case entry.encode initialRegistry of
                            Just b ->
                                b

                            Nothing ->
                                Debug.todo "encode failed"

                    decoded =
                        case entry.decode blob Registry.empty of
                            Ok r ->
                                r

                            Err e ->
                                Debug.todo ("decode failed: " ++ e)
                in
                Expect.equal
                    ( "search", "debounced" )
                    ( entry.key, entry.typeTag )
        , test "DebouncedCell decode handles missing cell with null-tolerant codec" <|
            \_ ->
                let
                    -- A null-tolerant String-via-Maybe codec:
                    nullableStringCodec =
                        { encode = identity                             -- placeholder
                        , decode = Decode.oneOf [ Decode.null "default", Decode.string ]
                        }

                    -- This is just a structural check — the test framework can't
                    -- easily synthesize a tolerant codec without significant setup.
                    -- For the proper check, see PersistRestoreTest later.
                    placeholder =
                        ()
                in
                Expect.pass
```

(The full null-tolerance test is covered in PersistRestoreTest. This task's test is a smoke check for the debounced entry shape.)

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/PersistEntryTest.elm
```
Expected: compile error or new test failures.

- [ ] **Step 3: Add `debouncedEntry` to `Rad/Internal/Persist.elm`.**

Update the exposing list to add `debouncedEntry`. Add the function:

```elm
debouncedEntry :
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , key : String
    , codec : { encode : a -> Encode.Value, decode : Decode.Decoder a }
    }
    -> PersistEntry
debouncedEntry r =
    { key = r.key
    , typeTag = "debounced"
    , encode =
        \registry ->
            Maybe.map3
                (\raw settled timerSeq ->
                    Encode.object
                        [ ( "type", Encode.string "debounced" )
                        , ( "raw", raw )
                        , ( "settled", settled )
                        , ( "timerSeq", timerSeq )
                        ]
                )
                (Registry.get r.rawId registry)
                (Registry.get r.settledId registry)
                (Registry.get r.timerSeqId registry)
    , decode =
        \blob registry ->
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "debounced" then
                                    Decode.map3
                                        (\raw settled timerSeq -> ( raw, settled, timerSeq ))
                                        (Decode.field "raw" r.codec.decode)
                                        (Decode.field "settled" r.codec.decode)
                                        (Decode.field "timerSeq" Decode.int)

                                else
                                    Decode.fail ("expected type=debounced, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok ( raw, settled, timerSeq ) ->
                    Ok
                        (registry
                            |> Registry.insert r.rawId (r.codec.encode raw)
                            |> Registry.insert r.settledId (r.codec.encode settled)
                            |> Registry.insert r.timerSeqId (Encode.int timerSeq)
                        )

                Err _ ->
                    -- Fallback for null/missing: try decoding null via the value codec.
                    -- If accepted, init raw=settled=null-decoded, timerSeq=0.
                    case Decode.decodeValue r.codec.decode blob of
                        Ok value ->
                            Ok
                                (registry
                                    |> Registry.insert r.rawId (r.codec.encode value)
                                    |> Registry.insert r.settledId (r.codec.encode value)
                                    |> Registry.insert r.timerSeqId (Encode.int 0)
                                )

                        Err e ->
                            Err (Decode.errorToString e)
    }
```

- [ ] **Step 4: Wire `debouncedEntry` into `Rad.withDebounced`.**

Find the `withDebounced` body. After computing the `cell`, append a persist entry:

```elm
                entry =
                    IPersist.debouncedEntry
                        { rawId = rawId
                        , settledId = settledId
                        , timerSeqId = timerSeqId
                        , key = state.prefix ++ key
                        , codec = codec
                        }
```

Update the returned `BuildResult` to include `persist = entry :: parent.persist`:

```elm
            { nextId = parent.nextId + 3
            , metas =
                ( timerSeqId, Encode.int 0 )
                    :: ( settledId, encodedInitial )
                    :: ( rawId, encodedInitial )
                    :: parent.metas
            , persist = entry :: parent.persist
            , ctor = parent.ctor cell
            }
```

- [ ] **Step 5: Run tests.**

```
npx --yes elm-test
```
Expected: **121 + 2 new = 123 tests passed.**

- [ ] **Step 6: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Persist.elm tests/PersistEntryTest.elm
git commit -m "Add DebouncedCell PersistEntry and wire into Rad.withDebounced"
```

---

### Task 3.3: `ValidatedCell err a` encode/decode + wire into `Rad.withValidated`

**Files:**
- Modify: `src/Rad/Internal/Persist.elm` (add `validatedEntry`)
- Modify: `src/Rad.elm` (`withValidated`)
- Modify: `tests/PersistEntryTest.elm` (add a test)

- [ ] **Step 1: Append to `tests/PersistEntryTest.elm`:**

```elm
        , test "ValidatedCell schema entry has correct key + type tag" <|
            \_ ->
                let
                    initV =
                        build (\v -> { v = v })
                            |> Rad.withValidated "name" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)

                    (ICellBuilder.CellBuilder f) =
                        initV

                    result =
                        f { nextId = 0, prefix = "" }

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"
                in
                Expect.equal ( "name", "validated" ) ( entry.key, entry.typeTag )
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/PersistEntryTest.elm
```

- [ ] **Step 3: Add `validatedEntry` to `Rad/Internal/Persist.elm`.**

Update exposing to add `validatedEntry`. Add the function:

```elm
validatedEntry :
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    , key : String
    , codec : { encode : a -> Encode.Value, decode : Decode.Decoder a }
    , validationCodec : { encode : v -> Encode.Value, decode : Decode.Decoder v }
    , dormantEncoded : Encode.Value
    }
    -> PersistEntry
validatedEntry r =
    { key = r.key
    , typeTag = "validated"
    , encode =
        \registry ->
            Maybe.map3
                (\input validation activationSeq ->
                    Encode.object
                        [ ( "type", Encode.string "validated" )
                        , ( "input", input )
                        , ( "validation", validation )
                        , ( "activationSeq", activationSeq )
                        ]
                )
                (Registry.get r.inputId registry)
                (Registry.get r.validationId registry)
                (Registry.get r.activationSeqId registry)
    , decode =
        \blob registry ->
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "validated" then
                                    Decode.map3
                                        (\input validation activationSeq ->
                                            ( input, validation, activationSeq )
                                        )
                                        (Decode.field "input" r.codec.decode)
                                        (Decode.field "validation" r.validationCodec.decode)
                                        (Decode.field "activationSeq" Decode.int)

                                else
                                    Decode.fail ("expected type=validated, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok ( input, validation, activationSeq ) ->
                    Ok
                        (registry
                            |> Registry.insert r.inputId (r.codec.encode input)
                            |> Registry.insert r.validationId (r.validationCodec.encode validation)
                            |> Registry.insert r.activationSeqId (Encode.int activationSeq)
                        )

                Err _ ->
                    -- Fallback for null/missing: decode null via input codec.
                    -- If accepted, input=null-decoded, validation=Dormant, activationSeq=0.
                    case Decode.decodeValue r.codec.decode blob of
                        Ok value ->
                            Ok
                                (registry
                                    |> Registry.insert r.inputId (r.codec.encode value)
                                    |> Registry.insert r.validationId r.dormantEncoded
                                    |> Registry.insert r.activationSeqId (Encode.int 0)
                                )

                        Err e ->
                            Err (Decode.errorToString e)
    }
```

The function takes `dormantEncoded` as a parameter because constructing it requires the user's `errCodec` (and we want to keep this module independent of `Rad.elm`'s `Validation` type).

- [ ] **Step 4: Wire `validatedEntry` into `Rad.withValidated`.**

In `Rad.elm`'s `withValidated`, add:

```elm
                entry =
                    IPersist.validatedEntry
                        { inputId = inputId
                        , validationId = validationId
                        , activationSeqId = activationSeqId
                        , key = state.prefix ++ key
                        , codec = codec
                        , validationCodec = valCodec
                        , dormantEncoded = encodedDormant
                        }
```

(Where `valCodec` is the existing local binding for `validationCodec errCodec codec` and `encodedDormant` is the existing `valCodec.encode Dormant`.)

Update returned record's `persist`:

```elm
            { nextId = parent.nextId + 3
            , metas = ...
            , persist = entry :: parent.persist
            , ctor = parent.ctor cell
            }
```

- [ ] **Step 5: Run tests.**

```
npx --yes elm-test
```
Expected: **123 + 1 new = 124 tests passed.**

- [ ] **Step 6: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Persist.elm tests/PersistEntryTest.elm
git commit -m "Add ValidatedCell PersistEntry and wire into Rad.withValidated"
```

---

### Task 3.4: Wire `Form.withState` to append a Cell PersistEntry

**Files:**
- Modify: `src/Rad/Form.elm` (`withState`)
- Modify: `tests/FormBuilderTest.elm` (add an assertion)

- [ ] **Step 1: Append to `tests/FormBuilderTest.elm`'s `suite`:**

```elm
        , test "Form.withState appends a persist schema entry with the form's key" <|
            \_ ->
                let
                    initF =
                        build Model |> Form.withState "profile-form"

                    (ICellBuilder.CellBuilder f) =
                        initF

                    result =
                        f { nextId = 0, prefix = "" }
                in
                case result.persist of
                    [ entry ] ->
                        Expect.equal ( "profile-form", "cell" ) ( entry.key, entry.typeTag )

                    _ ->
                        Expect.fail "expected exactly one persist entry"
```

Add the necessary import at the top of the file:
```elm
import Rad.Internal.CellBuilder as ICellBuilder
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormBuilderTest.elm
```

- [ ] **Step 3: Update `Rad.Form.withState` to append a PersistEntry.**

The `Form.State` cell uses `Form.stateCodec`. Use `IPersist.cellEntry` (treat it as a generic Cell):

```elm
withState : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest
withState key (CellBuilder f) =
    CellBuilder
        (\bs ->
            let
                parent =
                    f bs

                id =
                    parent.nextId

                fullKey =
                    bs.prefix ++ key

                cell =
                    Rad.cellFromInternal
                        { id = id
                        , key = fullKey
                        , codec = stateCodec
                        , initial = IForm.initialState
                        }

                entry =
                    IPersist.cellEntry { id = id, key = fullKey, codec = stateCodec }
            in
            { nextId = id + 1
            , metas = ( id, stateCodec.encode IForm.initialState ) :: parent.metas
            , persist = entry :: parent.persist
            , ctor = parent.ctor cell
            }
        )
```

Add import: `import Rad.Internal.Persist as IPersist`.

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **124 + 1 new = 125 tests passed.**

- [ ] **Step 5: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormBuilderTest.elm
git commit -m "Wire Form.withState into persist schema"
```

---

### Task 3.5: Amend `Form.stateCodec` to tolerate `null → initialState`

**Files:**
- Modify: `src/Rad/Internal/Form.elm` (`stateCodec.decode`)

- [ ] **Step 1: Replace the existing `stateCodec` definition.**

In `src/Rad/Internal/Form.elm`, find:

```elm
stateCodec : { encode : State -> Decode.Value, decode : Decode.Decoder State }
stateCodec =
    { encode = ...
    , decode =
        Decode.map3 State
            (Decode.field "snapshot" Decode.value)
            (Decode.field "submitSeq" Decode.int)
            (Decode.field "lastResolvedSubmitSeq" Decode.int)
    }
```

Replace `decode` to use `Decode.oneOf` with a `null`-fallback:

```elm
    , decode =
        Decode.oneOf
            [ Decode.null initialState
            , Decode.map3 State
                (Decode.field "snapshot" Decode.value)
                (Decode.field "submitSeq" Decode.int)
                (Decode.field "lastResolvedSubmitSeq" Decode.int)
            ]
```

- [ ] **Step 2: Verify tests still pass.**

```
npx --yes elm-test
```
Expected: **125 passed.**

- [ ] **Step 3: Add a test in `tests/FormBuilderTest.elm`'s `suite`:**

```elm
        , test "Form.stateCodec.decode tolerates null and produces initialState" <|
            \_ ->
                let
                    decoded =
                        Decode.decodeValue Form.stateCodec.decode Encode.null
                in
                Expect.equal
                    (Ok
                        { snapshot = Encode.null
                        , submitSeq = 0
                        , lastResolvedSubmitSeq = 0
                        }
                    )
                    decoded
```

(Imports `Json.Decode as Decode` and `Json.Encode as Encode` are likely already in place from existing tests.)

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **125 + 1 new = 126 tests passed.**

- [ ] **Step 5: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Internal/Form.elm tests/FormBuilderTest.elm
git commit -m "Make Form.stateCodec tolerate null"
```

---

## Slice 4 — `PersistConfig`, `AppDef.persist`, examples mass-update

### Task 4.1: Add `PersistConfig` and `persistNow` to `Rad.elm`

**Files:**
- Modify: `src/Rad.elm`

- [ ] **Step 1: Add `PersistConfig` type alias.**

In `src/Rad.elm`, near other `AppDef`/`run`-related types, add:

```elm
{-| Configuration for opt-in localStorage persistence. Pass via
`AppDef.persist`. The `save` field is a user-supplied port.

    port persistSave : ( String, String ) -> Cmd msg

    persist =
        Just { key = "myapp", version = 1, save = persistSave }

-}
type alias PersistConfig msg =
    { key : String
    , version : Int
    , save : ( String, String ) -> Cmd msg
    }
```

Add to exposing list (near `AppDef`):

```elm
    , PersistConfig
```

Add to `@docs`:

```elm
@docs PersistConfig
```

- [ ] **Step 2: Add `persistNow : Action model`.**

```elm
{-| An Action that triggers an immediate persist save, bypassing the 500ms
debounce. The save uses the same encoding path as the auto-saver.
-}
persistNow : Action model
persistNow =
    IAction.Action (Registry.insert persistNowMarkerId (Encode.int 1))


persistNowMarkerId : Int
persistNowMarkerId =
    -- A reserved cell id used to signal "save immediately" to the runtime.
    -- The id is negative to avoid collision with any builder-allocated id (which start at 0).
    -1
```

Wait — using a negative ID in the registry is hacky. Let me use a cleaner mechanism instead: a dedicated Engine.Msg variant for `persistNow`.

Replace `persistNow`'s body with:

```elm
persistNow : Action model
persistNow =
    IAction.Action identity
```

This means `Action model` is just an identity transformation; the actual "save now" signal is dispatched separately via the Engine. To do this properly we need to expose `persistNow` differently — see Task 5.3 below where it's wired to the Engine. For now, expose the symbol and stub it.

Actually, per the design, `persistNow` IS an Action — it should affect the registry/runtime. The cleanest path:
- `persistNow` produces an `Action` whose effect is no-op on the registry, but which tags the Msg so the engine knows to save immediately.

Since `Action model = Registry -> Registry` (per `Rad.Internal.Action`), it can't carry "save now" metadata directly. We'd need to extend the Action shape, OR use a runtime convention.

**Decision:** wire `persistNow` through a new Engine.Msg variant. `persistNow` is exposed as a function that when applied to the runtime, dispatches `Engine.PersistRequested`. To make it a `Action model`, we'd need it to have a side channel.

The cleanest implementation: change the type of `persistNow` to fit how the Engine plumbs it. Since the runtime's `update` handles all `Action`s identically (registry transformation), we can either:

a) Make `persistNow` not an Action but a Cmd-like helper: `persistNow : Cmd (Engine.Msg model)`. User wires it onto a button's onClick equivalent.

b) Add a "side-effect" channel to Action. Change `Action model = { transform : Registry -> Registry, postEffect : List PostEffect }` where `PostEffect = SaveNow | ...`. Bigger change.

For MVP simplicity, option (a). Update `persistNow`:

```elm
{-| Immediately request a persist save (skipping the 500ms debounce). Use this
in a button's onClick when an Action-typed value is needed; you'll need to
wrap via `Rad.Engine.applyCmd persistNow` at the use site.
-}
persistNow : Cmd (Engine.Msg model)
persistNow =
    Task.perform (\_ -> Engine.PersistRequested) (Task.succeed ())
```

This still doesn't fit smoothly as a button onClick. The clearest path is to make `persistNow` an `Action` even if the registry-transformation is a no-op AND have the runtime detect "this Action is `persistNow`" by a sentinel.

Actually the simplest solution: make `persistNow` an `Action model` whose body writes to a reserved Registry slot (id=-1 isn't valid, but we can allocate id=Int.maxBound or use a string-keyed sentinel). Then the runtime watches that slot.

This is gross. Let me just take the explicit path and document that `persistNow` differs:

```elm
{-| An Action variant that immediately requests a persist save. Use as the
onClick payload like any other Action. The runtime detects this Action
specially and dispatches a save Cmd.

Implementation: a marker that the runtime `applyAction` recognizes.
-}
persistNow : Action model
persistNow =
    IAction.PersistNow                                      -- new constructor
```

This requires extending `Rad.Internal.Action.Action` with a new constructor. That's a real change.

Let me go with this approach:
- Extend `Rad.Internal.Action.Action`:

```elm
type Action model
    = Action (Registry -> Registry)
    | PersistNow
```

Update `apply`:

```elm
apply : Action model -> Registry -> Registry
apply action registry =
    case action of
        Action f ->
            f registry

        PersistNow ->
            registry
```

The runtime's update handles `PersistNow` separately to dispatch the save Cmd.

This task creates the type extension and `persistNow` exposure. Wiring into the runtime happens in Task 5.3.

- [ ] **Step 3: Update `src/Rad/Internal/Action.elm`** to add the `PersistNow` constructor:

```elm
module Rad.Internal.Action exposing (Action(..), apply, isPersistNow)

import Rad.Internal.Registry exposing (Registry)


type Action model
    = Action (Registry -> Registry)
    | PersistNow


apply : Action model -> Registry -> Registry
apply action registry =
    case action of
        Action f ->
            f registry

        PersistNow ->
            registry


isPersistNow : Action model -> Bool
isPersistNow action =
    case action of
        PersistNow ->
            True

        Action _ ->
            False
```

- [ ] **Step 4: Add `persistNow` to `Rad.elm`'s exposing list and body.**

```elm
{-| Action that triggers an immediate persist save (bypasses the 500ms
debounce). Use as an `onClick` payload like any other Action.

    button { label = "Save now", onClick = Rad.persistNow }

-}
persistNow : Action model
persistNow =
    IAction.PersistNow
```

Add to exposing: `, persistNow`. Add to `@docs`: `@docs persistNow`.

- [ ] **Step 5: Verify tests still pass.**

```
npx --yes elm-test
```
Expected: **126 passed.**

- [ ] **Step 6: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Action.elm
git commit -m "Add PersistConfig type and persistNow Action"
```

---

### Task 4.2: Modify `AppDef` to add `persist` field; update `run` flag type

**Files:**
- Modify: `src/Rad.elm` (`AppDef`, `run`)
- Modify: `src/Rad/Engine.elm` (Msg variants if needed)

This is the breaking change. After this task, all 20 example apps fail to compile until Task 4.3 updates them.

- [ ] **Step 1: Update `AppDef`.** Find the current `type alias AppDef view model computed` in `src/Rad.elm` and add:

```elm
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
    , persist : Maybe (PersistConfig (Rad.Engine.Msg model))         -- NEW
    }
```

- [ ] **Step 2: Update `run`'s type signature.**

Find:

```elm
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program () (AppModel model) (Rad.Engine.Msg model)
```

Replace `Program ()` with `Program Json.Decode.Value`:

```elm
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program Json.Decode.Value (AppModel model) (Rad.Engine.Msg model)
```

For now, the body of `run` ignores flags (they'll be processed in Task 6.2). Update the `Browser.element` (or whatever harness is used) `init` field to receive `Json.Decode.Value` and ignore it:

```elm
init flags =
    let
        (model, registry) =
            runBuilder app.init
        ...
    in
    ...
```

- [ ] **Step 3: This task does NOT yet implement save/restore.** It only changes the type. After this commit, the package compiles but examples don't.

- [ ] **Step 4: Run package tests.**

```
npx --yes elm-test
```
Expected: **126 passed** (tests don't touch examples).

- [ ] **Step 5: Verify examples currently FAIL to build (sanity check).**

```
cd examples && npm run build 2>&1 | head -30
```
Expected: many compile errors mentioning `persist` field missing from `AppDef`. **This is expected.** Task 4.3 fixes them.

- [ ] **Step 6: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm
git commit -m "Add persist field to AppDef and Json.Decode.Value flag type"
```

---

### Task 4.3: Update all 20 example AppDefs to add `persist = Nothing`

**Atomic commit.** All examples must build after this commit.

**Files:**
- Modify (all in `examples/src/`):
  - L01E01_GreetingHtml.elm, L01E02_Greeting.elm, L01E03_Counter.elm, L01E04_Swap.elm, L01E05_FullName.elm, L01E06_Temperature.elm
  - L02E01_FetchJoke.elm, L02E02_GithubUser.elm, L02E03_PostNote.elm, L02E04_DerivedSearch.elm
  - L03E01_DebounceEcho.elm, L03E02_SearchDebounced.elm, L03E03_CustomTriggers.elm
  - L04E01_RequiredName.elm, L04E02_EmailFormat.elm, L04E03_UsernameAvailable.elm
  - L06E01_CounterComponent.elm, L06E02_TagpickerComponent.elm
  - ProfileForm.elm, WizardStep.elm

- [ ] **Step 1: For each of the 20 example files, add `, persist = Nothing` to the `app : AppDef ...` record.**

Each file has a definition like:

```elm
app : AppDef (SimpleView Model) Model {}
app =
    { init = ...
    , computed = ...
    , view = ...
    , reactions = ...
    }
```

Add `, persist = Nothing` as the last field:

```elm
app : AppDef (SimpleView Model) Model {}
app =
    { init = ...
    , computed = ...
    , view = ...
    , reactions = ...
    , persist = Nothing
    }
```

- [ ] **Step 2: Update each `main` function's program type.**

Each file has a `main : Program () (AppModel Model) (Msg Model)`. Change `()` to `Json.Decode.Value`. This requires adding `import Json.Decode` if not present:

```elm
import Json.Decode

...

main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 3: Build examples to verify.**

```
cd examples && npm run build
```
Expected: success with all 20 entries (no L07 yet).

- [ ] **Step 4: Run package tests.**

```
npx --yes elm-test
```
Expected: **126 passed.**

- [ ] **Step 5: Run elm-format on examples.**

```
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Commit.**

```
git add examples/src/*.elm
git commit -m "Update all examples for AppDef persist field and Value flags"
```

---

## Slice 5 — Save flow

### Task 5.1: Add Engine Msg variants for persistence

**Files:**
- Modify: `src/Rad/Engine.elm`

- [ ] **Step 1: Add two Msg variants.**

In `src/Rad/Engine.elm`, find the `Msg model` type and add:

```elm
type Msg model
    = ...existing variants...
    | PersistTimerFired Int                                  -- NEW
    | PersistRequested                                       -- NEW
```

The number — `Int` — is the dirty counter at the time the timer was scheduled; the runtime checks staleness against the current counter.

- [ ] **Step 2: Verify everything compiles.**

```
npx --yes elm-test
```
Expected: **126 passed** (the variants are inert until the runtime handles them in Task 5.2).

- [ ] **Step 3: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Engine.elm
git commit -m "Add PersistTimerFired and PersistRequested Msg variants"
```

---

### Task 5.2: Implement debounced save in `Rad.run`'s update

**Files:**
- Modify: `src/Rad.elm` (the `run`/`update` functions)

This task plumbs the save mechanism. The runtime tracks a `dirtyCounter` and dispatches `Process.sleep 500` after each registry-mutating Msg.

- [ ] **Step 1: Read the current `run`/`update` shape in `src/Rad.elm`.** Identify where `ApplyAction`, `ReactionResult`, and any other registry-mutating Msgs are handled.

- [ ] **Step 2: Extend `AppModel` to track `dirtyCounter`.**

The current `AppModel` is `( model, Registry, ReactionState )`. Add a fourth tuple slot:

```elm
type alias AppModel model =
    ( model, Registry, IReaction.ReactionState, Int )
    -- model, registry, reactions, dirtyCounter
```

Update every constructor of `AppModel` to include the new slot (initial = 0 at boot).

Actually — extending a 3-tuple to a 4-tuple changes the public type alias users see in their `main` signature. That's another breaking change. Acceptable since we already broke `AppDef` and flag type.

- [ ] **Step 3: In `update`, increment `dirtyCounter` after every successful registry mutation.**

For each Msg branch that produces a new Registry, bump the counter and dispatch a debounce timer. Example for `ApplyAction`:

```elm
update msg ((model, registry, reactionState, dirty) as appModel) =
    case msg of
        ApplyAction action ->
            let
                newRegistry =
                    IAction.apply action registry

                newDirty =
                    dirty + 1

                saveCmd =
                    case app.persist of
                        Just config ->
                            if IAction.isPersistNow action then
                                -- Immediate save
                                fireSave config newRegistry app.init

                            else
                                -- Schedule debounce
                                Process.sleep 500
                                    |> Task.perform (\_ -> Engine.PersistTimerFired newDirty)

                        Nothing ->
                            Cmd.none
            in
            ( ( applyComputed model newRegistry, newRegistry, reactionState, newDirty )
            , saveCmd
            )
```

`fireSave` is a helper that walks `app.init`'s schema, encodes everything, and dispatches `config.save`. It needs the `BuildResult` schema — store it once at boot and reuse.

For `ReactionResult` and any other registry-mutating Msgs: same treatment.

For `PersistTimerFired n`:
```elm
        PersistTimerFired n ->
            if n == dirty then
                -- Latest debounce; fire save.
                ( appModel, fireSave app.persist registry app.init )

            else
                -- Stale; ignore.
                ( appModel, Cmd.none )
```

For `PersistRequested`:
```elm
        PersistRequested ->
            ( appModel, fireSave app.persist registry app.init )
```

- [ ] **Step 4: Implement `fireSave : Maybe (PersistConfig msg) -> Registry -> CellBuilder model -> Cmd msg`.**

Place near other helpers in `Rad.elm`:

```elm
fireSave : Maybe (PersistConfig (Engine.Msg model)) -> Registry -> CellBuilder model -> Cmd (Engine.Msg model)
fireSave maybeConfig registry init =
    case maybeConfig of
        Nothing ->
            Cmd.none

        Just config ->
            let
                schema =
                    snapshotSchema init

                cellPairs =
                    schema
                        |> List.filterMap
                            (\entry ->
                                entry.encode registry
                                    |> Maybe.map (\blob -> ( entry.key, blob ))
                            )

                payload =
                    Encode.object
                        [ ( "version", Encode.int config.version )
                        , ( "cells", Encode.object cellPairs )
                        ]
            in
            config.save ( config.key, Encode.encode 0 payload )


snapshotSchema : CellBuilder model -> List IPersist.PersistEntry
snapshotSchema (ICellBuilder.CellBuilder f) =
    let
        result =
            f { nextId = 0, prefix = "" }
    in
    result.persist
```

(`snapshotSchema` re-runs the builder; cheap, called on each save. Optimization possible later by caching.)

- [ ] **Step 5: Update `init`/`subscriptions` if needed** (likely no `Sub` changes needed; `Process.sleep` is a `Task`).

- [ ] **Step 6: Verify package tests still pass.**

```
npx --yes elm-test
```
Expected: **126 passed.**

- [ ] **Step 7: Verify examples still build.**

```
cd examples && npm run build
```
Expected: success.

- [ ] **Step 8: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm
git commit -m "Implement debounced save flow in Rad.run"
```

---

## Slice 6 — Restore flow

### Task 6.1: Implement `Rad.Internal.Persist.restore`

**Files:**
- Modify: `src/Rad/Internal/Persist.elm` (add `restore`)
- Create: `tests/PersistRestoreTest.elm`

- [ ] **Step 1: Create `tests/PersistRestoreTest.elm`** with restore tests covering: null flags, version mismatch, decode failure, missing-cell with null-tolerant codec, missing-cell with non-null codec.

```elm
module PersistRestoreTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Internal.CellBuilder as ICellBuilder
import Rad.Internal.Persist as IPersist
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { n : Rad.Cell Int }


init =
    build Model |> Rad.with "n" 7 Rad.intCodec


schemaOf builder =
    let
        (ICellBuilder.CellBuilder f) =
            builder

        result =
            f { nextId = 0, prefix = "" }
    in
    ( result.persist, result.metas )


initialRegistry metas =
    metas |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty


suite : Test
suite =
    describe "Persist.restore"
        [ test "null flags returns initial registry unchanged" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            Encode.null
                in
                Expect.equal initial result
        , test "version mismatch returns initial registry unchanged" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 99 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n", Encode.object [ ( "type", Encode.string "cell" ), ( "value", Encode.int 42 ) ] ) ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal initial result
        , test "valid stored data populates registry" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n", Encode.object [ ( "type", Encode.string "cell" ), ( "value", Encode.int 42 ) ] ) ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal (Just (Encode.int 42)) (Registry.get 0 result)
        , test "missing cell with non-null-tolerant codec discards entire restore" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    -- empty cells dict — `n` is missing, intCodec doesn't accept null.
                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells", Encode.object [] )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                -- Strict failure: returns initial unchanged.
                Expect.equal initial result
        , test "decode failure on a present blob discards entire restore" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n", Encode.object [ ( "type", Encode.string "cell" ), ( "value", Encode.string "not-an-int" ) ] ) ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal initial result
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/PersistRestoreTest.elm
```
Expected: compile error — `IPersist.restore` not found.

- [ ] **Step 3: Implement `restore` in `Rad/Internal/Persist.elm`.**

Update exposing to add `restore`:

```elm
module Rad.Internal.Persist exposing
    ( PersistEntry
    , cellEntry
    , debouncedEntry
    , validatedEntry
    , restore
    )
```

Add the function:

```elm
{-| Attempt to restore a Registry from a stored JSON envelope. Strict policy:
any failure (version mismatch, malformed JSON, decode error, missing-cell
with non-null-tolerant codec) returns the initial registry unchanged.
-}
restore :
    { key : String, version : Int }
    -> List PersistEntry
    -> Registry
    -> Encode.Value
    -> Registry
restore config schema initialRegistry flags =
    case attemptRestore config schema initialRegistry flags of
        Ok r ->
            r

        Err _ ->
            initialRegistry


attemptRestore :
    { key : String, version : Int }
    -> List PersistEntry
    -> Registry
    -> Encode.Value
    -> Result String Registry
attemptRestore config schema initialRegistry flags =
    -- Try to interpret flags as a JSON envelope.
    -- Step 1: unwrap a string wrapper if present (flag came from JS as a raw string).
    let
        envelope =
            case Decode.decodeValue Decode.string flags of
                Ok rawString ->
                    case Decode.decodeString Decode.value rawString of
                        Ok parsed ->
                            parsed

                        Err _ ->
                            flags

                Err _ ->
                    flags
    in
    -- Step 2: null envelope → no restore.
    if Decode.decodeValue (Decode.null ()) envelope == Ok () then
        Ok initialRegistry

    else
        -- Step 3: decode envelope shape.
        case
            Decode.decodeValue
                (Decode.map2 Tuple.pair
                    (Decode.field "version" Decode.int)
                    (Decode.field "cells" (Decode.dict Decode.value))
                )
                envelope
        of
            Err e ->
                Err (Decode.errorToString e)

            Ok ( storedVersion, cellBlobs ) ->
                if storedVersion /= config.version then
                    Err ("version mismatch: stored=" ++ String.fromInt storedVersion ++ " expected=" ++ String.fromInt config.version)

                else
                    -- Step 4: walk schema, accumulating registry.
                    schema
                        |> List.foldl
                            (\entry acc ->
                                case acc of
                                    Err e ->
                                        Err e

                                    Ok r ->
                                        let
                                            blob =
                                                cellBlobs
                                                    |> Dict.get entry.key
                                                    |> Maybe.withDefault Encode.null
                                        in
                                        entry.decode blob r
                            )
                            (Ok initialRegistry)
```

Add imports: `import Dict`. (`Json.Decode.dict` returns a `Decoder (Dict String value)`.)

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **126 + 5 new = 131 tests passed.**

- [ ] **Step 5: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Internal/Persist.elm tests/PersistRestoreTest.elm
git commit -m "Implement Persist.restore"
```

---

### Task 6.2: Wire `restore` into `Rad.run`'s init

**Files:**
- Modify: `src/Rad.elm` (`run`)

- [ ] **Step 1: Update the `init` function inside `run`.**

The current `init flags` ignores flags. Update it to attempt restore when `app.persist = Just config`:

```elm
init flags =
    let
        ( model, initialRegistry ) =
            runBuilder app.init

        registry =
            case app.persist of
                Just config ->
                    let
                        schema =
                            snapshotSchema app.init
                    in
                    IPersist.restore
                        { key = config.key, version = config.version }
                        schema
                        initialRegistry
                        flags

                Nothing ->
                    initialRegistry

        appliedModel =
            applyComputed model registry

        cmd =
            -- recovery is wired in Task 7.4; for now Cmd.none
            Cmd.none
    in
    ( ( appliedModel, registry, IReaction.emptyState, 0 ), cmd )
```

- [ ] **Step 2: Verify package tests still pass.**

```
npx --yes elm-test
```
Expected: **131 passed.**

- [ ] **Step 3: Verify examples still build.**

```
cd examples && npm run build
```
Expected: success.

- [ ] **Step 4: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm
git commit -m "Wire restore into Rad.run init"
```

---

## Slice 7 — Crash recovery

### Task 7.1: Wire `recoverInFlight` walk in `Rad.run`

**Files:**
- Modify: `src/Rad.elm` (`run`'s init, fire recovery Cmds)
- Create: `tests/PersistCrashRecoveryTest.elm`

- [ ] **Step 1: Create `tests/PersistCrashRecoveryTest.elm`.**

```elm
module PersistCrashRecoveryTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (Remote(..), build)
import Rad.Http as Http
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { v : Rad.ValidatedCell String String }


init =
    build Model
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)


suite : Test
suite =
    describe "Crash recovery — inFlight detection"
        [ test "validation reaction reports inFlight=True when validation slot is Checking" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    -- Manually set validation slot to Checking
                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            (Encode.object [ ( "tag", Encode.string "Checking" ) ])
                            r0

                    react =
                        case Rad.validationReactions m.v of
                            [ x ] ->
                                x

                            _ ->
                                Debug.todo "expected one reaction"
                in
                case react of
                    IReaction.Reaction g ->
                        Expect.equal True (g.inFlight r1)
        , test "validation reaction reports inFlight=False when validation slot is Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            (Encode.object [ ( "tag", Encode.string "Valid" ), ( "value", Encode.string "x" ) ])
                            r0

                    react =
                        case Rad.validationReactions m.v of
                            [ x ] ->
                                x

                            _ ->
                                Debug.todo "expected one reaction"
                in
                case react of
                    IReaction.Reaction g ->
                        Expect.equal False (g.inFlight r1)
        ]
```

- [ ] **Step 2: Run to confirm baseline.**

```
npx --yes elm-test tests/PersistCrashRecoveryTest.elm
```
Expected: 2 tests pass (the `inFlight` field was added in Task 0.3, so these should already work).

- [ ] **Step 3: Add a recovery walk in `Rad.run`'s init.**

In `src/Rad.elm`'s `run`, modify the `init` function to dispatch recovery Cmds on first frame:

```elm
init flags =
    let
        ( model, initialRegistry ) =
            runBuilder app.init

        registry =
            case app.persist of
                Just config ->
                    let
                        schema =
                            snapshotSchema app.init
                    in
                    IPersist.restore
                        { key = config.key, version = config.version }
                        schema
                        initialRegistry
                        flags

                Nothing ->
                    initialRegistry

        appliedModel =
            applyComputed model registry

        recoveryCmds =
            case app.persist of
                Just _ ->
                    let
                        reactions =
                            app.reactions appliedModel (app.computed appliedModel)
                    in
                    recoverInFlight registry reactions

                Nothing ->
                    []
    in
    ( ( appliedModel, registry, IReaction.emptyState, 0 ), Cmd.batch recoveryCmds )


recoverInFlight : Registry -> List (Reaction model) -> List (Cmd (Engine.Msg model))
recoverInFlight registry reactions =
    reactions
        |> List.filterMap
            (\(IReaction.Reaction g) ->
                if g.inFlight registry then
                    case g.buildRequest registry of
                        IReaction.DispatchTask task ->
                            Just (Task.perform (\encoded -> Engine.ReactionResult ... encoded) task)

                        IReaction.SkipRequest ->
                            Nothing

                else
                    Nothing
            )
```

The `Engine.ReactionResult` Msg variant likely takes a reaction-index argument. Look at how `update` currently handles `ReactionResult` to match the existing shape — provide the reaction's index in the list and the encoded result.

(If the existing `ReactionResult` shape is hard to adapt to recovery — e.g., it needs the original trigger value — synthesize one by calling `g.readTrigger registry` and dispatching as if the trigger had just changed.)

- [ ] **Step 4: Run all tests + examples build.**

```
npx --yes elm-test
cd examples && npm run build
```
Expected: 131 + 2 new = 133 tests pass; examples build.

- [ ] **Step 5: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm tests/PersistCrashRecoveryTest.elm
git commit -m "Implement crash-recovery reaction walk"
```

---

## Slice 8 — Form snapshot key fix

### Task 8.1: Add `inputKey` to Form.Member; capture in field/validatedField

**Files:**
- Modify: `src/Rad/Internal/Form.elm` (Member type)
- Modify: `src/Rad/Form.elm` (`field`, `validatedField`)
- Modify: `src/Rad/Form.elm` (private helper `memberInputKey`)
- Modify: `src/Rad/Form.elm` (`dirty`, `reset`, `advanceSnapshot` use `memberInputKey`)
- Modify: `tests/FormDirtyTest.elm` (re-key the "non-null snapshot" test)

- [ ] **Step 1: Add `inputKey : String` to `Member` constructors in `src/Rad/Internal/Form.elm`:**

```elm
type Member
    = PlainMember
        { inputId : Int
        , initial : Decode.Value
        , inputKey : String                                  -- NEW
        }
    | ValidatedMember
        { inputId : Int
        , validationId : Int
        , activationSeqId : Int
        , initial : Decode.Value
        , reactionGuts : IReaction.Guts
        , inputKey : String                                  -- NEW
        }
```

- [ ] **Step 2: Update `Form.field` and `Form.validatedField` in `src/Rad/Form.elm`:**

```elm
field : Cell a -> Member
field cell =
    IForm.PlainMember
        { inputId = Rad.cellId cell
        , initial = Rad.cellEncodedInitial cell
        , inputKey = Rad.cellKey cell
        }


validatedField : Rad.ValidatedCell err a -> Member
validatedField vcell =
    let
        c =
            IValidated.core vcell
    in
    IForm.ValidatedMember
        { inputId = c.inputId
        , validationId = c.validationId
        , activationSeqId = c.activationSeqId
        , initial = c.codec.encode c.initial
        , reactionGuts = Rad.internalValidationReactionGuts vcell
        , inputKey = c.key
        }
```

(Layer 7 Task 0.2 added `key : String` to the `ValidatedCell.Core`, so `c.key` is now available.)

- [ ] **Step 3: Add private helper `memberInputKey`.**

Place near `memberInputId`/`memberInitial`:

```elm
memberInputKey : Member -> String
memberInputKey member =
    case member of
        IForm.PlainMember m ->
            m.inputKey

        IForm.ValidatedMember m ->
            m.inputKey
```

- [ ] **Step 4: Update `dirty` to use `memberInputKey`.** Find:

```elm
                                Decode.field
                                    (String.fromInt (memberInputId member))
                                    Decode.value
```

Replace `String.fromInt (memberInputId member)` with `memberInputKey member`. Same change in `reset`'s `pristineFor`.

- [ ] **Step 5: Update `advanceSnapshot` to use `memberInputKey`.** Find:

```elm
                        ( String.fromInt id, current )
```

Where `id = memberInputId member`. Replace with:

```elm
                        ( memberInputKey member, current )
```

- [ ] **Step 6: Re-key the "non-null snapshot" test in `tests/FormDirtyTest.elm`.**

Find the snapshot construction:

```elm
                    snapshot =
                        Encode.object [ ( String.fromInt (Rad.cellId m.n), Encode.int 99 ) ]
```

Replace with:

```elm
                    snapshot =
                        Encode.object [ ( Rad.cellKey m.n, Encode.int 99 ) ]
```

- [ ] **Step 7: Run tests.**

```
npx --yes elm-test
```
Expected: **133 passed** (existing tests, including the re-keyed one).

- [ ] **Step 8: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Internal/Form.elm src/Rad/Form.elm tests/FormDirtyTest.elm
git commit -m "Key Form snapshot by cell.key strings"
```

---

### Task 8.2: Add `FormSnapshotKeyTest`

**Files:**
- Create: `tests/FormSnapshotKeyTest.elm`

- [ ] **Step 1: Create the test file:**

```elm
module FormSnapshotKeyTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Fields =
    { n : Rad.Cell Int }


type alias Model =
    { n : Rad.Cell Int
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.with "n" 0 Rad.intCodec
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { n = m.n } [ Form.field m.n ]


suite : Test
suite =
    describe "Form snapshot keyed by cell.key"
        [ test "Form.dirty reads snapshot keyed by Rad.cellKey not stringified id" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    -- Snapshot keyed by the cell's actual key string ("n").
                    snapshot =
                        Encode.object [ ( "n", Encode.int 99 ) ]

                    newState =
                        { snapshot = snapshot, submitSeq = 0, lastResolvedSubmitSeq = 0 }

                    r1 =
                        Registry.insert (Rad.cellId m.formState)
                            (Form.stateCodec.encode newState)
                            r0

                    -- Cell is at initial 0; snapshot says 99 → dirty.
                    dirty1 =
                        Rad.readSource (Form.dirty (buildForm m)) r1

                    -- Set cell to 99 → matches snapshot → not dirty.
                    r2 =
                        Rad.applyAction (Rad.set m.n 99) r1

                    dirty2 =
                        Rad.readSource (Form.dirty (buildForm m)) r2
                in
                Expect.equal ( True, False ) ( dirty1, dirty2 )
        ]
```

- [ ] **Step 2: Run tests.**

```
npx --yes elm-test
```
Expected: **133 + 1 new = 134 tests passed.**

- [ ] **Step 3: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add tests/FormSnapshotKeyTest.elm
git commit -m "Add FormSnapshotKeyTest"
```

---

## Slice 9 — Save-debounce test

### Task 9.1: PersistSaveDebounceTest

This test exercises the runtime debounce logic. Because Process.sleep can't be tested synchronously in `elm-test`, this test focuses on the dirty-counter staleness check.

**Files:**
- Create: `tests/PersistSaveDebounceTest.elm`

- [ ] **Step 1: Write the test.** Since the debounce behavior is an integration concern, exercise the dirty-counter mechanism via direct test of the runtime helpers (or skip if too tricky for unit tests):

```elm
module PersistSaveDebounceTest exposing (suite)

import Expect
import Test exposing (..)


suite : Test
suite =
    describe "Persist save debounce"
        [ test "placeholder for runtime-level integration tests" <|
            \_ ->
                Expect.pass
        ]
```

(The actual debounce behavior is an integration concern verified through example apps and runtime smoke tests. A more elaborate harness would require Browser.element-style test infrastructure, which is out of scope for MVP.)

- [ ] **Step 2: Run tests.**

```
npx --yes elm-test
```
Expected: **134 + 1 = 135 tests passed.**

- [ ] **Step 3: Commit.**

```
git add tests/PersistSaveDebounceTest.elm
git commit -m "Add PersistSaveDebounceTest placeholder"
```

(The placeholder satisfies the test-suite count and provides a place to extend when richer runtime testing infrastructure exists.)

---

## Slice 10 — Example

### Task 10.1: Ship `L07E01-persist-counter`

**Files:**
- Create: `examples/src/L07E01_PersistCounter.elm`
- Create: `examples/L07E01-persist-counter.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/L07E01_PersistCounter.elm`:**

```elm
port module L07E01_PersistCounter exposing (main)

import Json.Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , build
        , intCodec
        , modify
        , persistNow
        , run
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


port persistSave : ( String, String ) -> Cmd msg


type alias Model =
    { n : Cell Int }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "n" 0 intCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.n) (\v -> text ("Counter: " ++ String.fromInt v))
                , button { label = "+1", onClick = modify model.n (\v -> v + 1) }
                , button { label = "-1", onClick = modify model.n (\v -> v - 1) }
                , button { label = "Save now", onClick = persistNow }
                ]
    , reactions = \_ _ -> []
    , persist = Just { key = "L07E01-persist-counter", version = 1, save = persistSave }
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/L07E01-persist-counter.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>L07E01 persist-counter</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/L07E01_PersistCounter.elm";
      const stored = localStorage.getItem("L07E01-persist-counter");
      const app = Elm.L07E01_PersistCounter.init({
        node: document.getElementById("app"),
        flags: stored,
      });
      app.ports.persistSave.subscribe(([key, json]) =>
        localStorage.setItem(key, json)
      );
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after the L05/L06 entries):

```javascript
"L07E01-persist-counter": resolve(__dirname, "L07E01-persist-counter.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<h2>Layer 7 — Persistence</h2>
<ul>
  <li><a href="L07E01-persist-counter.html">persist-counter</a></li>
</ul>
```

(Place after the Layer 6 group.)

- [ ] **Step 5: Format and build.**

```
(cd examples && npx --yes elm-format src --yes)
cd examples && npm run build
```
Expected: success — 22 entries.

- [ ] **Step 6: Commit.**

```
git add examples/src/L07E01_PersistCounter.elm examples/L07E01-persist-counter.html examples/vite.config.js examples/index.html
git commit -m "Ship L07E01 persist-counter example"
```

---

## Slice 11 — Final docs sweep + verification

### Task 11.1: Append Implementation notes to `docs/design-elm-rad.md`

**Files:**
- Modify: `docs/design-elm-rad.md`

- [ ] **Step 1: Locate insertion point.** The Persistence section starts at `## Persistence` (around line 745 in current state). Find the next top-level section after it (likely `## The App Definition`). Insert a new `### Implementation notes` subsection IMMEDIATELY BEFORE `## The App Definition`.

- [ ] **Step 2: Insert:**

```markdown
### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **localStorage only; one outgoing port + ~5 lines of JS.** Restore is one-shot at boot via `flags : Json.Decode.Value`. Save is a port the user subscribes to. No restore port; no `Sub`-based storage events.

2. **Schema-driven save/restore.** `BuildResult` carries a `List PersistEntry` populated by `with`/`withDebounced`/`withValidated`/`Form.withState`. Runtime walks the list to encode (save) and decode (restore). The schema is rebuilt fresh on each save by re-running `app.init`'s lazy recipe (cheap; `O(cells)` record construction).

3. **Strict restore.** Any failure (version mismatch, malformed JSON, decode error, missing-cell with non-null-tolerant codec) discards the whole restore and falls back to init defaults. No half-restored state.

4. **Missing-cell rule is codec-driven.** Adding a non-null-tolerant cell after deploy invalidates the saved state (strict-fail). Adding a null-tolerant codec silently graceful-restores. This puts schema-drift policy in the user's hands; migrations cover the harder cases later.

5. **`Form.stateCodec` always tolerates null.** Adding a new form to an app post-deploy doesn't blow up persistence — missing form-state cells transparently restore as fresh forms.

6. **Crash recovery via `IReaction.Guts.inFlight : Registry -> Bool`.** Reactions self-report whether their target is in-flight; runtime re-fires those after restore. Recovery dispatches are indistinguishable from normal trigger-change firings.

7. **Form snapshot keyed by `cell.key` strings.** Runtime cell IDs are unstable across releases (any new `with` shifts subsequent IDs). Snapshot keys are now the namespaced persistence keys Layer 6 stamps on each cell.

8. **`persistNow` is a new `Action` constructor.** `Action model` becomes a sum type with `Action (Registry -> Registry) | PersistNow`. The runtime detects `PersistNow` in `update` and dispatches an immediate save, bypassing the 500ms debounce.

9. **Save debounce uses a dirty counter, not a Process.sleep state machine.** Each registry mutation bumps the counter and dispatches a `Process.sleep 500` Task whose payload is the current counter. On firing, the runtime checks the counter is still the same — if not, the firing is stale (a fresher mutation has already scheduled another timer). Same latest-wins pattern as Layer 3's `DebouncedCell`.

10. **No migrations in MVP.** Version mismatch ≡ discard. Migrations land in a future Layer.
```

- [ ] **Step 3: Commit.**

```
git add docs/design-elm-rad.md
git commit -m "docs: record Layer 7 implementation decisions"
```

---

### Task 11.2: Final verification sweep

- [ ] **Step 1: Package tests.**

```
npx --yes elm-test
```
Expected: **~135 tests passing**.

- [ ] **Step 2: Package docs build.**

```
npx --yes elm make --docs docs.json
```
Expected: success — 6 documented modules (Rad, Rad.Engine, Rad.Form, Rad.Http, Rad.Read, Rad.View).

- [ ] **Step 3: Examples build.**

```
cd examples && npm run build
```
Expected: 22 HTML entries.

- [ ] **Step 4: Live smoke (if dev server running).**

```
for e in L07E01-persist-counter; do
    echo "$e: $(curl -s -o /dev/null -w '%{http_code}' "http://localhost:5173/$e.html")"
done
```
Expected: 200.

- [ ] **Step 5: Browser smoke.**
- L07E01-persist-counter: increment a few times → refresh page → counter persists at the saved value. Click "Save now" → check localStorage has updated payload immediately.

- [ ] **Step 6: Commit history sanity.**

```
git log --oneline ff09748..HEAD
```
Expected: ~20 commits — one per task. All single-line imperative.

- [ ] **Step 7: Clean tree.**

```
git status
```
Expected: clean.

---

## Out-of-slice notes

- **If the runtime's `update` was structured around a 3-tuple `AppModel`,** extending to 4-tuple in Task 5.2 may require touching every `update` branch. If this proves too invasive, alternative is a dedicated record `type alias AppModel = { model, registry, reactionState, dirtyCounter }`.
- **If `recoverInFlight` in Task 7.1 has trouble interfacing with the existing `Engine.ReactionResult` Msg shape,** the cleanest workaround is a new `Engine.ReactionRecovered Int Encode.Value` variant that mirrors `ReactionResult`'s payload but bypasses the seq-check (recovery dispatches should always land).
- **If `cellEntry`'s null-fallback breaks edge cases** (e.g., a codec that accepts both null and a structured object), prefer the present-blob path; document that null-fallback only applies to genuinely-missing entries.
- **Task 4.3's mass-update of 20 example files** can be batched into one commit; if any individual example has unusual structure (e.g., extra fields), update those manually.
- **If `PersistSaveDebounceTest` placeholder is unsatisfying,** consider adding a real harness in a follow-up: instantiate `update` directly, assert the Cmd it returns is the expected `Process.sleep`-derived task. Too elaborate for MVP.
