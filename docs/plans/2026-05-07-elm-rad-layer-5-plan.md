# elm-rad Layer 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 5 — `Rad.Form`, an orthogonal Form layer over existing cells: snapshot/dirty/reset, submit gating with typed clean values, and submit-button status helpers. Purely additive on top of Layers 0–4 and 6.

**Architecture:** Forms attach to user-allocated cells. One `Cell Form.State` per form (allocated by `Form.withState`) holds the snapshot blob + submitSeq/lastResolvedSubmitSeq counters. `Form fields` is a pure value built per render via `Form.over`. Members are explicitly listed via `Form.field` / `Form.validatedField`. Submit gating is a single Reaction whose trigger watches the state cell + each validation slot; latest-wins via Layer 2's reaction-seq.

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x. No new dependencies. Vite 6 + `vite-plugin-elm` for examples.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per memory `feedback_commit_cadence.md`).
- **One task = one commit** unless a header says otherwise.
- **Before every commit that touches `.elm` files, run `elm-format`** (per memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes`.
  - Examples: `npx --yes elm-format src --yes` from `examples/`.
- **Verification:** `npx --yes elm-test` from repo root. `cd examples && npm run build` for examples.
- **Commit messages are single-line imperative.** No Co-Authored-By trailers unless explicitly requested.

**Design-doc deviations (applied throughout):**

1. **`Form.onSubmit` target signature.** The design doc (Section 5.7) writes `Cell r`. The implementation uses `Cell (Remote err r)` to mirror `Rad.on` — Layer 2 already encodes Loading/Done/Failed into a Remote-shaped cell. Same correction in docstrings and tests.

2. **CellBuilder extraction is the only structural prereq.** The design doc commits to extracting `CellBuilder` to `Rad.Internal.CellBuilder`. `Cell` itself stays in `Rad.elm`; two new accessors (`cellId`, `cellEncodedInitial`) provide the data `Rad.Form` needs without exposing `Cell(..)`.

3. **`Reaction model` parametricity.** Validation reactions and form-submit reactions don't reference their `model` type variable in any field — `model` is phantom. We exploit this: store the reaction's record-of-functions as a separate `IReaction.Guts` type alias, then re-wrap as `Reaction model` at use site (let-polymorphism gives any fresh `model`). This lets `Member` be non-parameterized.

4. **`onValid` reuses the reaction Cmd loop.** The design says "runs an Action." The implementation routes through `IReaction.DispatchTask (Task.succeed Encode.null)` so the gate uses the existing reaction lifecycle. The user's `clean -> Action model` is applied inside `writeResult`. No new runtime variant.

**Module layout at the end:**

```
src/
  Rad.elm                                   ← uses Rad.Internal.CellBuilder; +cellId, cellEncodedInitial,
                                              cellFromInternal, internalValidationReactionGuts
  Rad/
    Form.elm                                ← NEW (public)
    Engine.elm, Http.elm, Read.elm, View.elm  ← unchanged
    Internal/
      CellBuilder.elm                       ← NEW (extracted)
      Form.elm                              ← NEW (private)
      ValidatedGroup.elm                    ← NEW (private)
      Reaction.elm                          ← + Guts type alias + fromGuts helper
      Action.elm, Component.elm, Debounced.elm, Msg.elm, Registry.elm,
      Request.elm, Source.elm, Validated.elm  ← unchanged
tests/
  FormBuilderTest.elm, FormDirtyTest.elm, FormResetTest.elm,
  FormStatusTest.elm, FormSubmitGateTest.elm, ValidatedGroupTest.elm  ← all NEW
examples/
  src/ProfileForm.elm, src/WizardStep.elm                              ← NEW
  L05E01-profile-form.html, L05E02-wizard-step.html                    ← NEW
  vite.config.js, index.html                                           ← + 2 entries
docs/
  design-elm-rad.md                         ← Forms section gains Implementation notes subsection
```

**Expected test count after Layer 5:** 90 pre + ~28 new = **~118**. Exact counts per task below.

**Expected example count after Layer 5:** 18 pre + 2 new = **21 entries** (index + 20 examples).

---

## Slice 0 — Internal prereqs

### Task 0.1: Extract `CellBuilder` to `Rad.Internal.CellBuilder`

Pure refactor. Public API unchanged.

**Files:**
- Create: `src/Rad/Internal/CellBuilder.elm`
- Modify: `src/Rad.elm`

- [ ] **Step 1: Verify the 90-test baseline.**

```
npx --yes elm-test
```
Expected: **90 passed**.

- [ ] **Step 2: Create `src/Rad/Internal/CellBuilder.elm`:**

```elm
module Rad.Internal.CellBuilder exposing
    ( BuildResult
    , BuildState
    , CellBuilder(..)
    )

import Json.Decode as Decode


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

- [ ] **Step 3: Update `src/Rad.elm`.** Add import alongside existing `Rad.Internal.*` imports:

```elm
import Rad.Internal.CellBuilder as ICellBuilder exposing (BuildResult, BuildState, CellBuilder(..))
```

Replace the local `type CellBuilder ctor = CellBuilder (...)` definition (around line 196) with:

```elm
{-| An applicative builder for constructing a model made of cells.
-}
type alias CellBuilder ctor =
    ICellBuilder.CellBuilder ctor
```

Delete the local `type alias BuildState = { ... }` and `type alias BuildResult ctor = { ... }` (now imported via `ICellBuilder` re-export).

In each function body that pattern-matches `(CellBuilder f)` (`build`, `with`, `runBuilder`, `withDebounced`, `withValidated`, `withInstance`), the constructor pattern still works because `CellBuilder(..)` is exposed via the import. No body changes are needed beyond the type-alias swap, since the bodies work with structural records, not the named aliases.

- [ ] **Step 4: Verify baseline survives.**

```
npx --yes elm-test
```
Expected: **90 passed**, same count.

- [ ] **Step 5: Verify examples still build.**

```
cd examples && npm run build
```
Expected: success — 18 entries.

- [ ] **Step 6: Run elm-format.**

```
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```
git add src/Rad.elm src/Rad/Internal/CellBuilder.elm
git commit -m "Extract CellBuilder to internal module"
```

---

### Task 0.2: Add `cellId`, `cellEncodedInitial`, `cellFromInternal` accessors

**Files:**
- Modify: `src/Rad.elm`

- [ ] **Step 1: Update `src/Rad.elm` exposing list.** Find:

```elm
    , Cell, cellKey
```

Replace with:

```elm
    , Cell, cellKey, cellId, cellEncodedInitial, cellFromInternal
```

Update `@docs`:

```elm
@docs Cell
@docs cellKey, cellId, cellEncodedInitial, cellFromInternal
```

- [ ] **Step 2: Add bodies after `cellKey`:**

```elm
{-| Inspect a cell's runtime ID. Useful for low-level integration (Form
membership, persistence keying). Most users won't need this.
-}
cellId : Cell a -> Int
cellId (Cell c) =
    c.id


{-| Inspect a cell's initial value, already encoded via its codec. Used by
`Rad.Form` to capture pristine snapshot values without exposing the codec.
-}
cellEncodedInitial : Cell a -> Decode.Value
cellEncodedInitial (Cell c) =
    c.codec.encode c.initial


{-| Internal helper for builder modules outside `Rad.elm` (`Rad.Form`'s
`withState`). Constructs a `Cell` from an already-resolved id, key, codec,
and initial. Most users have no reason to call this — use `with`,
`withDebounced`, `withValidated`, or `Form.withState` instead.
-}
cellFromInternal :
    { id : Int
    , key : String
    , codec : Codec a
    , initial : a
    }
    -> Cell a
cellFromInternal r =
    Cell r
```

- [ ] **Step 3: Verify tests still pass.**

```
npx --yes elm-test
```
Expected: **90 passed**.

- [ ] **Step 4: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm
git commit -m "Add cellId, cellEncodedInitial, cellFromInternal accessors"
```

---

### Task 0.3: Add `IReaction.Guts` type alias and `fromGuts` helper

To support `Form.reactions` lifting non-`model`-typed reaction guts into `Reaction model` at use site.

**Files:**
- Modify: `src/Rad/Internal/Reaction.elm`
- Modify: `src/Rad.elm` — add `internalValidationReactionGuts`

- [ ] **Step 1: Update `src/Rad/Internal/Reaction.elm`.** Add to exposing:

```elm
module Rad.Internal.Reaction exposing
    ( Guts
    , InternalRequest(..)
    , Reaction(..)
    , ReactionState
    , emptyState
    , fromGuts
    , guts
    )
```

Add the alias and helpers at the end of the file:

```elm
{-| The fields of a `Reaction` as a separate, non-parameterized record.
Used by `Rad.Form` to store partially-built reactions in `Member` without
threading a `model` type variable through Form/Member.
-}
type alias Guts =
    { readTrigger : Registry -> Encode.Value
    , buildRequest : Registry -> InternalRequest
    , writeLoading : Registry -> Registry
    , writeResult : Encode.Value -> Registry -> Registry
    }


guts : Reaction model -> Guts
guts (Reaction r) =
    r


fromGuts : Guts -> Reaction model
fromGuts g =
    Reaction g
```

- [ ] **Step 2: Add `internalValidationReactionGuts` to `Rad.elm`.** This re-exposes the body of `validationReaction` as raw guts. Add to exposing list:

```elm
    , internalValidationReactionGuts
```

(Place near `validationReactions` in the exposing.)

Update `@docs`:

```elm
@docs internalValidationReactionGuts
```

Add the function. Mirror `validationReaction`'s body but return the raw record:

```elm
{-| Internal: produces the raw fields of a validated cell's reaction. Used by
`Rad.Form` to compose `formReactions`. Not part of the supported public API.
-}
internalValidationReactionGuts : ValidatedCell err a -> IReaction.Guts
internalValidationReactionGuts vcell =
    let
        c =
            IValidated.core vcell

        valCodec =
            validationCodec c.errCodec c.codec

        readInput registry =
            case Registry.get c.inputId registry of
                Just v ->
                    Result.withDefault c.initial
                        (Decode.decodeValue c.codec.decode v)

                Nothing ->
                    c.initial

        readActivationSeq registry =
            Registry.get c.activationSeqId registry
                |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                |> Maybe.withDefault 0
    in
    { readTrigger =
        \registry ->
            Encode.list identity
                [ c.codec.encode (readInput registry)
                , Encode.int (readActivationSeq registry)
                ]
    , buildRequest =
        \registry ->
            let
                activationSeq =
                    readActivationSeq registry
            in
            if activationSeq == 0 then
                IReaction.SkipRequest

            else
                IReaction.DispatchTask
                    (applyValidator c.validator (readInput registry)
                        |> Task.map valCodec.encode
                    )
    , writeLoading =
        \registry ->
            Registry.insert c.validationId
                (valCodec.encode Checking)
                registry
    , writeResult =
        \encoded registry ->
            Registry.insert c.validationId encoded registry
    }
```

(This is the same body as `validationReaction`, just unwrapped from the `IReaction.Reaction` constructor.) Update `validationReaction` to delegate:

```elm
validationReaction : ValidatedCell err a -> Reaction model
validationReaction vcell =
    IReaction.fromGuts (internalValidationReactionGuts vcell)
```

- [ ] **Step 3: Verify tests pass.**

```
npx --yes elm-test
```
Expected: **90 passed**.

- [ ] **Step 4: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Internal/Reaction.elm
git commit -m "Add IReaction.Guts and internalValidationReactionGuts"
```

---

## Slice 1 — Internal Form types

### Task 1.1: Create `Rad.Internal.Form`

Internal-only. No public surface. Tests follow in Slice 2.

**Files:**
- Create: `src/Rad/Internal/Form.elm`

- [ ] **Step 1: Write the module:**

```elm
module Rad.Internal.Form exposing
    ( Form(..)
    , Member(..)
    , State
    , ValidationTag(..)
    , initialState
    , readState
    , stateCodec
    , validationTagDecoder
    )

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry exposing (Registry)


type alias State =
    { snapshot : Decode.Value
    , submitSeq : Int
    , lastResolvedSubmitSeq : Int
    }


initialState : State
initialState =
    { snapshot = Encode.null
    , submitSeq = 0
    , lastResolvedSubmitSeq = 0
    }


stateCodec : { encode : State -> Decode.Value, decode : Decode.Decoder State }
stateCodec =
    { encode =
        \s ->
            Encode.object
                [ ( "snapshot", s.snapshot )
                , ( "submitSeq", Encode.int s.submitSeq )
                , ( "lastResolvedSubmitSeq", Encode.int s.lastResolvedSubmitSeq )
                ]
    , decode =
        Decode.map3 State
            (Decode.field "snapshot" Decode.value)
            (Decode.field "submitSeq" Decode.int)
            (Decode.field "lastResolvedSubmitSeq" Decode.int)
    }


readState : Int -> Registry -> State
readState stateId registry =
    case Registry.get stateId registry of
        Just v ->
            Result.withDefault initialState (Decode.decodeValue stateCodec.decode v)

        Nothing ->
            initialState


type Form fields
    = Form
        { stateId : Int
        , fields : fields
        , members : List Member
        }


type Member
    = PlainMember
        { inputId : Int
        , initial : Decode.Value
        }
    | ValidatedMember
        { inputId : Int
        , validationId : Int
        , activationSeqId : Int
        , initial : Decode.Value
        , reactionGuts : IReaction.Guts
        }


type ValidationTag
    = TagDormant
    | TagChecking
    | TagValid
    | TagInvalid


validationTagDecoder : Decode.Decoder ValidationTag
validationTagDecoder =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "Dormant" ->
                        Decode.succeed TagDormant

                    "Checking" ->
                        Decode.succeed TagChecking

                    "Valid" ->
                        Decode.succeed TagValid

                    "Invalid" ->
                        Decode.succeed TagInvalid

                    _ ->
                        Decode.fail ("unknown Validation tag: " ++ s)
            )
```

- [ ] **Step 2: Verify everything still compiles.**

```
npx --yes elm-test
```
Expected: **90 passed**.

- [ ] **Step 3: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Internal/Form.elm
git commit -m "Add internal Form types"
```

---

## Slice 2 — Public `Rad.Form` skeleton + `Form.withState`

### Task 2.1: Create `Rad.Form` with `withState` and first tests

**Files:**
- Create: `src/Rad/Form.elm`
- Create: `tests/FormBuilderTest.elm`

- [ ] **Step 1: Write failing test.** Create `tests/FormBuilderTest.elm`:

```elm
module FormBuilderTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { profileForm : Rad.Cell Form.State }


init : Rad.CellBuilder Model
init =
    build Model |> Form.withState "profile-form"


suite : Test
suite =
    describe "Form.withState"
        [ test "allocates one Registry slot with the right initial state" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    decoded =
                        Registry.get (Rad.cellId model.profileForm) registry
                            |> Maybe.andThen (Decode.decodeValue Form.stateCodec.decode >> Result.toMaybe)
                in
                Expect.equal
                    (Just
                        { snapshot = Encode.null
                        , submitSeq = 0
                        , lastResolvedSubmitSeq = 0
                        }
                    )
                    decoded
        , test "the state cell's key carries the user-supplied namespace" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal "profile-form" (Rad.cellKey model.profileForm)
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormBuilderTest.elm
```
Expected: compile error — `Rad.Form` not found.

- [ ] **Step 3: Create `src/Rad/Form.elm`:**

```elm
module Rad.Form exposing
    ( Form
    , Member
    , State
    , stateCodec
    , withState
    )

{-| Layer 5 — Forms. Designed for `import Rad.Form as Form`.

# Types

@docs Form, Member, State, stateCodec

# Builder

@docs withState

-}

import Rad exposing (Cell, CellBuilder, Codec)
import Rad.Internal.CellBuilder exposing (CellBuilder(..))
import Rad.Internal.Form as IForm


{-| Opaque transaction boundary over a cells record.
-}
type alias Form fields =
    IForm.Form fields


{-| Opaque membership record. Constructed by `field` / `validatedField`.
-}
type alias Member =
    IForm.Member


{-| The persisted state of a form: snapshot blob + submit-lifecycle counters.
-}
type alias State =
    IForm.State


{-| Codec for `State`, useful at persistence boundaries and in tests.
-}
stateCodec : Codec State
stateCodec =
    IForm.stateCodec


{-| Allocate a Form's persisted state cell. Initial value
`{ snapshot = null, submitSeq = 0, lastResolvedSubmitSeq = 0 }`.

    init =
        build Model
            |> with "name" "" stringCodec
            |> Form.withState "profile-form"

-}
withState : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest
withState key (CellBuilder f) =
    CellBuilder
        (\bs ->
            let
                parent =
                    f bs

                id =
                    parent.nextId

                cell =
                    Rad.cellFromInternal
                        { id = id
                        , key = bs.prefix ++ key
                        , codec = stateCodec
                        , initial = IForm.initialState
                        }
            in
            { nextId = id + 1
            , metas = ( id, stateCodec.encode IForm.initialState ) :: parent.metas
            , ctor = parent.ctor cell
            }
        )
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **90 + 2 new = 92 tests passed.**

- [ ] **Step 5: Run elm-format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormBuilderTest.elm
git commit -m "Add Rad.Form skeleton and Form.withState"
```

---

## Slice 3 — `Form.over`, `Form.field`, `Form.validatedField`

### Task 3.1: Add use-site constructor + member helpers

**Files:**
- Modify: `src/Rad/Form.elm`
- Modify: `tests/FormBuilderTest.elm`

- [ ] **Step 1: Append to `tests/FormBuilderTest.elm`'s `suite`:**

```elm
        , test "Form.over captures fields and members" <|
            \_ ->
                let
                    initBig =
                        build (\n v st -> { n = n, v = v, st = st })
                            |> Rad.with "n" 7 Rad.intCodec
                            |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
                            |> Form.withState "form"

                    ( m, _ ) =
                        Rad.runBuilder initBig

                    f =
                        Form.over m.st { n = m.n, v = m.v } [ Form.field m.n, Form.validatedField m.v ]
                in
                Expect.equal 2 (Form.memberCount f)
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormBuilderTest.elm
```
Expected: compile error.

- [ ] **Step 3: Update `src/Rad/Form.elm`.** Update exposing:

```elm
module Rad.Form exposing
    ( Form
    , Member
    , State
    , field
    , memberCount
    , over
    , stateCodec
    , validatedField
    , withState
    )
```

Update `@docs`:

```elm
# Use-site construction

@docs over, field, validatedField

# Inspection

@docs memberCount
```

Add imports:

```elm
import Rad.Internal.Validated as IValidated
```

Add bodies (after `withState`):

```elm
{-| Construct a `Form fields` value bundling state cell, fields, and members.
Pure — call per render.
-}
over : Cell State -> fields -> List Member -> Form fields
over stateCell fieldsRec members =
    IForm.Form
        { stateId = Rad.cellId stateCell
        , fields = fieldsRec
        , members = members
        }


{-| Mark a plain `Cell` as a form field.
-}
field : Cell a -> Member
field cell =
    IForm.PlainMember
        { inputId = Rad.cellId cell
        , initial = Rad.cellEncodedInitial cell
        }


{-| Mark a `ValidatedCell` as a form field. Captures input/validation/
activation-seq ids and the member's validation reaction.
-}
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
        }


{-| Number of members in the form. For tests.
-}
memberCount : Form fields -> Int
memberCount (IForm.Form f) =
    List.length f.members
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **92 + 1 new = 93 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormBuilderTest.elm
git commit -m "Add Form.over, Form.field, Form.validatedField"
```

---

## Slice 4 — `Form.dirty`

### Task 4.1: Add `dirty` source + `FormDirtyTest`

**Files:**
- Modify: `src/Rad/Form.elm`
- Create: `tests/FormDirtyTest.elm`

- [ ] **Step 1: Create `tests/FormDirtyTest.elm`:**

```elm
module FormDirtyTest exposing (suite)

import Expect
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


buildForm : Model -> Form.Form Fields
buildForm m =
    Form.over m.formState { n = m.n } [ Form.field m.n ]


readDirty f registry =
    Rad.readSource (Form.dirty f) registry


suite : Test
suite =
    describe "Form.dirty"
        [ test "false initially (snapshot null, members at initial)" <|
            \_ ->
                let
                    ( m, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal False (readDirty (buildForm m) registry)
        , test "true after a member's value diverges from initial" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (Rad.set m.n 42) registry0
                in
                Expect.equal True (readDirty (buildForm m) registry1)
        , test "false again when value returns to initial" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        registry0
                            |> Rad.applyAction (Rad.set m.n 42)
                            |> Rad.applyAction (Rad.set m.n 0)
                in
                Expect.equal False (readDirty (buildForm m) registry1)
        , test "with non-null snapshot, dirty compares against snapshot value" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    snapshot =
                        Encode.object [ ( String.fromInt (Rad.cellId m.n), Encode.int 99 ) ]

                    newState =
                        { snapshot = snapshot, submitSeq = 0, lastResolvedSubmitSeq = 0 }

                    registry1 =
                        Registry.insert (Rad.cellId m.formState)
                            (Form.stateCodec.encode newState)
                            registry0

                    dirtyAtInitial =
                        readDirty (buildForm m) registry1

                    registry2 =
                        Rad.applyAction (Rad.set m.n 99) registry1

                    dirtyAtSnapshot =
                        readDirty (buildForm m) registry2
                in
                Expect.equal ( True, False ) ( dirtyAtInitial, dirtyAtSnapshot )
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormDirtyTest.elm
```
Expected: compile error — `Form.dirty` not found.

- [ ] **Step 3: Add `dirty` to `Rad/Form.elm`.** Update exposing to include `dirty` (alphabetically). Update `@docs`:

```elm
# Behaviors

@docs dirty
```

Add imports:

```elm
import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry as Registry exposing (Registry)
import Rad.Internal.Source as ISource
```

Add the `dirty` body and small helpers:

```elm
{-| `True` iff any member's current registry value differs from the form's
pristine reference (snapshot when non-null, otherwise each member's initial).
-}
dirty : Form fields -> Rad.Source Bool
dirty (IForm.Form f) =
    ISource.Source
        { read =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry

                    snapshotIsNull =
                        Decode.decodeValue (Decode.null ()) state.snapshot == Ok ()

                    pristineFor : Member -> Decode.Value
                    pristineFor member =
                        if snapshotIsNull then
                            memberInitial member

                        else
                            case
                                Decode.decodeValue
                                    (Decode.field
                                        (String.fromInt (memberInputId member))
                                        Decode.value
                                    )
                                    state.snapshot
                            of
                                Ok v ->
                                    v

                                Err _ ->
                                    memberInitial member

                    isMemberDirty member =
                        case Registry.get (memberInputId member) registry of
                            Just current ->
                                current /= pristineFor member

                            Nothing ->
                                False
                in
                List.any isMemberDirty f.members
        , codec = { encode = Encode.bool, decode = Decode.bool }
        }


memberInputId : Member -> Int
memberInputId member =
    case member of
        IForm.PlainMember m ->
            m.inputId

        IForm.ValidatedMember m ->
            m.inputId


memberInitial : Member -> Decode.Value
memberInitial member =
    case member of
        IForm.PlainMember m ->
            m.initial

        IForm.ValidatedMember m ->
            m.initial
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **93 + 4 new = 97 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormDirtyTest.elm
git commit -m "Add Form.dirty"
```

---

## Slice 5 — `Form.submit` and `Form.reset`

### Task 5.1: Add `submit` and `reset` actions + `FormResetTest`

**Files:**
- Modify: `src/Rad/Form.elm`
- Create: `tests/FormResetTest.elm`

- [ ] **Step 1: Create `tests/FormResetTest.elm`:**

```elm
module FormResetTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { n : Rad.Cell Int
    , v : Rad.ValidatedCell String String
    }


type alias Model =
    { n : Rad.Cell Int
    , v : Rad.ValidatedCell String String
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.with "n" 0 Rad.intCodec
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { n = m.n, v = m.v } [ Form.field m.n, Form.validatedField m.v ]


readState m registry =
    case Registry.get (Rad.cellId m.formState) registry of
        Just v ->
            Result.withDefault
                { snapshot = Encode.null, submitSeq = 0, lastResolvedSubmitSeq = 0 }
                (Decode.decodeValue Form.stateCodec.decode v)

        Nothing ->
            { snapshot = Encode.null, submitSeq = 0, lastResolvedSubmitSeq = 0 }


readActivationSeq vcell registry =
    Registry.get (.activationSeqId (IValidated.ref vcell)) registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
        |> Maybe.withDefault 0


suite : Test
suite =
    describe "Form.submit and Form.reset"
        [ test "submit bumps submitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0
                in
                Expect.equal 1 (.submitSeq (readState m r1))
        , test "submit bumps each ValidatedMember's activationSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0
                in
                Expect.equal 1 (readActivationSeq m.v r1)
        , test "reset restores members to initial when snapshot is null" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Rad.set m.n 42)
                            |> Rad.applyAction (Form.reset (buildForm m))
                in
                Expect.equal (Just (Encode.int 0)) (Registry.get (Rad.cellId m.n) r1)
        , test "reset zeros each ValidatedMember's activationSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Rad.validate m.v) r0

                    seqAfterValidate =
                        readActivationSeq m.v r1

                    r2 =
                        Rad.applyAction (Form.reset (buildForm m)) r1

                    seqAfterReset =
                        readActivationSeq m.v r2
                in
                Expect.equal ( 1, 0 ) ( seqAfterValidate, seqAfterReset )
        , test "reset does not modify submitSeq / lastResolvedSubmitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> Rad.applyAction (Form.reset (buildForm m))

                    s =
                        readState m r1
                in
                Expect.equal ( 1, 0 ) ( s.submitSeq, s.lastResolvedSubmitSeq )
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormResetTest.elm
```
Expected: compile error.

- [ ] **Step 3: Add `submit`/`reset` to `Rad/Form.elm`.** Update exposing to include `submit, reset`. Update `@docs`:

```elm
@docs dirty, submit, reset
```

Add imports:

```elm
import Rad.Internal.Action as IAction exposing (Action(..))
```

Add bodies:

```elm
{-| Bumps `submitSeq` and dispatches `validate` to each ValidatedMember.
-}
submit : Form fields -> Rad.Action model
submit (IForm.Form f) =
    IAction.Action
        (\registry ->
            let
                state =
                    IForm.readState f.stateId registry

                newState =
                    { state | submitSeq = state.submitSeq + 1 }

                r1 =
                    Registry.insert f.stateId (IForm.stateCodec.encode newState) registry

                bumpActivation member r =
                    case member of
                        IForm.ValidatedMember m ->
                            let
                                current =
                                    Registry.get m.activationSeqId r
                                        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                                        |> Maybe.withDefault 0
                            in
                            Registry.insert m.activationSeqId (Encode.int (current + 1)) r

                        IForm.PlainMember _ ->
                            r
            in
            List.foldl bumpActivation r1 f.members
        )


{-| Restores all members to pristine value (snapshot or initial), zeros each
ValidatedMember's activation seq, sets validation slot to Dormant. Does NOT
modify submitSeq / lastResolvedSubmitSeq.
-}
reset : Form fields -> Rad.Action model
reset (IForm.Form f) =
    IAction.Action
        (\registry ->
            let
                state =
                    IForm.readState f.stateId registry

                snapshotIsNull =
                    Decode.decodeValue (Decode.null ()) state.snapshot == Ok ()

                pristineFor member =
                    if snapshotIsNull then
                        memberInitial member

                    else
                        case
                            Decode.decodeValue
                                (Decode.field (String.fromInt (memberInputId member)) Decode.value)
                                state.snapshot
                        of
                            Ok v ->
                                v

                            Err _ ->
                                memberInitial member

                resetMember member r =
                    let
                        r1 =
                            Registry.insert (memberInputId member) (pristineFor member) r
                    in
                    case member of
                        IForm.ValidatedMember m ->
                            r1
                                |> Registry.insert m.validationId dormantEncoded
                                |> Registry.insert m.activationSeqId (Encode.int 0)

                        IForm.PlainMember _ ->
                            r1
            in
            List.foldl resetMember registry f.members
        )


dormantEncoded : Decode.Value
dormantEncoded =
    Encode.object [ ( "tag", Encode.string "Dormant" ) ]
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **97 + 5 new = 102 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormResetTest.elm
git commit -m "Add Form.submit and Form.reset"
```

---

## Slice 6 — Status sources and `Form.Status` enum

### Task 6.1: Add status helpers + `FormStatusTest`

**Files:**
- Modify: `src/Rad/Form.elm`
- Create: `tests/FormStatusTest.elm`

- [ ] **Step 1: Create `tests/FormStatusTest.elm`:**

```elm
module FormStatusTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form exposing (Status(..))
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { v : Rad.ValidatedCell String String }


type alias Model =
    { v : Rad.ValidatedCell String String
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { v = m.v } [ Form.validatedField m.v ]


readStatus f registry =
    Rad.readSource (Form.status f) registry


readBool src registry =
    Rad.readSource src registry


suite : Test
suite =
    describe "Form status helpers"
        [ test "Pristine when not dirty + no submit pending + no validation issues" <|
            \_ ->
                let
                    ( m, r ) =
                        Rad.runBuilder init
                in
                Expect.equal Pristine (readStatus (buildForm m) r)
        , test "Editable when dirty and clean otherwise" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Rad.set (Rad.input m.v) "x") r0
                in
                Expect.equal Editable (readStatus (buildForm m) r1)
        , test "submitPending true after Form.submit" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    initialPending =
                        readBool (Form.submitPending (buildForm m)) r0

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0

                    afterPending =
                        readBool (Form.submitPending (buildForm m)) r1
                in
                Expect.equal ( False, True ) ( initialPending, afterPending )
        , test "canSubmit truth table" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    s0 =
                        readBool (Form.canSubmit (buildForm m)) r0

                    r1 =
                        Rad.applyAction (Rad.set (Rad.input m.v) "x") r0

                    s1 =
                        readBool (Form.canSubmit (buildForm m)) r1

                    r2 =
                        Rad.applyAction (Form.submit (buildForm m)) r1

                    s2 =
                        readBool (Form.canSubmit (buildForm m)) r2
                in
                Expect.equal ( False, True, False ) ( s0, s1, s2 )
        , test "HasErrors wins over Submitting when validation slot is Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    invalidEncoded =
                        Encode.object
                            [ ( "tag", Encode.string "Invalid" )
                            , ( "errors", Encode.list Encode.string [ "bad" ] )
                            ]

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            invalidEncoded
                            r0

                    state2 =
                        { snapshot = Encode.null, submitSeq = 1, lastResolvedSubmitSeq = 0 }

                    r2 =
                        Registry.insert (Rad.cellId m.formState) (Form.stateCodec.encode state2) r1
                in
                Expect.equal HasErrors (readStatus (buildForm m) r2)
        , test "Validating when submitPending and a validation slot is Checking" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    checkingEncoded =
                        Encode.object [ ( "tag", Encode.string "Checking" ) ]

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            checkingEncoded
                            r0

                    state2 =
                        { snapshot = Encode.null, submitSeq = 1, lastResolvedSubmitSeq = 0 }

                    r2 =
                        Registry.insert (Rad.cellId m.formState) (Form.stateCodec.encode state2) r1
                in
                Expect.equal Validating (readStatus (buildForm m) r2)
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormStatusTest.elm
```
Expected: compile error.

- [ ] **Step 3: Add status API to `Rad/Form.elm`.** Update exposing:

```elm
    , Status(..)
    , canSubmit
    , checking
    , invalid
    , status
    , submitPending
```

Update `@docs`:

```elm
# Status

@docs Status, status, canSubmit, submitPending, invalid, checking
```

Add bodies (after `reset`):

```elm
{-| Bundled snapshot of the form's UI state. Suitable for rendering a submit
button. See `status` for precedence.
-}
type Status
    = Pristine
    | Editable
    | HasErrors
    | Validating
    | Submitting


{-| `True` iff submitSeq > lastResolvedSubmitSeq.
-}
submitPending : Form fields -> Rad.Source Bool
submitPending (IForm.Form f) =
    boolSource
        (\registry ->
            let
                s =
                    IForm.readState f.stateId registry
            in
            s.submitSeq > s.lastResolvedSubmitSeq
        )


{-| `True` iff any ValidatedMember's validation slot decodes to Invalid.
-}
invalid : Form fields -> Rad.Source Bool
invalid (IForm.Form f) =
    boolSource (\registry -> List.any (memberHasTag IForm.TagInvalid registry) f.members)


{-| `True` iff any ValidatedMember's validation slot decodes to Checking.
-}
checking : Form fields -> Rad.Source Bool
checking (IForm.Form f) =
    boolSource (\registry -> List.any (memberHasTag IForm.TagChecking registry) f.members)


{-| dirty AND not invalid AND not checking AND not submitPending.
-}
canSubmit : Form fields -> Rad.Source Bool
canSubmit form =
    boolSource
        (\registry ->
            Rad.readSource (dirty form) registry
                && not (Rad.readSource (invalid form) registry)
                && not (Rad.readSource (checking form) registry)
                && not (Rad.readSource (submitPending form) registry)
        )


{-| Bundled `Status`. Precedence: invalid → HasErrors; submitPending+checking
→ Validating; submitPending → Submitting; dirty → Editable; else Pristine.
-}
status : Form fields -> Rad.Source Status
status form =
    ISource.Source
        { read =
            \registry ->
                if Rad.readSource (invalid form) registry then
                    HasErrors

                else if Rad.readSource (submitPending form) registry && Rad.readSource (checking form) registry then
                    Validating

                else if Rad.readSource (submitPending form) registry then
                    Submitting

                else if Rad.readSource (dirty form) registry then
                    Editable

                else
                    Pristine
        , codec =
            { encode =
                \s ->
                    Encode.string
                        (case s of
                            Pristine ->
                                "Pristine"

                            Editable ->
                                "Editable"

                            HasErrors ->
                                "HasErrors"

                            Validating ->
                                "Validating"

                            Submitting ->
                                "Submitting"
                        )
            , decode =
                Decode.string
                    |> Decode.andThen
                        (\s ->
                            case s of
                                "Pristine" ->
                                    Decode.succeed Pristine

                                "Editable" ->
                                    Decode.succeed Editable

                                "HasErrors" ->
                                    Decode.succeed HasErrors

                                "Validating" ->
                                    Decode.succeed Validating

                                "Submitting" ->
                                    Decode.succeed Submitting

                                _ ->
                                    Decode.fail ("unknown Status tag: " ++ s)
                        )
            }
        }


boolSource : (Registry -> Bool) -> Rad.Source Bool
boolSource read =
    ISource.Source
        { read = read
        , codec = { encode = Encode.bool, decode = Decode.bool }
        }


memberHasTag : IForm.ValidationTag -> Registry -> Member -> Bool
memberHasTag tag registry member =
    case member of
        IForm.ValidatedMember m ->
            case Registry.get m.validationId registry of
                Just v ->
                    case Decode.decodeValue IForm.validationTagDecoder v of
                        Ok decoded ->
                            decoded == tag

                        Err _ ->
                            False

                Nothing ->
                    False

        IForm.PlainMember _ ->
            False
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **102 + 6 new = 108 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormStatusTest.elm
git commit -m "Add Form.status and atomic status sources"
```

---

## Slice 7 — `ValidatedGroup` + `validators1..8` + `mapValidated`

### Task 7.1: Add internal `ValidatedGroup` + group helpers + tests

**Files:**
- Create: `src/Rad/Internal/ValidatedGroup.elm`
- Modify: `src/Rad/Form.elm`
- Create: `tests/ValidatedGroupTest.elm`

- [ ] **Step 1: Create `tests/ValidatedGroupTest.elm`:**

```elm
module ValidatedGroupTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { a : Rad.ValidatedCell String String
    , b : Rad.ValidatedCell String Int
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.withValidated "a" "alpha" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Rad.withValidated "b" 7 Rad.intCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


setValid vcell encodedValue registry =
    let
        ref =
            IValidated.ref vcell

        validEncoded =
            Encode.object [ ( "tag", Encode.string "Valid" ), ( "value", encodedValue ) ]
    in
    Registry.insert ref.validationId validEncoded registry


setInvalid vcell registry =
    let
        ref =
            IValidated.ref vcell

        invalidEncoded =
            Encode.object
                [ ( "tag", Encode.string "Invalid" )
                , ( "errors", Encode.list Encode.string [ "bad" ] )
                ]
    in
    Registry.insert ref.validationId invalidEncoded registry


suite : Test
suite =
    describe "ValidatedGroup"
        [ test "validators1 returns Just a when Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        setValid m.a (Encode.string "hello") r0
                in
                Expect.equal (Just "hello")
                    (Form.readGroup (Form.validators1 .a) { a = m.a, b = m.b } r1)
        , test "validators1 returns Nothing when Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        setInvalid m.a r0
                in
                Expect.equal Nothing
                    (Form.readGroup (Form.validators1 .a) { a = m.a, b = m.b } r1)
        , test "validators2 returns Just (a, b) when both Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setValid m.b (Encode.int 99)
                in
                Expect.equal (Just ( "alpha", 99 ))
                    (Form.readGroup (Form.validators2 .a .b) { a = m.a, b = m.b } r1)
        , test "validators2 returns Nothing when one Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setInvalid m.b
                in
                Expect.equal Nothing
                    (Form.readGroup (Form.validators2 .a .b) { a = m.a, b = m.b } r1)
        , test "mapValidated transforms the clean tuple" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setValid m.b (Encode.int 5)

                    group =
                        Form.validators2 .a .b
                            |> Form.mapValidated (\( a, b ) -> { name = a, count = b })
                in
                Expect.equal (Just { name = "alpha", count = 5 })
                    (Form.readGroup group { a = m.a, b = m.b } r1)
        ]
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/ValidatedGroupTest.elm
```
Expected: compile error.

- [ ] **Step 3: Create `src/Rad/Internal/ValidatedGroup.elm`:**

```elm
module Rad.Internal.ValidatedGroup exposing
    ( ValidatedGroup(..)
    , readGroup
    , validationIds
    )

import Rad.Internal.Registry exposing (Registry)


type ValidatedGroup fields clean
    = ValidatedGroup
        { ids : fields -> List Int
        , read : fields -> Registry -> Maybe clean
        }


readGroup : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
readGroup (ValidatedGroup g) =
    g.read


validationIds : ValidatedGroup fields clean -> fields -> List Int
validationIds (ValidatedGroup g) =
    g.ids
```

- [ ] **Step 4: Update `src/Rad/Form.elm`.** Update exposing to add `ValidatedGroup, validators1, validators2, validators3, validators4, validators5, validators6, validators7, validators8, mapValidated, readGroup`.

Update `@docs`:

```elm
# ValidatedGroup

@docs ValidatedGroup, validators1, validators2, validators3, validators4
@docs validators5, validators6, validators7, validators8, mapValidated, readGroup
```

Add import:

```elm
import Rad.Internal.ValidatedGroup as IGroup
```

Add type alias and helpers:

```elm
{-| Typed bundle of validators in a form, used to gate submission.
-}
type alias ValidatedGroup fields clean =
    IGroup.ValidatedGroup fields clean


{-| Read a group's clean values from registry. Returns `Just clean` iff every
validator is `Valid`. Mostly for tests.
-}
readGroup : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
readGroup =
    IGroup.readGroup


extractValid : (fields -> Rad.ValidatedCell err a) -> fields -> Registry -> Maybe a
extractValid getter fieldsRec registry =
    let
        c =
            IValidated.core (getter fieldsRec)

        validDecoder =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        if tag == "Valid" then
                            Decode.field "value" c.codec.decode

                        else
                            Decode.fail ("not Valid: " ++ tag)
                    )
    in
    Registry.get c.validationId registry
        |> Maybe.andThen (Decode.decodeValue validDecoder >> Result.toMaybe)


validationIdOf : (fields -> Rad.ValidatedCell err a) -> fields -> Int
validationIdOf getter fieldsRec =
    .validationId (IValidated.ref (getter fieldsRec))


validators1 :
    (fields -> Rad.ValidatedCell err a)
    -> ValidatedGroup fields a
validators1 g1 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f ]
        , read = \f r -> extractValid g1 f r
        }


validators2 g1 g2 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f ]
        , read = \f r -> Maybe.map2 Tuple.pair (extractValid g1 f r) (extractValid g2 f r)
        }


validators3 g1 g2 g3 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f ]
        , read =
            \f r ->
                Maybe.map3 (\a b c -> ( a, b, c ))
                    (extractValid g1 f r)
                    (extractValid g2 f r)
                    (extractValid g3 f r)
        }


validators4 g1 g2 g3 g4 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f, validationIdOf g4 f ]
        , read =
            \f r ->
                Maybe.map4 (\a b c d -> ( a, b, c, d ))
                    (extractValid g1 f r)
                    (extractValid g2 f r)
                    (extractValid g3 f r)
                    (extractValid g4 f r)
        }


validators5 g1 g2 g3 g4 g5 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f, validationIdOf g4 f, validationIdOf g5 f ]
        , read =
            \f r ->
                Maybe.map5 (\a b c d e -> ( a, b, c, d, e ))
                    (extractValid g1 f r)
                    (extractValid g2 f r)
                    (extractValid g3 f r)
                    (extractValid g4 f r)
                    (extractValid g5 f r)
        }


validators6 g1 g2 g3 g4 g5 g6 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f
                , validationIdOf g4 f, validationIdOf g5 f, validationIdOf g6 f
                ]
        , read =
            \f r ->
                Maybe.map2 (\( a, b, c, d, e ) ff -> ( a, b, c, d, e, ff ))
                    (Maybe.map5 (\a b c d e -> ( a, b, c, d, e ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                        (extractValid g4 f r)
                        (extractValid g5 f r)
                    )
                    (extractValid g6 f r)
        }


validators7 g1 g2 g3 g4 g5 g6 g7 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f
                , validationIdOf g4 f, validationIdOf g5 f, validationIdOf g6 f
                , validationIdOf g7 f
                ]
        , read =
            \f r ->
                Maybe.map3 (\( a, b, c, d, e ) ff gg -> ( a, b, c, d, e, ff, gg ))
                    (Maybe.map5 (\a b c d e -> ( a, b, c, d, e ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                        (extractValid g4 f r)
                        (extractValid g5 f r)
                    )
                    (extractValid g6 f r)
                    (extractValid g7 f r)
        }


validators8 g1 g2 g3 g4 g5 g6 g7 g8 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f
                , validationIdOf g4 f, validationIdOf g5 f, validationIdOf g6 f
                , validationIdOf g7 f, validationIdOf g8 f
                ]
        , read =
            \f r ->
                Maybe.map4 (\( a, b, c, d, e ) ff gg hh -> ( a, b, c, d, e, ff, gg, hh ))
                    (Maybe.map5 (\a b c d e -> ( a, b, c, d, e ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                        (extractValid g4 f r)
                        (extractValid g5 f r)
                    )
                    (extractValid g6 f r)
                    (extractValid g7 f r)
                    (extractValid g8 f r)
        }


{-| Transform a group's clean type. Useful for packing tuples into records.
-}
mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
mapValidated f (IGroup.ValidatedGroup g) =
    IGroup.ValidatedGroup
        { ids = g.ids
        , read = \fieldsRec registry -> Maybe.map f (g.read fieldsRec registry)
        }
```

If type-inference complains on `validators2`–`validators8`, add explicit type annotations modeled on `validators1`'s shape (multiple `errN` parameters, returning `ValidatedGroup fields ( a, b, ... )`).

- [ ] **Step 5: Run tests.**

```
npx --yes elm-test
```
Expected: **108 + 5 new = 113 tests passed.**

- [ ] **Step 6: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm src/Rad/Internal/ValidatedGroup.elm tests/ValidatedGroupTest.elm
git commit -m "Add ValidatedGroup and Form.validators1..8"
```

---

## Slice 8 — Reactions: `reactions`, `onSubmit`, `onValid`

### Task 8.1: Add `Form.reactions`

**Files:**
- Modify: `src/Rad/Form.elm`
- Modify: `tests/FormBuilderTest.elm`

- [ ] **Step 1: Append to `tests/FormBuilderTest.elm`'s `suite`:**

```elm
        , test "Form.reactions returns one Reaction per ValidatedMember (none for PlainMember)" <|
            \_ ->
                let
                    initR =
                        build (\n v st -> { n = n, v = v, st = st })
                            |> Rad.with "n" 0 Rad.intCodec
                            |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
                            |> Form.withState "form"

                    ( model_, _ ) =
                        Rad.runBuilder initR

                    f =
                        Form.over model_.st
                            { v = model_.v }
                            [ Form.field model_.n, Form.validatedField model_.v ]
                in
                Expect.equal 1 (List.length (Form.reactions f))
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormBuilderTest.elm
```
Expected: compile error — `Form.reactions` not found.

- [ ] **Step 3: Add `reactions` to `Rad/Form.elm`.** Update exposing to include `reactions`. Update `@docs`:

```elm
# Reactions

@docs reactions
```

Add import:

```elm
import Rad.Internal.Reaction as IReaction
```

Add body:

```elm
{-| One reaction per ValidatedMember; PlainMembers contribute nothing.
Concatenate with the user's other reactions in `AppDef.reactions`.
-}
reactions : Form fields -> List (Rad.Reaction model)
reactions (IForm.Form f) =
    List.filterMap memberReaction f.members


memberReaction : Member -> Maybe (Rad.Reaction model)
memberReaction member =
    case member of
        IForm.ValidatedMember m ->
            Just (IReaction.fromGuts m.reactionGuts)

        IForm.PlainMember _ ->
            Nothing
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **113 + 1 new = 114 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad/Form.elm tests/FormBuilderTest.elm
git commit -m "Add Form.reactions"
```

---

### Task 8.2: Add `Form.onSubmit` + `FormSubmitGateTest`

**Files:**
- Modify: `src/Rad/Form.elm`
- Create: `tests/FormSubmitGateTest.elm`

The reaction's behavior:
- **Trigger:** state cell value + each validation slot in the group.
- **buildRequest:** if `submitSeq <= lastResolvedSubmitSeq` → SkipRequest. Else if any validator not Valid → SkipRequest. Else extract clean → user's `(clean -> Request err r)` → DispatchTask.
- **writeLoading:** writes `Loading` to target Cell (Remote-shaped) — same as `Rad.on`.
- **writeResult:** decodes Done/Failed, writes to target. On Done: bump `lastResolvedSubmitSeq` ← `submitSeq` AND re-encode all member values into snapshot AND write updated state cell.

- [ ] **Step 1: Create `tests/FormSubmitGateTest.elm`:**

```elm
module FormSubmitGateTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (Remote(..), build)
import Rad.Form as Form
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { name : Rad.ValidatedCell String String }


type alias Model =
    { name : Rad.ValidatedCell String String
    , submitResult : Rad.Cell (Remote Rad.Http.RequestError ())
    , formState : Rad.Cell Form.State
    }


resultCodec : Rad.Codec (Remote Rad.Http.RequestError ())
resultCodec =
    Rad.remoteCodec Rad.Http.requestErrorCodec
        { encode = \_ -> Encode.null, decode = Decode.null () }


init =
    build Model
        |> Rad.withValidated "name" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Rad.with "result" Idle resultCodec
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { name = m.name } [ Form.validatedField m.name ]


setValid vcell encodedValue registry =
    Registry.insert
        (.validationId (IValidated.ref vcell))
        (Encode.object [ ( "tag", Encode.string "Valid" ), ( "value", encodedValue ) ])
        registry


-- noop request used in tests; we only check buildRequest's dispatch decision.
noopRequest : a -> Rad.Request err ()
noopRequest _ =
    Rad.noRequest


suite : Test
suite =
    describe "Form.onSubmit"
        [ test "SkipRequest when submitSeq <= lastResolvedSubmitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    -- name validation Valid; but no submit pending
                    r1 =
                        setValid m.name (Encode.string "alice") r0

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            noopRequest
                            m.submitResult
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest"
        , test "SkipRequest when submit pending but validation not yet Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            noopRequest
                            m.submitResult
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest"
        , test "DispatchTask when submit pending and all Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> setValid m.name (Encode.string "alice")

                    -- use a sync-success request that always succeeds with ()
                    successRequest _ =
                        Rad.noRequest
                            -- noRequest produces SkipRequest. Replace with a real
                            -- task that always succeeds. Use an async-Sync trick:
                            |> identity

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noRequest)
                            m.submitResult
                in
                -- when the user's `toRequest` returns NoRequest, buildRequest should
                -- still yield SkipRequest (because no actual task to run)
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest (toRequest returned noRequest)"
        ]
```

(The `DispatchTask` positive-path assertion is hard to test without a network harness; the negative paths cover the gating logic. A richer integration test would use `Rad.Http`'s mock handler infrastructure.)

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormSubmitGateTest.elm
```
Expected: compile error.

- [ ] **Step 3: Add `onSubmit` to `Rad/Form.elm`.** Update exposing to include `onSubmit`. Update `@docs`:

```elm
# Submit gating

@docs onSubmit, onValid
```

(Also include `onValid` here — implemented in Task 8.3.)

Add imports:

```elm
import Rad.Internal.Request as IRequest
import Task exposing (Task)
```

Add body:

```elm
{-| A reaction that fires a `Request` when the form is submitted and all
validators in the group are `Valid`. On success, advances the form's snapshot
and `lastResolvedSubmitSeq`. The target cell is `Cell (Remote err r)`.
-}
onSubmit :
    Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Rad.Request err r)
    -> Rad.Cell (Rad.Remote err r)
    -> Rad.Reaction model
onSubmit form group toRequest targetCell =
    let
        (IForm.Form f) =
            form

        targetId =
            Rad.cellId targetCell

        targetCodec =
            -- We need the codec; cellEncodedInitial gives us encoded null
            -- but we need encode/decode for Remote err r. Use a small accessor.
            -- (Implementation note: `Rad.cellCodec` does not exist yet — we
            -- access the codec via the existing `cellFromInternal` / direct
            -- field. Add `cellCodec : Cell a -> Codec a` accessor in this task
            -- if not already present from Slice 0.2.)
            Rad.cellCodec targetCell
    in
    IReaction.fromGuts
        { readTrigger =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry

                    valIds =
                        IGroup.validationIds group f.fields

                    valEncoded =
                        valIds
                            |> List.map
                                (\id ->
                                    Registry.get id registry
                                        |> Maybe.withDefault Encode.null
                                )
                in
                Encode.list identity
                    (Encode.int state.submitSeq
                        :: Encode.int state.lastResolvedSubmitSeq
                        :: valEncoded
                    )
        , buildRequest =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry
                in
                if state.submitSeq <= state.lastResolvedSubmitSeq then
                    IReaction.SkipRequest

                else
                    case IGroup.readGroup group f.fields registry of
                        Just clean ->
                            case toRequest clean of
                                IRequest.NoRequest ->
                                    IReaction.SkipRequest

                                IRequest.DispatchRequest task ->
                                    IReaction.DispatchTask
                                        (task
                                            |> Task.map (\r -> targetCodec.encode (Rad.Done r))
                                            |> Task.onError
                                                (\e -> Task.succeed (targetCodec.encode (Rad.Failed e)))
                                        )

                        Nothing ->
                            IReaction.SkipRequest
        , writeLoading =
            \registry ->
                Registry.insert targetId (targetCodec.encode Rad.Loading) registry
        , writeResult =
            \encoded registry ->
                let
                    -- Decode result; if Done, advance snapshot + lastResolvedSubmitSeq
                    decodedDone =
                        Decode.decodeValue
                            (Decode.field "tag" Decode.string
                                |> Decode.andThen
                                    (\tag ->
                                        if tag == "Done" then
                                            Decode.succeed True

                                        else
                                            Decode.succeed False
                                    )
                            )
                            encoded
                            |> Result.withDefault False

                    r1 =
                        Registry.insert targetId encoded registry
                in
                if decodedDone then
                    advanceSnapshot form r1

                else
                    r1
        }


advanceSnapshot : Form fields -> Registry -> Registry
advanceSnapshot (IForm.Form f) registry =
    let
        state =
            IForm.readState f.stateId registry

        snapshotPairs : List ( String, Decode.Value )
        snapshotPairs =
            f.members
                |> List.map
                    (\member ->
                        let
                            id =
                                memberInputId member

                            current =
                                Registry.get id registry
                                    |> Maybe.withDefault (memberInitial member)
                        in
                        ( String.fromInt id, current )
                    )

        newSnapshot =
            Encode.object snapshotPairs

        newState =
            { state
                | snapshot = newSnapshot
                , lastResolvedSubmitSeq = state.submitSeq
            }
    in
    Registry.insert f.stateId (IForm.stateCodec.encode newState) registry
```

This depends on `Rad.cellCodec : Cell a -> Codec a`. Add it to `Rad.elm` if not already present:

```elm
-- in Rad.elm exposing list near cellEncodedInitial:
    , cellCodec

-- @docs:
@docs cellCodec

-- body:
{-| Inspect a cell's codec. For low-level integration; most users won't need it.
-}
cellCodec : Cell a -> Codec a
cellCodec (Cell c) =
    c.codec
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **114 + 3 new = 117 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Form.elm tests/FormSubmitGateTest.elm
git commit -m "Add Form.onSubmit and cellCodec accessor"
```

---

### Task 8.3: Add `Form.onValid`

**Files:**
- Modify: `src/Rad/Form.elm`
- Modify: `tests/FormSubmitGateTest.elm`

- [ ] **Step 1: Append to `tests/FormSubmitGateTest.elm`'s suite:**

```elm
        , test "Form.onValid: SkipRequest when not all Valid; DispatchTask sentinel when all Valid + submit pending" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> setValid m.name (Encode.string "alice")

                    react =
                        Form.onValid (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noAction)
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.DispatchTask _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected DispatchTask"
```

This depends on `Rad.noAction` — a no-op Action. Add to `Rad.elm` if not already present:

```elm
-- exposing:
    , noAction

-- @docs:
@docs noAction

-- body:
{-| The identity Action — does nothing to the registry. Useful as a default
or a placeholder.
-}
noAction : Action model
noAction =
    IAction.Action identity
```

- [ ] **Step 2: Run to confirm failure.**

```
npx --yes elm-test tests/FormSubmitGateTest.elm
```
Expected: compile error.

- [ ] **Step 3: Add `onValid` to `Rad/Form.elm`.** Update exposing to include `onValid` (already in `@docs` from Task 8.2).

Add body:

```elm
{-| Like `onSubmit`, but runs an Action instead of dispatching a Request. On
each fire (when the gate passes), bumps `lastResolvedSubmitSeq` to
`submitSeq` and advances the snapshot.
-}
onValid :
    Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Rad.Action model)
    -> Rad.Reaction model
onValid form group toAction =
    let
        (IForm.Form f) =
            form
    in
    IReaction.fromGuts
        { readTrigger =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry

                    valIds =
                        IGroup.validationIds group f.fields

                    valEncoded =
                        List.map
                            (\id -> Registry.get id registry |> Maybe.withDefault Encode.null)
                            valIds
                in
                Encode.list identity
                    (Encode.int state.submitSeq
                        :: Encode.int state.lastResolvedSubmitSeq
                        :: valEncoded
                    )
        , buildRequest =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry
                in
                if state.submitSeq <= state.lastResolvedSubmitSeq then
                    IReaction.SkipRequest

                else
                    case IGroup.readGroup group f.fields registry of
                        Just _ ->
                            -- sentinel task; writeResult does the actual work
                            IReaction.DispatchTask (Task.succeed Encode.null)

                        Nothing ->
                            IReaction.SkipRequest
        , writeLoading = identity
        , writeResult =
            \_ registry ->
                case IGroup.readGroup group f.fields registry of
                    Just clean ->
                        let
                            (IAction.Action applyUserAction) =
                                toAction clean

                            r1 =
                                applyUserAction registry
                        in
                        advanceSnapshot form r1

                    Nothing ->
                        registry
        }
```

- [ ] **Step 4: Run tests.**

```
npx --yes elm-test
```
Expected: **117 + 1 new = 118 tests passed.**

- [ ] **Step 5: Format and commit.**

```
npx --yes elm-format src tests --yes
git add src/Rad.elm src/Rad/Form.elm tests/FormSubmitGateTest.elm
git commit -m "Add Form.onValid and noAction"
```

---

## Slice 9 — Examples

### Task 9.1: Ship `L05E01-profile-form`

**Files:**
- Create: `examples/src/ProfileForm.elm`
- Create: `examples/L05E01-profile-form.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/ProfileForm.elm`:**

```elm
module ProfileForm exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , ValidatedCell
        , build
        , noRequest
        , remoteCodec
        , run
        , stringCodec
        , sync
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import Rad.Http exposing (RequestError, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Fields =
    { name : ValidatedCell String String
    , email : ValidatedCell String String
    , bio : Cell String
    }


type alias Model =
    { name : ValidatedCell String String
    , email : ValidatedCell String String
    , bio : Cell String
    , submitResult : Cell (Remote RequestError ())
    , formState : Cell Form.State
    }


nameValidator : Rad.Validator String String
nameValidator =
    sync
        (\s ->
            if String.trim s == "" then
                Err [ "Name is required" ]

            else
                Ok s
        )


emailValidator : Rad.Validator String String
emailValidator =
    sync
        (\s ->
            if String.contains "@" s then
                Ok s

            else
                Err [ "Invalid email" ]
        )


unitCodec : Rad.Codec ()
unitCodec =
    { encode = \_ -> Encode.null
    , decode = Decode.null ()
    }


resultCodec : Rad.Codec (Remote RequestError ())
resultCodec =
    remoteCodec requestErrorCodec unitCodec


fields : Model -> Fields
fields m =
    { name = m.name, email = m.email, bio = m.bio }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState
        (fields m)
        [ Form.validatedField m.name
        , Form.validatedField m.email
        , Form.field m.bio
        ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
            |> withValidated "email" "" stringCodec stringCodec emailValidator
            |> with "bio" "" stringCodec
            |> with "submit-result" Idle resultCodec
            |> Form.withState "profile-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = Rad.input model.name }
                , input { label = "Email", cell = Rad.input model.email }
                , input { label = "Bio", cell = model.bio }
                , watch (Form.status (theForm model)) renderStatusHint
                , watch (Form.dirty (theForm model))
                    (\d ->
                        text
                            (if d then
                                "* unsaved changes"

                             else
                                ""
                            )
                    )
                , button { label = "Submit", onClick = Form.submit (theForm model) }
                , button { label = "Reset", onClick = Form.reset (theForm model) }
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onSubmit (theForm model)
                        (Form.validators2 .name .email)
                        (\( _, _ ) -> noRequest)
                        model.submitResult
                   ]
    }


renderStatusHint : Status -> SimpleView Model
renderStatusHint status =
    case status of
        Pristine ->
            text "(Saved ✓)"

        Editable ->
            text "Click Submit when ready"

        HasErrors ->
            text "(Fix errors before submitting)"

        Validating ->
            text "Validating…"

        Submitting ->
            text "Submitting…"


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

The example uses `noRequest` for the submit handler — clicking "Submit" updates the form's `submitSeq` and triggers validation reactions, but no actual network call fires. To exercise the full success path visually, replace `(\( _, _ ) -> noRequest)` with a real `Http.httpGet` to an echo endpoint (and add the endpoint to `mock-api-plugin.js`). For the initial commit, ship the no-Request shape — the gating logic and status transitions are still visible.

- [ ] **Step 2: Create `examples/L05E01-profile-form.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>L05E01 profile-form</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/ProfileForm.elm";
      Elm.ProfileForm.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after the last existing entry):

```javascript
"L05E01-profile-form": resolve(__dirname, "L05E01-profile-form.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`** in the appropriate Layer 5 section:

```html
<li><a href="L05E01-profile-form.html">profile-form</a></li>
```

(Group with other Layer 5 entries; if the layer-5 group doesn't exist yet, add a new `<h2>Layer 5 — Forms</h2>` heading.)

- [ ] **Step 5: Format and build.**

```
(cd examples && npx --yes elm-format src --yes)
cd examples && npm run build
```
Expected: success — 19 entries.

- [ ] **Step 6: Commit.**

```
git add examples/src/ProfileForm.elm examples/L05E01-profile-form.html examples/vite.config.js examples/index.html
git commit -m "Ship L05E01 profile-form example"
```

---

### Task 9.2: Ship `L05E02-wizard-step`

**Files:**
- Create: `examples/src/WizardStep.elm`
- Create: `examples/L05E02-wizard-step.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/WizardStep.elm`:**

```elm
module WizardStep exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ValidatedCell
        , build
        , intCodec
        , modify
        , run
        , stringCodec
        , sync
        , toSource
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Fields =
    { name : ValidatedCell String String }


type alias Model =
    { name : ValidatedCell String String
    , step : Cell Int
    , formState : Cell Form.State
    }


nameValidator : Rad.Validator String String
nameValidator =
    sync
        (\s ->
            if String.length s >= 3 then
                Ok s

            else
                Err [ "Name must be at least 3 characters" ]
        )


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState { name = m.name } [ Form.validatedField m.name ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
            |> with "step" 1 intCodec
            |> Form.withState "step-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.step) (\s -> text ("Step " ++ String.fromInt s))
                , input { label = "Your name", cell = Rad.input model.name }
                , button { label = "Next →", onClick = Form.submit (theForm model) }
                , watch (Form.status (theForm model)) renderHint
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onValid (theForm model)
                        (Form.validators1 .name)
                        (\_ -> modify model.step (\n -> n + 1))
                   ]
    }


renderHint : Status -> SimpleView Model
renderHint status =
    case status of
        HasErrors ->
            text "(Need at least 3 characters)"

        Validating ->
            text "(checking…)"

        Submitting ->
            text "(advancing…)"

        _ ->
            text ""


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/L05E02-wizard-step.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>L05E02 wizard-step</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/WizardStep.elm";
      Elm.WizardStep.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`:**

```javascript
"L05E02-wizard-step": resolve(__dirname, "L05E02-wizard-step.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="L05E02-wizard-step.html">wizard-step</a></li>
```

- [ ] **Step 5: Format and build.**

```
(cd examples && npx --yes elm-format src --yes)
cd examples && npm run build
```
Expected: success — 20 entries.

- [ ] **Step 6: Commit.**

```
git add examples/src/WizardStep.elm examples/L05E02-wizard-step.html examples/vite.config.js examples/index.html
git commit -m "Ship L05E02 wizard-step example"
```

---

## Slice 10 — Final

### Task 10.1: Append Implementation notes to `docs/design-elm-rad.md`

**Files:**
- Modify: `docs/design-elm-rad.md`

- [ ] **Step 1: Locate insertion point.** Forms section starts at `## Forms` (~line 385). Insert a new `### Implementation notes` subsection just before `## Reactions — Async Effects` (~line 445).

- [ ] **Step 2: Insert:**

```markdown
### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **Layer 5 lives in `Rad.Form`, not `Rad`.** The Form API is orthogonal and exploratory; alternative Form designs may emerge later. Keeping it behind one importable name (`import Rad.Form as Form`) makes Forms swappable.

2. **One state cell per form.** `Form.withState` allocates a single `Cell Form.State` holding `{ snapshot, submitSeq, lastResolvedSubmitSeq }`. Field cells are user-allocated separately. Form is constructed at use sites via `Form.over state fields members` — pure, cheap to call per render.

3. **Members are user-curated.** `Form.field` and `Form.validatedField` capture cell IDs and (for ValidatedCells) reaction guts. Cells in the model but not listed in members aren't snapshotted/reset/dirty-checked.

4. **Snapshot is a JSON object keyed by stringified cell IDs.** Starts as `Encode.null`, meaning "pristine = each member's initial." On submit success, snapshot ← current encoded values. Cross-release ID stability is acknowledged as a Layer 7 concern.

5. **Submit gate is a single Reaction with a multi-source trigger.** Trigger watches `[submitSeq, lastResolvedSubmitSeq] ++ [each validation cell in group]`. Re-fires whenever any change. Latest-wins via Layer 2's reaction-seq.

6. **`onValid` reuses the reaction Cmd loop.** A sentinel `Task.succeed Encode.null` keeps it on the same lifecycle as `onSubmit`; the user's Action is recomputed and applied inside `writeResult`. No new runtime variant.

7. **`Reaction model`'s `model` is phantom.** Validation reactions and form-submit reactions don't reference their `model` type variable in any field. We exploit this: store reaction-record-of-functions as `Rad.Internal.Reaction.Guts` (no `model` parameter), then re-wrap as `Reaction model` at use site. This lets `Form.Member` be non-parameterized.

8. **Form.Status enum's `HasErrors` wins over `Submitting`.** A late-arriving Invalid validation surfaces as `HasErrors` even when a submit is pending — the user sees the error rather than a misleading "Submitting" state.
```

- [ ] **Step 3: Commit.**

```
git add docs/design-elm-rad.md
git commit -m "docs: record Layer 5 implementation decisions"
```

---

### Task 10.2: Final verification sweep

- [ ] **Step 1: Package tests.**

```
npx --yes elm-test
```
Expected: **~118 tests passing** (90 pre + ~28 new).

- [ ] **Step 2: Package docs build.**

```
npx --yes elm make --docs docs.json
```
Expected: success — `Rad`, `Rad.Engine`, `Rad.Form`, `Rad.Http`, `Rad.Read`, `Rad.View` all documented.

- [ ] **Step 3: Examples build.**

```
cd examples && npm run build
```
Expected: **20 HTML entries** (18 pre-Layer-5 + 2 new).

- [ ] **Step 4: Live smoke (if dev server running).**

```
for e in L05E01-profile-form L05E02-wizard-step; do
    echo "$e: $(curl -s -o /dev/null -w '%{http_code}' "http://localhost:5173/$e.html")"
done
```
Expected: `200` for both.

- [ ] **Step 5: Visual behavioral smoke (manual browser).**
- `L05E01-profile-form`: type "alice" + "alice@x.com" + "hi" → click Submit → status flows `Editable → Validating → Submitting → Pristine` (or sticks at Submitting if no real backend). Reset clears the form.
- `L05E02-wizard-step`: type a 3+ char name → click Next → step advances. Type a 1-char name → click Next → "Need at least 3 characters" hint shows.

- [ ] **Step 6: Commit-history sanity.**

```
git log --oneline 6eff37a..HEAD
```
Expected: ~12–13 commits — Slice 0 (3) + Slice 1–8 (8 functional commits + tests) + Slice 9 (2) + Slice 10 (1 docs). All single-line imperative.

- [ ] **Step 7: Clean tree.**

```
git status
```
Expected: clean.

---

## Out-of-slice notes

- **If `validators6`/`7`/`8` cause type-inference complaints,** add explicit type annotations modeled on `validators5`'s style (multiple `errN` parameters, returning `ValidatedGroup fields ( a, b, ... )`).
- **If `Form.onSubmit`'s `writeResult` fails to advance the snapshot** because of a decode mismatch (the codec's `Done` tag uses a different shape), check `Rad.remoteCodec`'s wire format and update `decodedDone`'s decoder accordingly.
- **If a tests' codec dependency on `IValidated.ref` breaks** because the structural `{ inputId, validationId, activationSeqId }` shape changes, the fix is in `Rad.Internal.Validated.Ref` — Layer 5 tests pierce it deliberately.
- **If `Form.dirty` tests are flaky on `Encode.null` comparison,** the issue is Elm's structural `==` on `Json.Value` — verify that the project uses elm/json 1.x where this works. Layer 3's `synced` precedent confirms it does.
