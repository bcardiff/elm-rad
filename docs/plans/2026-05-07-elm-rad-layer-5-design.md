# elm-rad Layer 5 Design — Forms

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–4 and 6 shipped (cells, reactions, `Remote`/`Request`, `Rad.Http`, debounced cells, validated cells, components). Layer 5 is additive on the user-facing API but requires one internal refactor: extracting `CellBuilder` (and its `BuildState` / `BuildResult` helpers) from `Rad.elm` into a new private module `Rad.Internal.CellBuilder`, so the new public module `Rad.Form` can define `Form.withState` without sitting in `Rad.elm`.

**Module-home decision:** All Layer 5 public surface lives in a new public module `Rad.Form`. `Rad.elm` itself is unchanged by Layer 5. Rationale: Forms are orthogonal to the rest of the API (snapshot/dirty/submit-gating semantics are an opinionated layer, and alternative Form designs may emerge later). Keeping the API behind one importable name (`import Rad.Form as Form`) makes Forms swappable and usage explicit at the call site.

---

## 1. Scope

Layer 5 introduces `Form fields` as a **transaction boundary** layered over an existing cells record. A Form does not own its field cells — it carries references to user-allocated cells plus a single Form-state cell that holds the pristine snapshot and submit lifecycle counters. Forms add three orthogonal capabilities to a cells record:

1. **Snapshot/dirty/reset.** A persisted snapshot of pristine values, a reactive `dirty` source, and an `Action` that restores all members from the snapshot.
2. **Submit gating.** A `Form.submit` action and `Form.onSubmit` / `Form.onValid` reactions that wait for all validators in a typed group to land `Valid`, then fire a `Request` (or `Action`) with the unwrapped clean values.
3. **Status helpers.** Atomic `Source Bool` flags (`Form.dirty`, `Form.submitPending`, `Form.invalid`, `Form.checking`, `Form.canSubmit`) plus a bundled `Form.status : Source Form.Status` enum for typical submit-button rendering.

All names below are qualified-by-import-alias style: `import Rad.Form as Form` makes `Form.X` the call-site form. Names are intentionally trimmed to remove redundant "form" / "Form" prefixes.

**In scope** (all in `Rad.Form`):
- `Form fields` opaque type, `State` (alias for the persisted form state), `Member` opaque, `Status(..)`, `ValidatedGroup fields clean` opaque.
- `Form.withState : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest` — allocates one Registry slot.
- `Form.over : Cell State -> fields -> List Member -> Form fields` — pure use-site constructor.
- `Form.field : Cell a -> Member`, `Form.validatedField : ValidatedCell err a -> Member`.
- Behaviors: `Form.dirty`, `Form.submit`, `Form.reset`, `Form.reactions`, `Form.onSubmit`, `Form.onValid`.
- Status: `Form.submitPending`, `Form.invalid`, `Form.checking`, `Form.canSubmit`, `Form.status`.
- `Form.validators1`..`Form.validators8`, `Form.mapValidated`.
- Two example apps: `L05E01-profile-form` (validation + submit gate + dirty/reset/status) and `L05E02-wizard-step` (`Form.onValid` advancing a step counter).
- `elm-test` suites: builder, dirty, reset, submit-gate, status, ValidatedGroup.

**Out of scope:**
- Persistence itself (Layer 7). Layer 5's `Form.State` is a normal `Cell`; rehydration is uniform with other cells.
- Cross-release stability of snapshot keys (snapshot is keyed by stringified runtime cell IDs). Layer 7 will reshape persistence keys; the snapshot blob will be re-keyed at that time.
- Auto-save / undo at form-level (use cases mentioned in the design doc but YAGNI for MVP).
- Conditional field visibility (orthogonal — solved by user-level reactive view code).
- Form-level "is request in flight?" — reflected via the user's result `Cell r` (e.g., `Remote.Loading`), not via `Form.Status`.

**Key decisions:**

1. **Forms live in `Rad.Form`, not `Rad`.** Orthogonal API + exploratory semantics + room for alternative Form designs in future. `Rad.elm`'s public surface is unchanged by Layer 5.

2. **Forms are orthogonal to Components.** A Form attaches metadata + actions to an existing cells record. The cells may live in a top-level model or inside a component instance — the Form doesn't care. `Form.withState` allocates only the Form's own state cell.

3. **Form value constructed at use sites.** `Form.over state fields members` is a pure function that returns a `Form fields`. Rebuilt per render (cheap — record construction). Mirrors the `embed`/`include` pattern from Layer 6.

4. **Members are user-curated.** The user explicitly lists which cells participate in the form via `Form.field` / `Form.validatedField`. Cells in the model but not in the member list are not snapshotted, reset, or part of dirty.

5. **Snapshot is one JSON-blob cell.** A `Cell Form.State` per form. The snapshot is `Encode.Value` (a JSON object keyed by stringified cell IDs). On first call to `Form.withState`, snapshot starts as `Encode.null`, meaning "pristine = each member's initial value." On submit-success, snapshot ← current encoded values.

6. **Submit gating is a single reaction with a multi-source trigger.** `Form.onSubmit` watches `[submitSeq, lastResolvedSubmitSeq, each validation state]`. Re-fires whenever any change. Latest-wins via Layer 2's reaction-seq.

7. **`ValidatedGroup` is a typed bundle.** `Form.validators1`..`Form.validators8` cover 1–8 validated fields. `Form.mapValidated` lets users transform tuples into records. No applicative chain; no >8 arity.

8. **`Form.Status` does NOT reflect Request state.** The form does not own the user's result `Cell r`; the user composes `Form.status` with their own `Remote` source for full UI state.

9. **No new `Msg` variants.** Forms dispatch through existing `ApplyAction` + `ReactionResult`. The runtime is unchanged.

---

## 2. Module layout after Layer 5

| Module | Audience | New in Layer 5 |
|---|---|---|
| `Rad` | App authors | — (unchanged user-facing API; internal CellBuilder body re-exports from `Rad.Internal.CellBuilder`) |
| `Rad.Form` | App authors | **NEW**: full Layer 5 public surface (see §3) |
| `Rad.Engine` | Engine authors | — (unchanged) |
| `Rad.View` | App authors | — (unchanged) |
| `Rad.Read` | App authors | — (unchanged) |
| `Rad.Http` | App authors | — (unchanged) |
| `Rad.Internal.CellBuilder` | private | **NEW** (extracted from `Rad.elm`): `CellBuilder(..)`, `BuildState`, `BuildResult` |
| `Rad.Internal.Form` | private | **NEW**: `Form(..)`, `Member(..)`, `State`, `stateCodec` |
| `Rad.Internal.ValidatedGroup` | private | **NEW**: `ValidatedGroup(..)`, `validators1`..`validators8`, `mapValidated` (kept separate from `Internal.Form` so the validator-group machinery stays loosely coupled) |
| `Rad.Internal.Action`, `Component`, `Debounced`, `Msg`, `Reaction`, `Registry`, `Request`, `Source`, `Validated` | private | — (unchanged) |

**Dependency graph after Layer 5:**

- `Rad.Internal.CellBuilder` ← imported by `Rad.elm` and `Rad.Form`.
- `Rad.Internal.Form` ← imports `Rad.Internal.CellBuilder`, `Rad.Internal.Validated`, `Rad.Internal.Reaction`, `Rad.Internal.Action`, `Rad.Internal.Registry`, `Rad.Internal.Source`.
- `Rad.Internal.ValidatedGroup` ← imports `Rad.Internal.Validated`, `Rad.Internal.Source` (for `Read`).
- `Rad.Form` ← imports `Rad`, `Rad.Internal.CellBuilder`, `Rad.Internal.Form`, `Rad.Internal.ValidatedGroup`, plus reaction/action internals as needed. Re-exports the opaque types it owns; references types from `Rad` (`Cell`, `Action`, `Reaction`, `Source`, `Request`, `ValidatedCell`) by importing from `Rad`.

No cycles. The `Rad.elm` ↔ `Rad.Form` relationship is one-way (`Rad.Form` imports `Rad`), so the existing API stays self-contained.

**Internal `CellBuilder` extraction (Slice 0 of the implementation plan):**
- Move the `CellBuilder ctor` opaque type, `BuildState`, `BuildResult` from `Rad.elm` to `Rad/Internal/CellBuilder.elm`. Expose the constructor (`CellBuilder(..)`) so `Rad.elm` and `Rad.Form` can both pattern-match.
- `Rad.elm` keeps `build`, `with`, `runBuilder`, `withDebounced`, `withValidated`, `withInstance` exactly as they are (their bodies now reference the imported type). Public signatures unchanged.
- The Layer 6 plan flagged this extraction as a future option ("either extracting `CellBuilder` to its own internal module (larger refactor) or defining `ComponentDef` directly in `Rad.elm` (simpler, keeps the existing layering)" — Slice 2 architectural note). Layer 5 takes that option.

---

## 3. Types and public surface

All Layer 5 surface lives in **`Rad.Form`**. Recommended import: `import Rad.Form as Form exposing (Form, Status(..))`. Below, the qualified `Form.` prefix is the call-site form.

```elm
-- Rad.Form (public)

type Form fields
    -- opaque; reexport of Rad.Internal.Form.Form

type alias State =
    { snapshot : Encode.Value         -- JSON object: { "<cellId>": <encoded value>, ... }
                                      -- starts as Encode.null ⇒ "pristine = initial values"
    , submitSeq : Int                 -- bumped by Form.submit action
    , lastResolvedSubmitSeq : Int     -- bumped after a successful submit (latest-wins gate)
    }

type Member
    -- opaque; reexport of Rad.Internal.Form.Member

type Status
    = Pristine
    | Editable
    | HasErrors
    | Validating
    | Submitting

type ValidatedGroup fields clean
    -- opaque; reexport of Rad.Internal.ValidatedGroup.ValidatedGroup


-- Builder (call sites: Form.withState ...)

withState
    : String
    -> CellBuilder (Cell State -> rest)
    -> CellBuilder rest


-- Use-site construction

over
    : Cell State
    -> fields
    -> List Member
    -> Form fields

field          : Cell a               -> Member
validatedField : ValidatedCell err a  -> Member


-- Behaviors

dirty     : Form fields -> Source Bool
submit    : Form fields -> Action model
reset     : Form fields -> Action model
reactions : Form fields -> List (Reaction model)


-- Status

submitPending : Form fields -> Source Bool
invalid       : Form fields -> Source Bool
checking      : Form fields -> Source Bool
canSubmit     : Form fields -> Source Bool   -- dirty AND not invalid AND not checking AND not submitPending
status        : Form fields -> Source Status


-- ValidatedGroup

validators1 : (fields -> ValidatedCell err a) -> ValidatedGroup fields a
validators2 : (fields -> ValidatedCell err a)
            -> (fields -> ValidatedCell err b)
            -> ValidatedGroup fields ( a, b )
validators3 .. validators8

mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b


-- Submit gating

onSubmit
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Request r)
    -> Cell r
    -> Reaction model

onValid
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Action model)
    -> Reaction model
```

**Example call site:**

```elm
import Rad.Form as Form exposing (Form, Status(..))

type alias Model =
    { profile     : ProfileFields
    , profileForm : Cell Form.State
    , submitResult : Cell (Remote RequestError ())
    }

init =
    build Model
        |> withInstance "profile" profileComponent
        |> Form.withState "profile-form"
        |> with "submit-result" Idle remoteResultCodec

profileForm : Model -> Form ProfileFields
profileForm m =
    Form.over m.profileForm m.profile
        [ Form.validatedField m.profile.name
        , Form.validatedField m.profile.email
        , Form.field m.profile.bio
        ]

reactions = \model _ ->
    Form.reactions (profileForm model)
        ++ [ Form.onSubmit (profileForm model)
                (Form.validators2 .name .email)
                (\(name, email) -> postProfile name email)
                model.submitResult
           ]
```

---

## 4. Sketch of `Rad.Internal.Form`

This is a **shape sketch**, not the final code. The implementation plan will settle the exact `Member` constructors and helper signatures.

Internal modules in this codebase reference codecs by their **structural shape** (`{ encode, decode }`) rather than the `Codec a` alias defined in `Rad.elm`. This avoids a `Rad ↔ Rad.Internal.*` import cycle. `Rad.Internal.Form` follows the same convention — see `Rad.Internal.Validated` for precedent (`Rad/Internal/Validated.elm` lines 38–39).

```elm
module Rad.Internal.Form exposing
    ( Form(..)
    , Member(..)
    , State
    , stateCodec
    )

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Validated as IValidated


type alias State =
    { snapshot : Encode.Value
    , submitSeq : Int
    , lastResolvedSubmitSeq : Int
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


type Form fields
    = Form
        { state : -- reference to the State cell (id + codec record)
            { id : Int
            , codec : { encode : State -> Decode.Value, decode : Decode.Decoder State }
            }
        , fields : fields
        , members : List Member
        }


type Member
    = PlainMember
        { inputId : Int
        , initial : Decode.Value           -- already-encoded initial
        }
    | ValidatedMember
        { inputId : Int
        , validationId : Int
        , activationSeqId : Int
        , initial : Decode.Value
        , validationDecoder : Decode.Decoder (IValidated.Validation Decode.Value Decode.Value)
            -- enough to read Dormant / Checking / Valid / Invalid for status purposes
        }
```

The design contract for `Member`: capture **everything the form needs** to (a) read each member's current registry value, (b) compare/write encoded values for snapshot/dirty/reset, (c) for validated members, read/bump the validation+activationSeq slots. Exact constructors are an implementation detail.

---

## 5. Behavior contracts

### 5.1 `Form.withState`

Allocates one Registry slot for `Form.State` with initial value:

```elm
{ snapshot = Encode.null
, submitSeq = 0
, lastResolvedSubmitSeq = 0
}
```

Persistence-key namespacing follows Layer 6 (prefix-extended). Inside a component instance mounted as `"profile"`, `Form.withState "data"` produces a state cell with key `"profile.data"`.

### 5.2 `Form.over`

Pure constructor. Captures references; allocates nothing. Cheap to call per render.

### 5.3 `Form.dirty : Form fields -> Source Bool`

Implementation: a `Source` whose `Read` reads `State.snapshot` and each member's current registry value.

- If `snapshot == Encode.null`: compare each member's current encoded value against the member's encoded initial. `True` on first mismatch.
- Otherwise: look up `String.fromInt member.id` in the snapshot object. If present, compare. If absent (member added after the snapshot was captured), treat as initial.

### 5.4 `Form.submit : Form fields -> Action model`

One Action that:
1. Bumps `State.submitSeq` (`+1`).
2. For each `ValidatedMember`, bumps that member's `activationSeq` (= equivalent of dispatching `Rad.validate`).

Implemented as a single Registry transformation (one Action returns one Registry, one transition).

### 5.5 `Form.reset : Form fields -> Action model`

One Action that:
1. Reads `State.snapshot`.
2. For each member:
   - If snapshot is `null` or the member's id is not in the snapshot object: write the member's initial encoded value back to its input slot.
   - Else: write the snapshot value back to the member's input slot.
3. For each `ValidatedMember`: also write `Dormant` to the validation slot and `0` to the `activationSeq` slot (matches `Rad.resetValidation`).
4. Does **not** modify `submitSeq` / `lastResolvedSubmitSeq`.

### 5.6 `Form.reactions : Form fields -> List (Reaction model)`

Returns one `Reaction` per `ValidatedMember`, equivalent to `Rad.validationReactions` for that ValidatedCell. `Form.field` (plain) members produce no reactions. Users compose:

```elm
reactions = \model _ ->
    Form.reactions (profileForm model)
        ++ [ Form.onSubmit (profileForm model) ... ]
```

### 5.7 `Form.onSubmit`

```elm
Form.onSubmit
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Request r)
    -> Cell r
    -> Reaction model
```

**Trigger:** `[ State.submitSeq, State.lastResolvedSubmitSeq ] ++ [ validationId for each ValidatedCell in the group ]`.

**`buildRequest registry`:**
- If `submitSeq <= lastResolvedSubmitSeq`: `SkipRequest` (no fresh submit).
- Else if any validation in the group is `Dormant` / `Checking` / `Invalid`: `SkipRequest` (waits).
- Else (all `Valid`): extract `clean` via the group's accessors, call `(clean -> Request r)`, return `DispatchRequest req`.

**On Request success** (handled by the reaction's response path):
1. Write decoded result to target `Cell r`.
2. Bump `State.lastResolvedSubmitSeq` ← `submitSeq`.
3. Re-encode all members' current values into a JSON object; write to `State.snapshot`.

**On Request failure:**
1. Write `Failed err` (per `Remote` semantics) to target `Cell r` if it carries a `Remote`-shaped value. (Form does not require the result Cell to be `Remote`; the Request's error type lands in the Cell per existing `Rad.on` semantics.)
2. Do NOT bump `lastResolvedSubmitSeq`. User can edit + resubmit.

**Latest-wins:** Layer 2's reaction-seq mechanism handles superseded in-flight requests when validations or `submitSeq` change mid-flight.

### 5.8 `Form.onValid`

Same gate as `Form.onSubmit`, but instead of dispatching a `Request`, runs an `Action`. On the action's commit, also bumps `lastResolvedSubmitSeq` and updates snapshot.

Useful for client-only flows ("advance wizard step", "open dialog").

### 5.9 Atomic status sources

```elm
Form.submitPending : Form fields -> Source Bool
-- True iff state.submitSeq > state.lastResolvedSubmitSeq

Form.invalid : Form fields -> Source Bool
-- True iff any ValidatedMember's validation slot decodes to `Invalid _`

Form.checking : Form fields -> Source Bool
-- True iff any ValidatedMember's validation slot decodes to `Checking`

Form.canSubmit : Form fields -> Source Bool
-- True iff dirty AND not invalid AND not checking AND not submitPending
```

### 5.10 `Form.status : Form fields -> Source Status`

Computed as a single `Read Status`. **`Form.invalid` always wins over `Submitting`** — a late-arriving Invalid validation surfaces as `HasErrors` even when a submit is pending, so the user sees the error rather than a misleading "Submitting" state.

```elm
if invalid                       -> HasErrors
else if submitPending && checking -> Validating
else if submitPending             -> Submitting   -- all Valid; request firing or about to
else if dirty                     -> Editable
else                              -> Pristine
```

Truth table for the user's submit button rendering:

| dirty | submitPending | checking | invalid | status | typical button |
|---|---|---|---|---|---|
| F | F | F | F | `Pristine` | hidden / "Saved ✓" |
| T | F | F | F | `Editable` | enabled "Save" |
| any | F | F | T | `HasErrors` | disabled "Fix errors" |
| any | T | T | F | `Validating` | spinner "Checking…" |
| any | T | F | F | `Submitting` | spinner "Saving…" |
| any | T | any | T | `HasErrors` | disabled "Fix errors" (Invalid wins) |

### 5.11 ValidatedGroup

```elm
type ValidatedGroup fields clean
    = ValidatedGroup (fields -> List Int -> Read (Maybe clean))
    -- carries: validation cell ids (for triggers) + a Read that returns
    --   Just clean iff every validation in the group is Valid
```

`Form.validators1` / ... / `Form.validators8` are hand-rolled overloads. `Form.mapValidated` post-processes the `clean`:

```elm
Form.mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
```

---

## 6. Edge cases

| Scenario | Behavior |
|---|---|
| User clicks submit, validations all Dormant | `Form.submit` bumps each `activationSeq`; `Form.onSubmit` waits; on all-Valid, fires |
| User clicks submit, one validator async-Checking | `Form.onSubmit` waits; reaction re-fires when validation settles |
| Validation Invalid → user fixes → field becomes Valid (no second submit click) | `Form.onSubmit` fires (gate satisfied because `submitSeq > lastResolvedSubmitSeq`). Matches design-doc semantics: "wait for valid" |
| User clicks submit twice quickly | submitSeq bumps twice; reaction sees latest; one DispatchRequest via Layer 2 latest-wins seq |
| Request fails | result Cell ← Failed err (per Cell's codec); lastResolvedSubmitSeq NOT bumped → user can retry |
| User resets while submit is in-flight | `Form.reset` writes snapshot back; validations Dormant; in-flight reaction superseded; no DispatchRequest fires |
| ValidatedGroup references a cell NOT in form members | Allowed; group still gates submit, but field isn't snapshotted/reset. Documented as user responsibility |
| Snapshot is null at first submit success | Snapshot ← current encoded blob (so subsequent dirty/reset compare against last-submitted state) |
| Member's codec fails to decode snapshot value during reset | Skip that member (write its initial as fallback) |
| Form's state Cell rehydrated from persistence with submitSeq > lastResolvedSubmitSeq | Submit reaction re-fires on boot — same crash-recovery pattern as Layer 4 `Checking` |

---

## 7. Examples shipped with this layer

### 7.1 `L05E01-profile-form`

Profile form with two validated fields (name required, email format) plus a non-validated bio field. Submit gates on both validators. Renders submit button using `Form.status`. Buttons for `Form.submit` and `Form.reset`. Watches `Form.dirty` for an "unsaved changes" indicator.

### 7.2 `L05E02-wizard-step`

Two-step wizard demoing `Form.onValid` (no Request — pure Action). Each step is a small form; `Form.onValid` advances a step counter when the step's validators pass.

---

## 8. Tests

| Suite | Coverage |
|---|---|
| `FormBuilderTest` | `Form.withState` allocates one Registry slot with the right initial; nested inside components, the state cell's key is namespaced |
| `FormDirtyTest` | Initial dirty=False; mutate a member → True; `Form.reset` → False; submit-success → False (snapshot bumped) |
| `FormResetTest` | Restores all member values; resets ValidatedCell to Dormant; doesn't touch submitSeq |
| `FormSubmitGateTest` | Dispatches Request iff submitSeq>lastResolved AND all-Valid; bumps lastResolvedSubmitSeq + snapshot on success; latest-wins under interleaving |
| `FormStatusTest` | Each `Form.Status` variant transition + `Form.canSubmit` truth table (`FormStatusTest` keeps a `Form` prefix in the test module name only — the test file is `tests/FormStatusTest.elm`) |
| `ValidatedGroupTest` | `Form.validators1`..`Form.validators8` produce typed clean values; `Form.mapValidated` post-transforms; group gate is "all Valid" |

Total: ~6 new suites, ~20–25 new tests. Expected post-Layer-5 total: 90 + ~22 = **~112**.

---

## 9. Open items deferred to writing-plans

- Exact `Member` internal shape (struct or sum) and how `Form.field` / `Form.validatedField` capture codecs without making `Member` parameterized over field types (must be type-erased to live in a `List`).
- Whether `Form.onSubmit`'s Request response handler is implemented as a special reaction kind or composes with existing `Rad.on` machinery + a follow-up Action.
- Whether `Rad.Internal.ValidatedGroup` ends up as a separate file or a section of `Rad.Internal.Form` (settle when the implementation reveals coupling).
- Naming review: `Form.over` (use-site constructor) vs alternatives (`Form.from`, `Form.attach`) — gate on first example writeup.

---

## 10. Non-goals

- Layer 5 does not touch persistence semantics. The Form's state Cell rehydrates like any other Cell.
- Layer 5 does not auto-revalidate on snapshot bump (validations are reactive; if member values change due to `Form.reset`, validations re-fire normally).
- Layer 5 does not introduce a per-form scope on validation activation. Validators are still per-cell; the form just bumps them in concert.
- Layer 5 does not provide `Request`-typed error access in `Form.Status`. The result Cell carries that information.
