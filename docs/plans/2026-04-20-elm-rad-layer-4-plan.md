# elm-rad Layer 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 4 — validated cells. Add `ValidatedCell err a` with opaque `Validator err a` (sync/async/compose builders), a `Validation err a` lifecycle state, `validate`/`resetValidation` actions, and a `validationReactions` helper that users compose into `AppDef.reactions`. Plus three example apps. Purely additive on Layer 3.

**Architecture:** Each `ValidatedCell` owns three Registry slots (input, validation state, activation seq). `validate` bumps the activation seq; the validation reaction's trigger is `[input, activationSeq]` encoded as JSON. When activation seq > 0, the reaction dispatches the validator through Layer 2's reaction machinery; latest-wins is inherited. Validators are opaque: `sync`, `async`, `compose`. Sync validators dispatch through the Cmd loop (one-frame Checking flash accepted).

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x, no new package dependencies (uses existing `elm/core` `Task`). Vite 6, `vite-plugin-elm`.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per memory `feedback_commit_cadence.md`). Each commit must be reviewable on its own and must leave the tree green.
- **One task = one commit** unless a task header says otherwise.
- **Before every commit that touches `.elm` files, run `elm-format`** (per memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes` (from repo root).
  - Examples: `npx --yes elm-format src --yes` (from `examples/`).
  - Stage any reformatting in the same commit.
- Verification: `npx --yes elm-test` (from repo root); `cd examples && npm run build`.
- **Commit messages are single-line imperative** (`Add X`, `Ship Y`). No Co-Authored-By trailers unless explicitly requested.

**Design-doc correction (flagged here, applied throughout):**
The Layer 4 design doc's Section 3 omits `Codec err` from `withValidated`'s signature. It is **required** — the runtime must encode `Invalid (List err)` into the registry, which needs `err -> Value`. This plan uses:

```elm
withValidated :
    String -> a -> Codec a -> Codec err -> Validator err a
    -> CellBuilder (ValidatedCell err a -> rest) -> CellBuilder rest
```

Call sites: `build Model |> withValidated "name" "" stringCodec stringCodec (sync notEmpty)`.

**One new combinator added here (not in design doc), needed by the `username-available` example:**

```elm
andThenRequest : (a -> Result err b) -> Request err a -> Request err b
```

Transforms a `Request`'s success value into either success or failure. Without it, the async validator can't short-circuit on the HTTP response's `available: false` field without reaching into `Rad.Internal.Request`. Added in Slice 6, one small commit with a test in `RequestTest`.

**Module layout at the end:**

```
src/
  Rad.elm                         ← + Validation, validationCodec, Validator,
                                    sync/async/compose, ValidatedCell, withValidated,
                                    input, validation, validate, resetValidation,
                                    validationReactions, andThenRequest
  Rad/
    Engine.elm                    ← unchanged
    Http.elm                      ← unchanged
    Read.elm                      ← unchanged
    View.elm                      ← unchanged
    Internal/
      Action.elm                  ← unchanged
      Debounced.elm               ← unchanged
      Msg.elm                     ← unchanged
      Reaction.elm                ← unchanged
      Registry.elm                ← unchanged
      Request.elm                 ← unchanged (andThenRequest lives in Rad, not Internal)
      Source.elm                  ← unchanged
      Validated.elm               ← NEW: Validator, ValidatedCell, Core, Ref,
                                    core, ref, runSyncOnly, applyValidator,
                                    validationReaction
tests/
  <Layer 0-3 suites unchanged>
  ValidatedTest.elm               ← NEW
  ValidatorTest.elm               ← NEW
  ValidatedLifecycleTest.elm      ← NEW
  ValidatedLatestWinsTest.elm     ← NEW
  RequestTest.elm                 ← MODIFIED: add andThenRequest tests
examples/
  elm.json                        ← unchanged
  vite.config.js                  ← + 3 new entries
  mock-api-plugin.js              ← + /api/username-check endpoint
  index.html                      ← + 3 new links
  required-name.html              ← NEW
  email-format.html               ← NEW
  username-available.html         ← NEW
  src/
    RequiredName.elm              ← NEW
    EmailFormat.elm               ← NEW
    UsernameAvailable.elm         ← NEW
    SimpleView.elm                ← unchanged
docs/
  design-elm-rad.md               ← Validation section gains Implementation notes subsection
```

**Expected test count after Layer 4:** 48 (pre) + ~19 new = **67** total. Broken down per slice in each task.

---

## Slice 1 — Internal module + `withValidated` builder

### Task 1.1: Create `Rad.Internal.Validated` with types and accessors

**Files:**
- Create: `src/Rad/Internal/Validated.elm`

- [ ] **Step 1: Create the module** with types + accessors only (no applyValidator or validationReaction yet — those land later):

```elm
module Rad.Internal.Validated exposing
    ( Core
    , Ref
    , Validation(..)
    , ValidatedCell(..)
    , Validator(..)
    , core
    , ref
    )

{-| Internal shape of `ValidatedCell err a`. The constructor is exposed so
that `Rad` (for `input`, `validation`, `validate`, etc.) can pattern-match.
User code only sees `Rad.ValidatedCell err a`, opaquely.
-}

import Json.Decode as Decode
import Rad.Internal.Request as IRequest


type Validation err a
    = Dormant
    | Checking
    | Valid a
    | Invalid (List err)


type Validator err a
    = Sync (a -> Result (List err) a)
    | Async (a -> IRequest.Request (List err) a)
    | Compose (List (Validator err a))


type ValidatedCell err a
    = ValidatedCell (Core err a)


type alias Core err a =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , validationCodec :
        { encode : Validation err a -> Decode.Value
        , decode : Decode.Decoder (Validation err a)
        }
    , validator : Validator err a
    , initial : a
    }


core : ValidatedCell err a -> Core err a
core (ValidatedCell c) =
    c


{-| A type-erased slice used by reactions and tests. No `err`/`a` type
variables — values are already encoded by the time they flow through.
-}
type alias Ref =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    }


ref : ValidatedCell err a -> Ref
ref (ValidatedCell c) =
    { inputId = c.inputId
    , validationId = c.validationId
    , activationSeqId = c.activationSeqId
    }
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm make src/Rad/Internal/Validated.elm --output=/dev/null`
Expected: success.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Validated.elm
git commit -m "Add internal ValidatedCell type"
```

---

### Task 1.2: Expose `Validation(..)`, `validationCodec`, `ValidatedCell`, `withValidated`; add `ValidatedTest`

**Atomic commit.** Adds the public surface and first test suite together.

**Files:**
- Modify: `src/Rad.elm` (exposing list, import, body)
- Create: `tests/ValidatedTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/ValidatedTest.elm`:

```elm
module ValidatedTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( Validation(..)
        , ValidatedCell
        , build
        , stringCodec
        , validationCodec
        , withValidated
        )
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : IValidated.Validator String String
nameValidator =
    IValidated.Sync Ok


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec nameValidator


suite : Test
suite =
    describe "withValidated"
        [ test "allocates three Registry slots with correct initial values" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    r =
                        IValidated.ref model.name

                    decodeString id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)

                    decodeInt id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)

                    decodeValidation id =
                        Registry.get id registry
                            |> Maybe.andThen
                                (Decode.decodeValue
                                    (validationCodec stringCodec stringCodec).decode
                                    >> Result.toMaybe
                                )
                in
                Expect.equal
                    { input = Just "hello"
                    , validation = Just Dormant
                    , activationSeq = Just 0
                    }
                    { input = decodeString r.inputId
                    , validation = decodeValidation r.validationId
                    , activationSeq = decodeInt r.activationSeqId
                    }
        , test "IDs are distinct and sequential" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init

                    r =
                        IValidated.ref model.name
                in
                Expect.equal
                    { raw = r.inputId, settled = r.validationId, seq = r.activationSeqId }
                    { raw = 0, settled = 1, seq = 2 }
        , test "validationCodec round-trips Dormant" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode Dormant
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok Dormant)
        , test "validationCodec round-trips Checking" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode Checking
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok Checking)
        , test "validationCodec round-trips Valid" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode (Valid "yes")
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok (Valid "yes"))
        , test "validationCodec round-trips Invalid with multiple errors" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode (Invalid [ "oops", "again" ])
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok (Invalid [ "oops", "again" ]))
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ValidatedTest.elm`
Expected: compile error — `Rad.Validation`, `Rad.ValidatedCell`, `Rad.validationCodec`, `Rad.withValidated` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `Validation(..)`, `validationCodec`, `ValidatedCell`, `withValidated` after the existing DebouncedCell entries (in order: after `synced, commit, revert` add a new line):

```elm
    , ValidatedCell, withValidated, Validation(..), validationCodec
```

Update the `@docs` block accordingly — add a new line:

```elm
@docs ValidatedCell, withValidated, Validation, validationCodec
```

- [ ] **Step 4: Add import** (alphabetical, after `Rad.Internal.Source`):

```elm
import Rad.Internal.Validated as IValidated
```

- [ ] **Step 5: Add body entries** (place after the DebouncedCell block, before the `Source` / `toSource` block):

```elm
{-| A cell with a reactive validation lifecycle. Holds a writable input value
and a derived `Validation err a` state. Constructed via `withValidated`.
Opaque.
-}
type alias ValidatedCell err a =
    IValidated.ValidatedCell err a


{-| The validation lifecycle state.
-}
type alias Validation err a =
    IValidated.Validation err a


{-| A codec for `Validation err a` given codecs for the error and value types.

The wire format is a tagged object: `{"tag":"Dormant"}`, `{"tag":"Checking"}`,
`{"tag":"Valid","value":<valueEncoded>}`,
`{"tag":"Invalid","errors":[<errEncoded>, ...]}`.
-}
validationCodec : Codec err -> Codec a -> Codec (IValidated.Validation err a)
validationCodec errCodec valueCodec =
    let
        encode v =
            case v of
                IValidated.Dormant ->
                    Encode.object [ ( "tag", Encode.string "Dormant" ) ]

                IValidated.Checking ->
                    Encode.object [ ( "tag", Encode.string "Checking" ) ]

                IValidated.Valid a ->
                    Encode.object
                        [ ( "tag", Encode.string "Valid" )
                        , ( "value", valueCodec.encode a )
                        ]

                IValidated.Invalid errs ->
                    Encode.object
                        [ ( "tag", Encode.string "Invalid" )
                        , ( "errors", Encode.list errCodec.encode errs )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Dormant" ->
                                Decode.succeed IValidated.Dormant

                            "Checking" ->
                                Decode.succeed IValidated.Checking

                            "Valid" ->
                                Decode.map IValidated.Valid
                                    (Decode.field "value" valueCodec.decode)

                            "Invalid" ->
                                Decode.map IValidated.Invalid
                                    (Decode.field "errors" (Decode.list errCodec.decode))

                            other ->
                                Decode.fail ("unknown Validation tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }


{-| Add a validated cell to the builder. Allocates three Registry slots
(input, validation state, activation sequence counter) seeded from `initial`
and Dormant.
-}
withValidated :
    String
    -> a
    -> Codec a
    -> Codec err
    -> IValidated.Validator err a
    -> CellBuilder (ValidatedCell err a -> rest)
    -> CellBuilder rest
withValidated _ initial codec errCodec validator (CellBuilder b) =
    let
        inputId =
            b.nextId

        validationId =
            b.nextId + 1

        activationSeqId =
            b.nextId + 2

        valCodec =
            validationCodec errCodec codec

        cell =
            IValidated.ValidatedCell
                { inputId = inputId
                , validationId = validationId
                , activationSeqId = activationSeqId
                , codec = codec
                , validationCodec = valCodec
                , validator = validator
                , initial = initial
                }

        encodedInitial =
            codec.encode initial

        encodedDormant =
            valCodec.encode IValidated.Dormant
    in
    CellBuilder
        { nextId = b.nextId + 3
        , metas =
            ( activationSeqId, Encode.int 0 )
                :: ( validationId, encodedDormant )
                :: ( inputId, encodedInitial )
                :: b.metas
        , ctor = b.ctor cell
        }
```

Note the `Validation(..)` alias exposes the constructors via re-import. Because `Validation` is re-exported from the internal module, users can write `Rad.Dormant`, `Rad.Valid x`, etc., and pattern-match in views.

Wait — `type alias Validation err a = IValidated.Validation err a` does not re-export constructors. To expose them, we need `import Rad.Internal.Validated as IValidated exposing (Validation(..))` in `Rad.elm`. Check this. Let's update the import:

- [ ] **Step 5b: Update the import** to expose Validation constructors:

```elm
import Rad.Internal.Validated as IValidated exposing (Validation(..))
```

And in the exposing list, `Validation(..)` re-exposes the imported type's constructors. `ValidatedCell` stays opaque (no `(..)` on it) — only the type alias is re-exported.

- [ ] **Step 6: Run tests to confirm pass.**

Run: `npx --yes elm-test`
Expected: all suites pass + 6 new tests in ValidatedTest = 54 total.

- [ ] **Step 7: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 8: Commit.**

```bash
git add src/Rad.elm tests/ValidatedTest.elm
git commit -m "Expose Validation, validationCodec, ValidatedCell, withValidated"
```

---

## Slice 2 — Builders + Source/Action accessors

### Task 2.1: Expose `sync`, `async`, `compose` builder functions

**Files:**
- Modify: `src/Rad.elm` (exposing, @docs, body)
- Modify: `tests/ValidatedTest.elm` (rewrite the test's `nameValidator` to use public builder)

- [ ] **Step 1: Update `tests/ValidatedTest.elm`.** Change the validator constructor to use the public API, proving it exists:

Replace the top imports to drop `Rad.Internal.Validated as IValidated` where not needed (keep it for `ref`), and replace the validator:

```elm
import Rad exposing (..)  -- or keep explicit list; add `sync` to it
```

And the validator:

```elm
nameValidator : Rad.Validator String String
nameValidator =
    Rad.sync Ok
```

Adjust the existing import list in the test module to include `Validator, sync`:

```elm
import Rad
    exposing
        ( Validation(..)
        , ValidatedCell
        , Validator
        , build
        , stringCodec
        , sync
        , validationCodec
        , withValidated
        )
```

And change `IValidated.Validator String String` / `IValidated.Sync Ok` to `Validator String String` / `sync Ok` in the `nameValidator` definition.

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ValidatedTest.elm`
Expected: compile error — `Rad.Validator` and `Rad.sync` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `Validator, sync, async, compose` after `withValidated`:

```elm
    , Validator, sync, async, compose
```

Update `@docs`:

```elm
@docs Validator, sync, async, compose
```

- [ ] **Step 4: Add body entries** (after `withValidated`):

```elm
{-| Opaque validator. Build via `sync`, `async`, or `compose`.
-}
type alias Validator err a =
    IValidated.Validator err a


{-| A synchronous validator. Returns `Ok a` if valid; `Err errs` with a list
of errors otherwise.
-}
sync : (a -> Result (List err) a) -> Validator err a
sync =
    IValidated.Sync


{-| An asynchronous validator. Builds a `Request` whose success value is the
valid `a`; failure is a list of errors. HTTP-backed validators typically
build via `Rad.Http.httpGet` + `mapRequestError`.
-}
async : (a -> Request (List err) a) -> Validator err a
async =
    IValidated.Async


{-| A composed validator. Runs the validators left-to-right; if any one
returns `Invalid`, subsequent validators are skipped. `Valid` propagates the
(possibly transformed) value to the next validator.
-}
compose : List (Validator err a) -> Validator err a
compose =
    IValidated.Compose
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 54 tests.

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm tests/ValidatedTest.elm
git commit -m "Add sync, async, compose validator builders"
```

---

### Task 2.2: Add `input` and `validation` source accessors

**Files:**
- Modify: `src/Rad.elm` (exposing, @docs, body)
- Modify: `tests/ValidatedTest.elm` (add two new assertions)

- [ ] **Step 1: Extend the test suite.** Append two new tests inside the `describe` body after the existing six:

```elm
        , test "input returns a Cell whose id matches inputId" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    inputCell =
                        Rad.input model.name
                in
                Expect.equal "hello"
                    (Rad.readSource (Rad.toSource inputCell) registry)
        , test "validation returns a Source reading the validation state" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal Dormant
                    (Rad.readSource (Rad.validation model.name) registry)
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ValidatedTest.elm`
Expected: compile error — `Rad.input` and `Rad.validation` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `input, validation` after `compose`:

```elm
    , input, validation
```

Update `@docs`:

```elm
@docs input, validation
```

- [ ] **Step 4: Add body entries.** Note: `input` needs to construct a `Cell a`, which means we need access to the `Cell` constructor. Since `Cell` is defined in `Rad.elm` directly, this works.

```elm
{-| The writable input cell of a validated cell. Use with `set`, `modify`,
`copy`, or view bindings (`bind (input vcell)`).
-}
input : ValidatedCell err a -> Cell a
input vcell =
    let
        c =
            IValidated.core vcell
    in
    Cell { id = c.inputId, key = "", codec = c.codec, initial = c.initial }


{-| A `Source` for the validation state of a validated cell.
-}
validation : ValidatedCell err a -> Source (Validation err a)
validation vcell =
    let
        c =
            IValidated.core vcell
    in
    IS.Source
        { read =
            \registry ->
                case Registry.get c.validationId registry of
                    Just v ->
                        Result.withDefault Dormant
                            (Decode.decodeValue c.validationCodec.decode v)

                    Nothing ->
                        Dormant
        , codec = c.validationCodec
        }
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 56 tests (54 + 2 new).

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm tests/ValidatedTest.elm
git commit -m "Add input and validation source accessors"
```

---

### Task 2.3: Add `validate` and `resetValidation` actions + `ValidatedLifecycleTest`

**Files:**
- Modify: `src/Rad.elm` (exposing, @docs, body)
- Create: `tests/ValidatedLifecycleTest.elm`

- [ ] **Step 1: Create `tests/ValidatedLifecycleTest.elm`:**

```elm
module ValidatedLifecycleTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( Validation(..)
        , ValidatedCell
        , build
        , resetValidation
        , stringCodec
        , sync
        , validate
        , validationCodec
        , withValidated
        )
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : Rad.Validator String String
nameValidator =
    sync Ok


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec nameValidator


readSeq : Int -> Registry.Registry -> Maybe Int
readSeq id registry =
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)


readValidation : Int -> Registry.Registry -> Maybe (Validation String String)
readValidation id registry =
    let
        c =
            validationCodec stringCodec stringCodec
    in
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue c.decode >> Result.toMaybe)


suite : Test
suite =
    describe "ValidatedCell lifecycle actions"
        [ test "validate increments activationSeqId from 0 to 1" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.name) registry0

                    r =
                        IValidated.ref model.name
                in
                Expect.equal (Just 1) (readSeq r.activationSeqId registry1)
        , test "two consecutive validate calls produce seq 2" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry2 =
                        registry0
                            |> Rad.applyAction (validate model.name)
                            |> Rad.applyAction (validate model.name)

                    r =
                        IValidated.ref model.name
                in
                Expect.equal (Just 2) (readSeq r.activationSeqId registry2)
        , test "resetValidation writes Dormant and resets seq to 0" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.name) registry0

                    registry2 =
                        Rad.applyAction (resetValidation model.name) registry1

                    r =
                        IValidated.ref model.name
                in
                Expect.equal
                    { seq = Just 0, state = Just Dormant }
                    { seq = readSeq r.activationSeqId registry2
                    , state = readValidation r.validationId registry2
                    }
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ValidatedLifecycleTest.elm`
Expected: compile error — `Rad.validate`, `Rad.resetValidation` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `validate, resetValidation` after `input, validation`:

```elm
    , validate, resetValidation
```

Update `@docs`:

```elm
@docs validate, resetValidation
```

- [ ] **Step 4: Add body entries** (after `validation`):

```elm
{-| Activate validation. Bumps the activation sequence counter; the
validation reaction re-fires with the current input, transitioning from
`Dormant` through `Checking` to `Valid` / `Invalid`. Repeated calls bump
the counter again, forcing re-validation even if the input is unchanged.
-}
validate : ValidatedCell err a -> Action model
validate vcell =
    let
        c =
            IValidated.core vcell
    in
    IA.Action
        (\registry ->
            let
                currentSeq =
                    Registry.get c.activationSeqId registry
                        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                        |> Maybe.withDefault 0
            in
            Registry.insert c.activationSeqId (Encode.int (currentSeq + 1)) registry
        )


{-| Reset validation to `Dormant`. Writes `Dormant` to the validation state
and resets the activation sequence to 0. Any in-flight async validator's
result is discarded by the validation reaction (it sees `SkipRequest`).
-}
resetValidation : ValidatedCell err a -> Action model
resetValidation vcell =
    let
        c =
            IValidated.core vcell
    in
    IA.Action
        (\registry ->
            registry
                |> Registry.insert c.validationId (c.validationCodec.encode Dormant)
                |> Registry.insert c.activationSeqId (Encode.int 0)
        )
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 59 tests (56 + 3 new).

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm tests/ValidatedLifecycleTest.elm
git commit -m "Add validate and resetValidation actions"
```

---

## Slice 3 — `applyValidator` + `ValidatorTest`

### Task 3.1: Add `runSyncOnly` + `applyValidator` + `ValidatorTest`

**Files:**
- Modify: `src/Rad/Internal/Validated.elm` (add helpers, update exposing)
- Create: `tests/ValidatorTest.elm`

- [ ] **Step 1: Create `tests/ValidatorTest.elm`:**

```elm
module ValidatorTest exposing (suite)

import Expect
import Rad exposing (Validation(..), async, compose, sync)
import Rad.Internal.Request as IRequest
import Rad.Internal.Validated as IValidated
import Task
import Test exposing (..)


suite : Test
suite =
    describe "Validator evaluation via runSyncOnly"
        [ test "Sync Ok returns Just (Valid a)" <|
            \_ ->
                IValidated.runSyncOnly (sync Ok) "hello"
                    |> Expect.equal (Just (Valid "hello"))
        , test "Sync Err returns Just (Invalid errs)" <|
            \_ ->
                let
                    v =
                        sync (\_ -> Err [ "bad" ])
                in
                IValidated.runSyncOnly v "hello"
                    |> Expect.equal (Just (Invalid [ "bad" ]))
        , test "Async returns Nothing (can't run sync)" <|
            \_ ->
                let
                    v =
                        async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                in
                IValidated.runSyncOnly v "hello"
                    |> Expect.equal Nothing
        , test "Compose [] returns Just (Valid value)" <|
            \_ ->
                IValidated.runSyncOnly (compose []) "hello"
                    |> Expect.equal (Just (Valid "hello"))
        , test "Compose [Sync Ok, Sync Ok] runs both" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\s -> Ok (s ++ "1"))
                            , sync (\s -> Ok (s ++ "2"))
                            ]
                in
                IValidated.runSyncOnly v "x"
                    |> Expect.equal (Just (Valid "x12"))
        , test "Compose [Sync Err, Sync Ok] short-circuits at first failure" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\_ -> Err [ "first" ])
                            , sync (\_ -> Err [ "second — should not run" ])
                            ]
                in
                IValidated.runSyncOnly v "x"
                    |> Expect.equal (Just (Invalid [ "first" ]))
        , test "Compose [Sync Err, Async ...] doesn't reach the async" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\_ -> Err [ "blocked" ])
                            , async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                            ]
                in
                IValidated.runSyncOnly v "x"
                    |> Expect.equal (Just (Invalid [ "blocked" ]))
        , test "Compose [Sync Ok, Async ...] reaches async, returns Nothing" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync Ok
                            , async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                            ]
                in
                IValidated.runSyncOnly v "hello"
                    |> Expect.equal Nothing
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/ValidatorTest.elm`
Expected: compile error — `IValidated.runSyncOnly` not found.

- [ ] **Step 3: Update `src/Rad/Internal/Validated.elm`.** Add `applyValidator` and `runSyncOnly` to the exposing list and body. New full exposing list:

```elm
module Rad.Internal.Validated exposing
    ( Core
    , Ref
    , Validation(..)
    , ValidatedCell(..)
    , Validator(..)
    , applyValidator
    , core
    , ref
    , runSyncOnly
    )
```

Add imports at the top:

```elm
import Task exposing (Task)
```

Add the two helpers at the end of the module:

```elm
{-| Run the sync portions of a validator without dispatching any async work.
Returns `Just settled` if a final state is reachable (all Sync, with or
without short-circuiting Compose), or `Nothing` if an Async must run.
Used by tests and (potentially) a future sync fast-path.
-}
runSyncOnly : Validator err a -> a -> Maybe (Validation err a)
runSyncOnly validator value =
    case validator of
        Sync f ->
            case f value of
                Ok a ->
                    Just (Valid a)

                Err errs ->
                    Just (Invalid errs)

        Async _ ->
            Nothing

        Compose validators ->
            runSyncCompose validators value


runSyncCompose : List (Validator err a) -> a -> Maybe (Validation err a)
runSyncCompose validators value =
    case validators of
        [] ->
            Just (Valid value)

        v :: rest ->
            case runSyncOnly v value of
                Nothing ->
                    Nothing

                Just (Valid currentValue) ->
                    runSyncCompose rest currentValue

                Just other ->
                    Just other


{-| Run a validator, producing a `Task` that resolves to the final
`Validation err a`. Sync paths resolve via `Task.succeed`. Async paths
dispatch their `Request` and fold the result. The error channel is `Never`
because failures are folded into `Invalid`.
-}
applyValidator : Validator err a -> a -> Task Never (Validation err a)
applyValidator validator value =
    case validator of
        Sync f ->
            case f value of
                Ok a ->
                    Task.succeed (Valid a)

                Err errs ->
                    Task.succeed (Invalid errs)

        Async buildReq ->
            case buildReq value of
                IRequest.NoRequest ->
                    Task.succeed (Valid value)

                IRequest.DispatchRequest task ->
                    task
                        |> Task.map Valid
                        |> Task.onError (\errs -> Task.succeed (Invalid errs))

        Compose validators ->
            applyCompose validators value


applyCompose : List (Validator err a) -> a -> Task Never (Validation err a)
applyCompose validators value =
    case validators of
        [] ->
            Task.succeed (Valid value)

        v :: rest ->
            applyValidator v value
                |> Task.andThen
                    (\vState ->
                        case vState of
                            Valid currentValue ->
                                applyCompose rest currentValue

                            _ ->
                                Task.succeed vState
                    )
```

- [ ] **Step 4: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 67 tests (59 + 8 new in ValidatorTest).

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad/Internal/Validated.elm tests/ValidatorTest.elm
git commit -m "Add runSyncOnly and applyValidator helpers"
```

---

## Slice 4 — `validationReactions` + trigger/latest-wins tests

### Task 4.1: Add `validationReaction` internal + `validationReactions` public

**Files:**
- Modify: `src/Rad/Internal/Validated.elm` (add `validationReaction`, expose)
- Modify: `src/Rad.elm` (expose `validationReactions`)

- [ ] **Step 1: Update `src/Rad/Internal/Validated.elm`.** Extend the exposing list with `validationReaction`:

```elm
module Rad.Internal.Validated exposing
    ( Core
    , Ref
    , Validation(..)
    , ValidatedCell(..)
    , Validator(..)
    , applyValidator
    , core
    , ref
    , runSyncOnly
    , validationReaction
    )
```

Add imports for `Rad.Internal.Reaction as IReaction` and `Rad.Internal.Registry as Registry exposing (Registry)`:

```elm
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry exposing (Registry)
```

Also need `Json.Encode as Encode` (for `Encode.int` in the trigger):

```elm
import Json.Encode as Encode
```

Add the new function at the end of the module:

```elm
{-| Build the reaction that powers a validated cell. The trigger combines
input value and activation seq (both JSON-encoded). When activation seq is
0, the reaction dispatches nothing. Otherwise it runs the validator through
Layer 2's reaction machinery, which handles latest-wins automatically.
-}
validationReaction : ValidatedCell err a -> IReaction.Reaction model
validationReaction vcell =
    let
        c =
            core vcell

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
    IReaction.Reaction
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
                            |> Task.map c.validationCodec.encode
                        )
        , writeLoading =
            \registry ->
                Registry.insert c.validationId
                    (c.validationCodec.encode Checking)
                    registry
        , writeResult =
            \encoded registry ->
                Registry.insert c.validationId encoded registry
        }
```

- [ ] **Step 2: Update `src/Rad.elm`.** Add `validationReactions` to the exposing list after `validate, resetValidation`:

```elm
    , validationReactions
```

Update `@docs`:

```elm
@docs validationReactions
```

Add the body entry (after `resetValidation`):

```elm
{-| The reaction(s) powering a validated cell's lifecycle. Returns a
single-element list so users can concatenate multiple validated cells'
reactions with their own:

    reactions =
        \model _ ->
            validationReactions model.name
                ++ validationReactions model.email
                ++ [ myOtherReaction ]

-}
validationReactions : ValidatedCell err a -> List (Reaction model)
validationReactions vcell =
    [ IValidated.validationReaction vcell ]
```

- [ ] **Step 3: Verify compilation + tests.**

Run: `npx --yes elm-test`
Expected: 67 tests still pass (no new tests yet).

- [ ] **Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 5: Commit.**

```bash
git add src/Rad/Internal/Validated.elm src/Rad.elm
git commit -m "Add validationReaction and validationReactions"
```

---

### Task 4.2: Extend `ValidatedLifecycleTest` with reaction-trigger semantics

**Files:**
- Modify: `tests/ValidatedLifecycleTest.elm`

- [ ] **Step 1: Append reaction-trigger tests** to the existing `describe` in `tests/ValidatedLifecycleTest.elm`. Add imports at the top:

```elm
import Rad.Internal.Reaction as IReaction
```

Append these tests to the `describe` list:

```elm
        , test "validationReactions returns exactly one Reaction" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 1 (List.length (Rad.validationReactions model.name))
        , test "readTrigger is stable when input and seq don't change" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name
                in
                Expect.equal
                    (Encode.encode 0 (r.readTrigger registry))
                    (Encode.encode 0 (r.readTrigger registry))
        , test "readTrigger changes when input changes" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    registry1 =
                        Rad.applyAction
                            (Rad.set (Rad.input model.name) "world")
                            registry0
                in
                Expect.notEqual
                    (Encode.encode 0 (r.readTrigger registry0))
                    (Encode.encode 0 (r.readTrigger registry1))
        , test "readTrigger changes when activationSeq changes" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    registry1 =
                        Rad.applyAction (Rad.validate model.name) registry0
                in
                Expect.notEqual
                    (Encode.encode 0 (r.readTrigger registry0))
                    (Encode.encode 0 (r.readTrigger registry1))
        , test "buildRequest returns SkipRequest when activationSeq is 0" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name
                in
                case r.buildRequest registry of
                    IReaction.SkipRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected SkipRequest when activationSeq is 0"
        , test "buildRequest returns DispatchTask after validate" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    registry1 =
                        Rad.applyAction (Rad.validate model.name) registry0
                in
                case r.buildRequest registry1 of
                    IReaction.DispatchTask _ ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected DispatchTask after validate"
        , test "writeLoading writes encoded Checking to validationId" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    registry1 =
                        r.writeLoading registry0
                in
                Expect.equal (Just Checking) (readValidation (IValidated.ref model.name).validationId registry1)
        ]
```

- [ ] **Step 2: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 74 tests (67 + 7 new).

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add tests/ValidatedLifecycleTest.elm
git commit -m "Test validationReaction trigger and dispatch semantics"
```

---

### Task 4.3: Add `ValidatedLatestWinsTest`

**Files:**
- Create: `tests/ValidatedLatestWinsTest.elm`

- [ ] **Step 1: Create `tests/ValidatedLatestWinsTest.elm`:**

```elm
module ValidatedLatestWinsTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( Validation(..)
        , ValidatedCell
        , build
        , stringCodec
        , sync
        , validationCodec
        , withValidated
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec (sync Ok)


readValidation : Int -> Registry.Registry -> Maybe (Validation String String)
readValidation id registry =
    let
        c =
            validationCodec stringCodec stringCodec
    in
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue c.decode >> Result.toMaybe)


suite : Test
suite =
    describe "Validated latest-wins"
        [ test "writeResult overwrites — runtime owns seq filtering" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    c =
                        validationCodec stringCodec stringCodec

                    encodedStale =
                        c.encode (Valid "stale")

                    encodedFresh =
                        c.encode (Valid "fresh")

                    registryBoth =
                        registry0
                            |> r.writeResult encodedStale
                            |> r.writeResult encodedFresh

                    registryFreshFirst =
                        registry0
                            |> r.writeResult encodedFresh
                in
                Expect.equal
                    (readValidation (IValidated.ref model.name).validationId registryBoth)
                    (readValidation (IValidated.ref model.name).validationId registryFreshFirst)
        , test "writeResult writes the exact bytes passed, no filtering" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        IValidated.validationReaction model.name

                    c =
                        validationCodec stringCodec stringCodec

                    invalidEncoded =
                        c.encode (Invalid [ "nope" ])

                    registry1 =
                        r.writeResult invalidEncoded registry0
                in
                Expect.equal (Just (Invalid [ "nope" ]))
                    (readValidation (IValidated.ref model.name).validationId registry1)
        ]
```

- [ ] **Step 2: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 76 tests (74 + 2 new).

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add tests/ValidatedLatestWinsTest.elm
git commit -m "Add ValidatedLatestWinsTest"
```

---

## Slice 5 — Sync examples

### Task 5.1: Ship `required-name` example

**Files:**
- Create: `examples/src/RequiredName.elm`
- Create: `examples/required-name.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/RequiredName.elm`.** Note on naming: `Rad.input` and `SimpleView.input` share the unqualified name. The three Layer 4 example modules uniformly resolve this by:
  - **Not** exposing `input` from `Rad` in the import list — always qualified as `Rad.input`.
  - Exposing `input` from `SimpleView` — used unqualified as `input`.

```elm
module RequiredName exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , Validation(..)
        , ValidatedCell
        , Validator
        , build
        , resetValidation
        , run
        , stringCodec
        , sync
        , validate
        , validation
        , validationReactions
        , withValidated
        )
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : Validator String String
nameValidator =
    sync
        (\s ->
            if String.trim s == "" then
                Err [ "name required" ]

            else
                Ok s
        )


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = Rad.input model.name }
                , button { label = "Validate", onClick = validate model.name }
                , button { label = "Reset", onClick = resetValidation model.name }
                , watch (validation model.name) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.name
    }


renderValidation : Validation String String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ looks good"

        Invalid errs ->
            text ("× " ++ String.join ", " errs)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/required-name.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>required-name</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/RequiredName.elm";
      Elm.RequiredName.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** `input` map, after `custom-triggers`:

```javascript
"required-name": resolve(__dirname, "required-name.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`** after `custom-triggers`:

```html
<li><a href="required-name.html">required-name</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 15 entries (index + 14 examples).

- [ ] **Step 7: Commit.**

```bash
git add examples/src/RequiredName.elm examples/required-name.html examples/vite.config.js examples/index.html
git commit -m "Ship required-name example"
```

---

### Task 5.2: Ship `email-format` example

**Files:**
- Create: `examples/src/EmailFormat.elm`
- Create: `examples/email-format.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/EmailFormat.elm`:**

```elm
module EmailFormat exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Codec
        , Validation(..)
        , ValidatedCell
        , Validator
        , build
        , resetValidation
        , run
        , stringCodec
        , sync
        , validate
        , validation
        , validationReactions
        , withValidated
        )
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type EmailError
    = Empty
    | MissingAt
    | TooLong


emailErrorCodec : Codec EmailError
emailErrorCodec =
    { encode =
        \err ->
            case err of
                Empty ->
                    Encode.object [ ( "tag", Encode.string "Empty" ) ]

                MissingAt ->
                    Encode.object [ ( "tag", Encode.string "MissingAt" ) ]

                TooLong ->
                    Encode.object [ ( "tag", Encode.string "TooLong" ) ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "Empty" ->
                            Decode.succeed Empty

                        "MissingAt" ->
                            Decode.succeed MissingAt

                        "TooLong" ->
                            Decode.succeed TooLong

                        other ->
                            Decode.fail ("unknown EmailError tag: " ++ other)
                )
    }


emailValidator : Validator EmailError String
emailValidator =
    sync
        (\s ->
            let
                errs =
                    List.filterMap identity
                        [ if s == "" then
                            Just Empty

                          else
                            Nothing
                        , if not (String.contains "@" s) then
                            Just MissingAt

                          else
                            Nothing
                        , if String.length s > 100 then
                            Just TooLong

                          else
                            Nothing
                        ]
            in
            if List.isEmpty errs then
                Ok s

            else
                Err errs
        )


type alias Model =
    { email : ValidatedCell EmailError String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "email" "" stringCodec emailErrorCodec emailValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Email", cell = Rad.input model.email }
                , button { label = "Validate", onClick = validate model.email }
                , button { label = "Reset", onClick = resetValidation model.email }
                , watch (validation model.email) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.email
    }


renderValidation : Validation EmailError String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ looks good"

        Invalid errs ->
            text ("× " ++ String.join ", " (List.map humanize errs))


humanize : EmailError -> String
humanize err =
    case err of
        Empty ->
            "email is required"

        MissingAt ->
            "missing @"

        TooLong ->
            "too long"


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/email-format.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>email-format</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/EmailFormat.elm";
      Elm.EmailFormat.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after `required-name`):

```javascript
"email-format": resolve(__dirname, "email-format.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="email-format.html">email-format</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 16 entries.

- [ ] **Step 7: Commit.**

```bash
git add examples/src/EmailFormat.elm examples/email-format.html examples/vite.config.js examples/index.html
git commit -m "Ship email-format example"
```

---

## Slice 6 — Async example + docs

### Task 6.1: Add `Rad.andThenRequest` combinator

**Files:**
- Modify: `src/Rad.elm` (exposing, body)
- Modify: `tests/RequestTest.elm` (add 2 tests)

- [ ] **Step 1: Extend `tests/RequestTest.elm`** with two new test cases inside the existing `describe`:

```elm
        , test "andThenRequest preserves NoRequest" <|
            \_ ->
                let
                    result =
                        Rad.andThenRequest (\_ -> Ok "x") Rad.noRequest
                in
                case result of
                    IR.NoRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected NoRequest"
        , test "andThenRequest wraps DispatchRequest" <|
            \_ ->
                let
                    base =
                        IR.DispatchRequest (Task.succeed 1)

                    result =
                        Rad.andThenRequest (\n -> Ok (n + 1)) base
                in
                case result of
                    IR.DispatchRequest _ ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected DispatchRequest"
```

Imports needed (check if already present): `import Task`.

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/RequestTest.elm`
Expected: compile error — `Rad.andThenRequest` not found.

- [ ] **Step 3: Update `src/Rad.elm` exposing list.** Add `andThenRequest` alongside `mapRequestError`:

Replace `, Request, noRequest, mapRequestError` with:

```elm
    , Request, noRequest, mapRequestError, andThenRequest
```

Update `@docs`:

```elm
@docs Request, noRequest, mapRequestError, andThenRequest
```

- [ ] **Step 4: Add body entry** (after `mapRequestError`):

```elm
{-| Transform a Request's success value via a function that may itself
short-circuit to the error channel.

Useful for chaining a sync check after an async request. Example: an HTTP
response whose body indicates whether the action succeeded at the domain
level:

    Http.httpGet handler url decoder
        |> mapRequestError (\netErr -> [ NetworkError netErr ])
        |> andThenRequest
            (\resp ->
                if resp.ok then
                    Ok resp.value

                else
                    Err [ DomainFailure ]
            )

-}
andThenRequest : (a -> Result err b) -> Request err a -> Request err b
andThenRequest f req =
    case req of
        IRequest.NoRequest ->
            IRequest.NoRequest

        IRequest.DispatchRequest task ->
            IRequest.DispatchRequest
                (task
                    |> Task.andThen
                        (\a ->
                            case f a of
                                Ok b ->
                                    Task.succeed b

                                Err errs ->
                                    Task.fail errs
                        )
                )
```

- [ ] **Step 5: Run tests.**

Run: `npx --yes elm-test`
Expected: all green, 78 tests (76 + 2 new).

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm tests/RequestTest.elm
git commit -m "Add Rad.andThenRequest combinator"
```

---

### Task 6.2: Add `/api/username-check` mock endpoint

**Files:**
- Modify: `examples/mock-api-plugin.js`

- [ ] **Step 1: Append a new middleware registration** to `examples/mock-api-plugin.js`, inside the `configureServer(server)` function, after the `/api/search` handler:

```javascript
      // GET /api/username-check?q=<name>
      // "taken" → unavailable; anything else → available
      server.middlewares.use("/api/username-check", (req, res, next) => {
        if (req.method !== "GET") return next();
        const url = new URL(req.url || "/", "http://localhost");
        const q = url.searchParams.get("q") || "";
        sendJson(res, { available: q !== "taken" }, 1500);
      });
```

- [ ] **Step 2: Commit (JS only, no elm-format needed).**

```bash
git add examples/mock-api-plugin.js
git commit -m "Add /api/username-check mock endpoint"
```

- [ ] **Step 3: Verify endpoint via curl** (against the user's running dev server — Vite hot-reloads config changes):

```bash
curl -s 'http://localhost:5173/api/username-check?q=alice'
```

Expected: `{"available":true}` after ~1.5s.

```bash
curl -s 'http://localhost:5173/api/username-check?q=taken'
```

Expected: `{"available":false}` after ~1.5s.

If the dev server isn't running, skip the verification — it'll be confirmed in Task 6.3 when the UsernameAvailable example exercises it.

---

### Task 6.3: Ship `username-available` example

**Files:**
- Create: `examples/src/UsernameAvailable.elm`
- Create: `examples/username-available.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/UsernameAvailable.elm`:**

```elm
module UsernameAvailable exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Codec
        , Validation(..)
        , ValidatedCell
        , Validator
        , andThenRequest
        , async
        , build
        , compose
        , mapRequestError
        , resetValidation
        , run
        , stringCodec
        , sync
        , validate
        , validation
        , validationReactions
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type UsernameError
    = EmptyName
    | AlreadyTaken
    | LookupFailed RequestError


usernameErrorCodec : Codec UsernameError
usernameErrorCodec =
    { encode =
        \err ->
            case err of
                EmptyName ->
                    Encode.object [ ( "tag", Encode.string "EmptyName" ) ]

                AlreadyTaken ->
                    Encode.object [ ( "tag", Encode.string "AlreadyTaken" ) ]

                LookupFailed reqErr ->
                    Encode.object
                        [ ( "tag", Encode.string "LookupFailed" )
                        , ( "cause", requestErrorCodec.encode reqErr )
                        ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "EmptyName" ->
                            Decode.succeed EmptyName

                        "AlreadyTaken" ->
                            Decode.succeed AlreadyTaken

                        "LookupFailed" ->
                            Decode.map LookupFailed
                                (Decode.field "cause" requestErrorCodec.decode)

                        other ->
                            Decode.fail ("unknown UsernameError tag: " ++ other)
                )
    }


availabilityDecoder : Decode.Decoder Bool
availabilityDecoder =
    Decode.field "available" Decode.bool


usernameValidator : Validator UsernameError String
usernameValidator =
    compose
        [ sync
            (\s ->
                if String.trim s == "" then
                    Err [ EmptyName ]

                else
                    Ok s
            )
        , async
            (\name ->
                Http.httpGet prodHandler
                    ("/api/username-check?q=" ++ name)
                    availabilityDecoder
                    |> mapRequestError (\netErr -> [ LookupFailed netErr ])
                    |> andThenRequest
                        (\available ->
                            if available then
                                Ok name

                            else
                                Err [ AlreadyTaken ]
                        )
            )
        ]


type alias Model =
    { username : ValidatedCell UsernameError String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "username" "" stringCodec usernameErrorCodec usernameValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Username", cell = Rad.input model.username }
                , button { label = "Validate", onClick = validate model.username }
                , button { label = "Reset", onClick = resetValidation model.username }
                , watch (validation model.username) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.username
    }


renderValidation : Validation UsernameError String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ available"

        Invalid errs ->
            text ("× " ++ String.join ", " (List.map humanize errs))


humanize : UsernameError -> String
humanize err =
    case err of
        EmptyName ->
            "username is required"

        AlreadyTaken ->
            "already taken"

        LookupFailed _ ->
            "lookup failed"


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/username-available.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>username-available</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/UsernameAvailable.elm";
      Elm.UsernameAvailable.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after `email-format`):

```javascript
"username-available": resolve(__dirname, "username-available.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="username-available.html">username-available</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 17 entries (index + 16 examples).

- [ ] **Step 7: Live curl check (optional — against running dev server):**

```bash
curl -s 'http://localhost:5173/api/username-check?q=alice'
```

Expected: `{"available":true}` after ~1.5s.

- [ ] **Step 8: Commit.**

```bash
git add examples/src/UsernameAvailable.elm examples/username-available.html examples/vite.config.js examples/index.html
git commit -m "Ship username-available example"
```

---

### Task 6.4: Append Implementation notes to `docs/design-elm-rad.md`

**Files:**
- Modify: `docs/design-elm-rad.md`

- [ ] **Step 1: Locate insertion point.** The Validation section starts at around line 335 (`## Validation`). It has subsections through "Persistence of validation state" (around line 363). The next top-level section begins with `## Forms` (around line 369). Insert a new `### Implementation notes` subsection **between** the last existing Validation subsection and the `## Forms` heading — effectively at the end of the Validation section.

- [ ] **Step 2: Insert the subsection.** Add this content immediately before the `## Forms` heading:

```markdown
### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **Three Registry slots per `ValidatedCell`.** `withValidated` allocates input, validation state, and a per-cell activation sequence counter. The input slot holds the encoded `a`; the validation slot holds encoded `Validation err a`; the activation seq slot holds an `Int` (0 when Dormant, >0 when active).

2. **Validator constructors are opaque.** Users build validators via `sync`, `async`, `compose`. The internal `Validator` constructors live in `Rad.Internal.Validated` and are not re-exported. This keeps the public surface small and lets later layers add validator variants (e.g., `deferred`, `whenDirty`) without breaking call sites.

3. **Reactions are reused; no new Msg variants.** Each `ValidatedCell` produces one `Reaction` (built by hand, not via `Rad.on`, because `on` writes to `Cell (Remote err r)` and we need to write to `Cell (Validation err a)`). The reaction's trigger is `[input value, activation seq]` encoded as a JSON list. Layer 2's reaction-seq handles latest-wins.

4. **Sync validators dispatch through the Cmd loop.** A pure-sync validator briefly shows `Checking` (one render frame) before landing on `Valid` / `Invalid`. Uniform dispatch through the reaction was chosen over a sync fast-path because the flash is imperceptible in practice; fast-path deferred if measured as a problem.

5. **Activation via an `Int` counter, not a `Bool`.** `validate` bumps the counter (0 → 1 → 2 → ...), which changes the reaction's trigger. Repeated `validate` clicks against unchanged input still re-run the validator — supporting "re-validate to pick up server-side state" UX. A Bool would miss the second click.

6. **`validationReactions` is composed manually by the user.** A user's `reactions` function concatenates `validationReactions vcell` with their own reactions. Auto-wiring was rejected to keep Layer 2's runtime surface unchanged and to keep control flow grep-able. Layer 5 Forms will collect field reactions and pre-compose.
```

- [ ] **Step 3: Verify the file still reads coherently.** Scan around the insertion point.

- [ ] **Step 4: Commit.**

```bash
git add docs/design-elm-rad.md
git commit -m "docs: record Layer 4 implementation decisions"
```

---

## Final checkpoint — Task 7.1: Full verification sweep

- [ ] **Step 1: Package tests.**

Run: `npx --yes elm-test`
Expected: **78 tests pass** (48 pre + 30 new in Layer 4 — actually recompute: base 48 + 6 (ValidatedTest after 1.2) + 0 (2.1 reuses) + 2 (2.2) + 3 (2.3) + 8 (3.1) + 7 (4.2) + 2 (4.3) + 2 (6.1) = 48+30=78). Report actual.

- [ ] **Step 2: Package docs build.**

Run: `npx --yes elm make --docs docs.json`
Expected: success. Exposed modules unchanged: Rad, Rad.Engine, Rad.Http, Rad.Read, Rad.View.

- [ ] **Step 3: Examples build.**

Run: `cd examples && npm run build`
Expected: **17 HTML entries** (index + 13 pre-Layer-4 examples + 3 new Layer 4 examples).

- [ ] **Step 4: Live smoke (against user's running dev server).**

```bash
for e in required-name email-format username-available; do
    echo "$e: $(curl -s -o /dev/null -w '%{http_code}' "http://localhost:5173/$e.html")"
done
```

Expected: all `200`.

Plus:
```bash
curl -s 'http://localhost:5173/api/username-check?q=alice'
curl -s 'http://localhost:5173/api/username-check?q=taken'
```

Expected: `{"available":true}` and `{"available":false}` after ~1.5s each.

- [ ] **Step 5: TestRunner still compiles.**

Run: `cd examples && npx --yes elm make src/TestRunner.elm --output=/dev/null`
Expected: success.

- [ ] **Step 6: Visual behavioral smoke (manual browser).**
- `required-name`: type empty name, click Validate → "× name required". Type "alice" → "✓ looks good" immediately (reactive after activation). Click Reset → empty.
- `email-format`: type "foo" → Validate → "× missing @". Type "foo@bar" → "✓ looks good". Type a string of 120 chars with "@" → "× too long".
- `username-available`: type "alice" → Validate → "checking…" → after ~1.5s → "✓ available". Type "taken" → Validate → "checking…" → "× already taken".

- [ ] **Step 7: Commit history sanity.**

Run: `git log --oneline bd5fc78..HEAD`
Expected: ~14 implementation commits (one per task in Slices 1–6) + optional follow-ups. All single-line imperative, no Co-Authored-By trailers.

- [ ] **Step 8: Clean tree.**

Run: `git status`
Expected: clean.

---

## Out-of-slice notes

- **If a test expectation on test counts drifts:** tests may re-order or elm-test may count differently after `elm-format`. The exact numbers in each task are a guide, not a hard assert. What matters is that each task's new tests pass and no Layer 0-3 regressions appear.
- **If `elm-format` re-orders the `exposing` list:** accept the reordering and stage it in the same commit. `elm-format` is the source of truth.
- **If the test's naming collision between `Rad.input` and `SimpleView.input`** causes confusion elsewhere: prefer qualifying `Rad.input` explicitly (as done in Task 5.1). The example apps should not `expose (input)` from both `Rad` and `SimpleView`.
- **If `docs/design-elm-rad.md` line numbers shift** during the period this plan is in flight: use the `## Validation` heading as the anchor for the insertion in Task 6.4 rather than a line number.
- **Design-doc correction reminder:** the `withValidated` signature in the Layer 4 design doc Section 3 omits `Codec err`. This plan uses the corrected 5-argument form. If the design doc is ever edited to match, do not rewrite call sites here.
