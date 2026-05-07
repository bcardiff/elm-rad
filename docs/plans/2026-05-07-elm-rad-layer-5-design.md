# elm-rad Layer 5 Design — Forms

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–4 and 6 shipped (cells, reactions, `Remote`/`Request`, `Rad.Http`, debounced cells, validated cells, components). Layer 5 is purely additive.

---

## 1. Scope

Layer 5 introduces `Form fields` as a **transaction boundary** layered over an existing cells record. A Form does not own its field cells — it carries references to user-allocated cells plus a single Form-state cell that holds the pristine snapshot and submit lifecycle counters. Forms add three orthogonal capabilities to a cells record:

1. **Snapshot/dirty/reset.** A persisted snapshot of pristine values, a reactive `dirty` source, and an `Action` that restores all members from the snapshot.
2. **Submit gating.** A `submitForm` action and `onFormSubmit` / `onFormValid` reactions that wait for all validators in a typed group to land `Valid`, then fire a `Request` (or `Action`) with the unwrapped clean values.
3. **Status helpers.** Atomic `Source Bool` flags (`dirty`, `submitPending`, `formInvalid`, `formChecking`, `canSubmit`) plus a bundled `formStatus : Source FormStatus` enum for typical submit-button rendering.

**In scope:**
- `Form fields` opaque type.
- `withForm : String -> CellBuilder (Cell FormState -> rest) -> CellBuilder rest` — allocates one Registry slot.
- `form : Cell FormState -> fields -> List FormMember -> Form fields` — pure use-site constructor.
- `formField : Cell a -> FormMember`, `formValidatedField : ValidatedCell err a -> FormMember`.
- Behaviors: `dirty`, `submitForm`, `resetForm`, `formReactions`, `onFormSubmit`, `onFormValid`.
- Status: `submitPending`, `formInvalid`, `formChecking`, `canSubmit`, `formStatus`, `FormStatus(..)`.
- `ValidatedGroup fields clean` opaque + `valid1`..`valid8` + `mapValidated`.
- Two example apps: `L05E01-profile-form` (validation + submit gate + dirty/reset/status) and `L05E02-wizard-step` (`onFormValid` advancing a step counter).
- `elm-test` suites: builder, dirty, reset, submit-gate, status, ValidatedGroup.

**Out of scope:**
- Persistence itself (Layer 7). Layer 5's `FormState` is a normal `Cell`; rehydration is uniform with other cells.
- Cross-release stability of snapshot keys (snapshot is keyed by stringified runtime cell IDs). Layer 7 will reshape persistence keys; the snapshot blob will be re-keyed at that time.
- Auto-save / undo at form-level (use cases mentioned in the design doc but YAGNI for MVP).
- Conditional field visibility (orthogonal — solved by user-level reactive view code).
- Form-level "is request in flight?" — reflected via the user's result `Cell r` (e.g., `Remote.Loading`), not via `FormStatus`.

**Key decisions:**

1. **Forms are orthogonal to Components.** A Form attaches metadata + actions to an existing cells record. The cells may live in a top-level model or inside a component instance — the Form doesn't care. `withForm` allocates only the Form's own state cell.

2. **Form value constructed at use sites.** `form state fields members` is a pure function that returns a `Form fields`. Rebuilt per render (cheap — record construction). Mirrors the `embed`/`include` pattern from Layer 6.

3. **Members are user-curated.** The user explicitly lists which cells participate in the form via `formField` / `formValidatedField`. Cells in the model but not in the member list are not snapshotted, reset, or part of dirty.

4. **Snapshot is one JSON-blob cell.** A `Cell FormState` per form. The snapshot is `Encode.Value` (a JSON object keyed by stringified cell IDs). On first call to `withForm`, snapshot starts as `Encode.null`, meaning "pristine = each member's initial value." On submit-success, snapshot ← current encoded values.

5. **Submit gating is a single reaction with a multi-source trigger.** `onFormSubmit` watches `[submitSeq, lastResolvedSubmitSeq, each validation state]`. Re-fires whenever any change. Latest-wins via Layer 2's reaction-seq.

6. **`ValidatedGroup` is a typed bundle.** `valid1`..`valid8` cover 1–8 validated fields. `mapValidated` lets users transform tuples into records. No applicative chain; no >8 arity.

7. **`FormStatus` does NOT reflect Request state.** The form does not own the user's result `Cell r`; the user composes `formStatus` with their own `Remote` source for full UI state.

8. **No new `Msg` variants.** Forms dispatch through existing `ApplyAction` + `ReactionResult`. The runtime is unchanged.

---

## 2. Module layout after Layer 5

| Module | Audience | New in Layer 5 |
|---|---|---|
| `Rad` | App authors | + `Form`, `withForm`, `form`, `FormMember`, `formField`, `formValidatedField`, `dirty`, `submitForm`, `resetForm`, `formReactions`, `onFormSubmit`, `onFormValid`, `submitPending`, `formInvalid`, `formChecking`, `canSubmit`, `formStatus`, `FormStatus(..)`, `ValidatedGroup`, `valid1`..`valid8`, `mapValidated` |
| `Rad.Engine` | Engine authors | — (unchanged) |
| `Rad.View` | App authors | — (unchanged) |
| `Rad.Read` | App authors | — (unchanged) |
| `Rad.Http` | App authors | — (unchanged) |
| `Rad.Internal.Form` | private | **NEW**: `Form(..)`, `FormMember(..)`, `FormState`, accessors |
| `Rad.Internal.ValidatedGroup` | private | **NEW**: `ValidatedGroup(..)`, `valid1`..`valid8`, `mapValidated` (kept separate from `Internal.Form` to avoid mutual coupling) |
| `Rad.Internal.Action`, `Component`, `Debounced`, `Msg`, `Reaction`, `Registry`, `Request`, `Source`, `Validated` | private | — (unchanged) |

`Rad.Internal.Form` depends on `Rad.Internal.Validated` (to read validation state for dirty/status), `Rad.Internal.Reaction`, `Rad.Internal.Action`, `Rad.Internal.Registry`. No cycles.

---

## 3. Types and public surface

```elm
-- Rad (public)

type Form fields
    -- opaque; reexport of Rad.Internal.Form.Form

type alias FormState =
    { snapshot : Encode.Value         -- JSON object: { "<cellId>": <encoded value>, ... }
                                      -- starts as Encode.null ⇒ "pristine = initial values"
    , submitSeq : Int                 -- bumped by submitForm action
    , lastResolvedSubmitSeq : Int     -- bumped after a successful submit (latest-wins gate)
    }

type FormMember
    -- opaque; reexport of Rad.Internal.Form.FormMember

type FormStatus
    = Pristine
    | Editable
    | HasErrors
    | Validating
    | Submitting

type ValidatedGroup fields clean
    -- opaque; reexport of Rad.Internal.ValidatedGroup.ValidatedGroup


-- Builder

withForm
    : String
    -> CellBuilder (Cell FormState -> rest)
    -> CellBuilder rest


-- Use-site construction

form
    : Cell FormState
    -> fields
    -> List FormMember
    -> Form fields

formField          : Cell a               -> FormMember
formValidatedField : ValidatedCell err a  -> FormMember


-- Behaviors

dirty       : Form fields -> Source Bool
submitForm  : Form fields -> Action model
resetForm   : Form fields -> Action model
formReactions : Form fields -> List (Reaction model)


-- Status

submitPending : Form fields -> Source Bool
formInvalid   : Form fields -> Source Bool
formChecking  : Form fields -> Source Bool
canSubmit     : Form fields -> Source Bool   -- dirty AND not formInvalid AND not formChecking AND not submitPending
formStatus    : Form fields -> Source FormStatus


-- ValidatedGroup

valid1 : (fields -> ValidatedCell err a) -> ValidatedGroup fields a
valid2 : (fields -> ValidatedCell err a)
       -> (fields -> ValidatedCell err b)
       -> ValidatedGroup fields ( a, b )
valid3 .. valid8

mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b


-- Submit gating

onFormSubmit
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Request r)
    -> Cell r
    -> Reaction model

onFormValid
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Action model)
    -> Reaction model
```

---

## 4. Sketch of `Rad.Internal.Form`

This is a **shape sketch**, not the final code. The implementation plan will settle the exact `FormMember` constructors and helper signatures.

Internal modules in this codebase reference codecs by their **structural shape** (`{ encode, decode }`) rather than the `Codec a` alias defined in `Rad.elm`. This avoids a `Rad ↔ Rad.Internal.*` import cycle. `Rad.Internal.Form` follows the same convention — see `Rad.Internal.Validated` for precedent (`Rad/Internal/Validated.elm` lines 38–39).

```elm
module Rad.Internal.Form exposing
    ( Form(..)
    , FormMember(..)
    , FormState
    , formStateCodec
    )

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Validated as IValidated


type alias FormState =
    { snapshot : Encode.Value
    , submitSeq : Int
    , lastResolvedSubmitSeq : Int
    }


formStateCodec : { encode : FormState -> Decode.Value, decode : Decode.Decoder FormState }
formStateCodec =
    { encode =
        \s ->
            Encode.object
                [ ( "snapshot", s.snapshot )
                , ( "submitSeq", Encode.int s.submitSeq )
                , ( "lastResolvedSubmitSeq", Encode.int s.lastResolvedSubmitSeq )
                ]
    , decode =
        Decode.map3 FormState
            (Decode.field "snapshot" Decode.value)
            (Decode.field "submitSeq" Decode.int)
            (Decode.field "lastResolvedSubmitSeq" Decode.int)
    }


type Form fields
    = Form
        { state : -- reference to the FormState cell (id + codec record)
            { id : Int
            , codec : { encode : FormState -> Decode.Value, decode : Decode.Decoder FormState }
            }
        , fields : fields
        , members : List FormMember
        }


type FormMember
    = PlainMember
        { inputId : Int
        , initial : Decode.Value           -- already-encoded initial
        , readEncoded : Decode.Value -> Decode.Value
            -- identity in practice; reserved for future "wire format != stored format"
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

The design contract for `FormMember`: capture **everything the form needs** to (a) read each member's current registry value, (b) compare/write encoded values for snapshot/dirty/reset, (c) for validated members, read/bump the validation+activationSeq slots. Exact constructors are an implementation detail.

---

## 5. Behavior contracts

### 5.1 `withForm`

Allocates one Registry slot for `FormState` with initial value:

```elm
{ snapshot = Encode.null
, submitSeq = 0
, lastResolvedSubmitSeq = 0
}
```

Persistence-key namespacing follows Layer 6 (prefix-extended). Inside a component instance mounted as `"profile"`, `withForm "data"` produces a state cell with key `"profile.data"`.

### 5.2 `form`

Pure constructor. Captures references; allocates nothing. Cheap to call per render.

### 5.3 `dirty : Form fields -> Source Bool`

Implementation: a `Source` whose `Read` reads `FormState.snapshot` and each member's current registry value.

- If `snapshot == Encode.null`: compare each member's current encoded value against the member's encoded initial. `True` on first mismatch.
- Otherwise: look up `String.fromInt member.id` in the snapshot object. If present, compare. If absent (member added after the snapshot was captured), treat as initial.

### 5.4 `submitForm : Form fields -> Action model`

One Action that:
1. Bumps `FormState.submitSeq` (`+1`).
2. For each `ValidatedMember`, bumps that member's `activationSeq` (= equivalent of dispatching `validate`).

Implemented as a single Registry transformation (one Action returns one Registry, one transition).

### 5.5 `resetForm : Form fields -> Action model`

One Action that:
1. Reads `FormState.snapshot`.
2. For each member:
   - If snapshot is `null` or the member's id is not in the snapshot object: write the member's initial encoded value back to its input slot.
   - Else: write the snapshot value back to the member's input slot.
3. For each `ValidatedMember`: also write `Dormant` to the validation slot and `0` to the `activationSeq` slot (matches `resetValidation`).
4. Does **not** modify `submitSeq` / `lastResolvedSubmitSeq`.

### 5.6 `formReactions : Form fields -> List (Reaction model)`

Returns one `Reaction` per `ValidatedMember`, equivalent to `Rad.validationReactions` for that ValidatedCell. Plain `formField` members produce no reactions. Users compose:

```elm
reactions = \model _ ->
    formReactions (profileForm model)
        ++ [ onFormSubmit (profileForm model) ... ]
```

### 5.7 `onFormSubmit`

```elm
onFormSubmit
    : Form fields
    -> ValidatedGroup fields clean
    -> (clean -> Request r)
    -> Cell r
    -> Reaction model
```

**Trigger:** `[ FormState.submitSeq, FormState.lastResolvedSubmitSeq ] ++ [ validationId for each ValidatedCell in the group ]`.

**`buildRequest registry`:**
- If `submitSeq <= lastResolvedSubmitSeq`: `SkipRequest` (no fresh submit).
- Else if any validation in the group is `Dormant` / `Checking` / `Invalid`: `SkipRequest` (waits).
- Else (all `Valid`): extract `clean` via the group's accessors, call `(clean -> Request r)`, return `DispatchRequest req`.

**On Request success** (handled by the reaction's response path):
1. Write decoded result to target `Cell r`.
2. Bump `FormState.lastResolvedSubmitSeq` ← `submitSeq`.
3. Re-encode all members' current values into a JSON object; write to `FormState.snapshot`.

**On Request failure:**
1. Write `Failed err` (per `Remote` semantics) to target `Cell r` if it carries a `Remote`-shaped value. (Form does not require the result Cell to be `Remote`; the Request's error type lands in the Cell per existing `Rad.on` semantics.)
2. Do NOT bump `lastResolvedSubmitSeq`. User can edit + resubmit.

**Latest-wins:** Layer 2's reaction-seq mechanism handles superseded in-flight requests when validations or `submitSeq` change mid-flight.

### 5.8 `onFormValid`

Same gate as `onFormSubmit`, but instead of dispatching a `Request`, runs an `Action`. On the action's commit, also bumps `lastResolvedSubmitSeq` and updates snapshot.

Useful for client-only flows ("advance wizard step", "open dialog").

### 5.9 Atomic status sources

```elm
submitPending : Form fields -> Source Bool
-- True iff state.submitSeq > state.lastResolvedSubmitSeq

formInvalid : Form fields -> Source Bool
-- True iff any ValidatedMember's validation slot decodes to `Invalid _`

formChecking : Form fields -> Source Bool
-- True iff any ValidatedMember's validation slot decodes to `Checking`

canSubmit : Form fields -> Source Bool
-- True iff dirty AND not formInvalid AND not formChecking AND not submitPending
```

### 5.10 `formStatus : Form fields -> Source FormStatus`

Computed as a single `Read FormStatus`. **`formInvalid` always wins over `Submitting`** — a late-arriving Invalid validation surfaces as `HasErrors` even when a submit is pending, so the user sees the error rather than a misleading "Submitting" state.

```elm
if formInvalid               -> HasErrors
else if submitPending && formChecking -> Validating
else if submitPending        -> Submitting   -- all Valid; request firing or about to
else if dirty                -> Editable
else                         -> Pristine
```

Truth table for the user's `submit` button rendering:

| dirty | submitPending | formChecking | formInvalid | formStatus | typical button |
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

`valid1` / `valid2` / ... / `valid8` are hand-rolled overloads. `mapValidated` post-processes the `clean`:

```elm
mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
```

---

## 6. Edge cases

| Scenario | Behavior |
|---|---|
| User clicks submit, validations all Dormant | submitForm bumps each `activationSeq`; onFormSubmit waits; on all-Valid, fires |
| User clicks submit, one validator async-Checking | onFormSubmit waits; reaction re-fires when validation settles |
| Validation Invalid → user fixes → field becomes Valid (no second submit click) | onFormSubmit fires (gate satisfied because `submitSeq > lastResolvedSubmitSeq`). Matches design-doc semantics: "wait for valid" |
| User clicks submit twice quickly | submitSeq bumps twice; reaction sees latest; one DispatchRequest via Layer 2 latest-wins seq |
| Request fails | result Cell ← Failed err (per Cell's codec); lastResolvedSubmitSeq NOT bumped → user can retry |
| User resets while submit is in-flight | resetForm writes snapshot back; validations Dormant; in-flight reaction superseded; no DispatchRequest fires |
| ValidatedGroup references a cell NOT in form members | Allowed; group still gates submit, but field isn't snapshotted/reset. Documented as user responsibility |
| Snapshot is null at first submit success | Snapshot ← current encoded blob (so subsequent dirty/reset compare against last-submitted state) |
| Member's codec fails to decode snapshot value during reset | Skip that member (write its initial as fallback) |
| Form's state Cell rehydrated from persistence with submitSeq > lastResolvedSubmitSeq | Submit reaction re-fires on boot — same crash-recovery pattern as Layer 4 `Checking` |

---

## 7. Examples shipped with this layer

### 7.1 `L05E01-profile-form`

Profile form with two validated fields (name required, email format) plus a non-validated bio field. Submit gates on both validators. Renders submit button using `formStatus`. Buttons for `submitForm` and `resetForm`. Watches `dirty` for a "unsaved changes" indicator.

### 7.2 `L05E02-wizard-step`

Two-step wizard demoing `onFormValid` (no Request — pure Action). Each step is a small form; `onFormValid` advances a step counter when the step's validators pass.

---

## 8. Tests

| Suite | Coverage |
|---|---|
| `FormBuilderTest` | `withForm` allocates one Registry slot with the right initial; nested inside components, the state cell's key is namespaced |
| `FormDirtyTest` | Initial dirty=False; mutate a member → True; resetForm → False; submit-success → False (snapshot bumped) |
| `FormResetTest` | Restores all member values; resets ValidatedCell to Dormant; doesn't touch submitSeq |
| `FormSubmitGateTest` | Dispatches Request iff submitSeq>lastResolved AND all-Valid; bumps lastResolvedSubmitSeq + snapshot on success; latest-wins under interleaving |
| `FormStatusTest` | Each FormStatus variant transition + canSubmit truth table |
| `ValidatedGroupTest` | valid1..valid8 produce typed clean values; mapValidated post-transforms; group gate is "all Valid" |

Total: ~6 new suites, ~20–25 new tests. Expected post-Layer-5 total: 90 + ~22 = **~112**.

---

## 9. Open items deferred to writing-plans

- Exact `FormMember` internal shape (struct or sum) and how `formField` / `formValidatedField` capture codecs without making `FormMember` parameterized over field types (must be type-erased to live in a `List`).
- Whether `onFormSubmit`'s Request response handler is implemented as a special reaction kind or composes with existing `Rad.on` machinery + a follow-up Action.
- Whether `mapValidated` is exposed as `Rad.mapValidated` or `Rad.Validated.mapGroup` (naming pass).
- Whether `Rad.Internal.ValidatedGroup` ends up as a separate file or a section of `Rad.Internal.Form` (settle when the implementation reveals coupling).

---

## 10. Non-goals

- Layer 5 does not touch persistence semantics. The Form's state Cell rehydrates like any other Cell.
- Layer 5 does not auto-revalidate on snapshot bump (validations are reactive; if member values change due to `resetForm`, validations re-fire normally).
- Layer 5 does not introduce a per-form scope on validation activation. Validators are still per-cell; the form just bumps them in concert.
- Layer 5 does not provide `Request`-typed error access in `FormStatus`. The result Cell carries that information.
