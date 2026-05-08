# elm-rad Layer 7 Design — Persistence

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–6 shipped (cells, reactions, debounce, validation, forms, components). Layer 7 is largely additive but introduces one breaking change to `AppDef` (new `persist` field) and changes `run`'s flags type from `()` to `Json.Decode.Value`.

---

## 1. Scope

Layer 7 introduces opt-in persistence: an Elm app can declare a `PersistConfig` and the runtime will (a) attempt to restore the registry from a user-supplied `Json.Decode.Value` (typically read from `localStorage` at boot via JS), (b) save the full registry to `localStorage` on a debounced timer or via an explicit `persistNow` action, and (c) re-fire reactions whose targets are in `Loading`/`Checking` state on restore (crash recovery).

**In scope:**
- `localStorage` backend only. User wires one outgoing port plus ~5 lines of JS.
- `PersistConfig` with `key`, `version`, `save` port. No migrations field.
- `AppDef` gains `persist : Maybe (PersistConfig (Engine.Msg model))`. **Breaking** — every existing app/example must add `persist = Nothing`.
- `run`'s flags type becomes `Json.Decode.Value` (was `()`). Accepts raw string, parsed object, or `null`. Tries string-first; falls back to value-as-is. `null` ⇒ fresh start.
- `BuildResult` extends with `List PersistEntry`. Each `with`/`withDebounced`/`withValidated`/`Form.withState` appends one schema entry.
- Per-cell-type encode/decode for `Cell a`, `DebouncedCell a`, `ValidatedCell err a`, `Cell Form.State`.
- `withDebounced` / `withValidated` thread the user-supplied `String` key into the cell's internal record (Layer 3/4 prereq fix; key is currently dropped via `_`).
- Save: any registry change schedules a 500ms debounced save (latest-wins via dirty counter). `persistNow : Action model` skips the debounce.
- Strict restore: version mismatch, missing-cell-with-non-null-codec, or any decode failure → discard everything, use init defaults.
- Missing-cell rule: codec-driven null fallback. The cell's value codec is invoked with `Encode.null`; if it accepts, the cell is initialized using that value (with multi-slot cells synthesizing the rest of the structure at defaults: `timerSeq = 0`, `validation = Dormant`, `activationSeq = 0`). If it rejects, strict-fail. `Form.stateCodec` is amended to always accept `null → initialState`.
- Crash recovery: `IReaction.Guts` gains `inFlight : Registry -> Bool`. After restore, runtime walks reactions and re-fires any reaction whose target is in-flight (`Loading`/`Checking`).
- Form snapshot fix: `Form.State.snapshot` is keyed by `cell.key` strings instead of stringified runtime cell IDs (cross-release stability).
- 5 new test suites (~30 tests). 2 existing test files re-keyed.
- 1 new example: `L07E01-persist-counter`.
- Design doc Persistence section gains an Implementation notes subsection.

**Out of scope (deferred to later layers):**
- `sessionStorage` backend.
- Per-cell backend choice / pluggable backend abstraction.
- Migrations (insertField/removeField/renameField + version chain). Design doc punts to v2.
- `onBlur`-specific or post-action save triggers (subsumed by debounce).
- Page visibility-change save trigger.
- Ephemeral cell variant (persists `Loading`/`Idle`/`Failed` only, re-fetches `Done` on restore).
- Best-effort restore (per-cell fallback instead of strict all-or-nothing).
- Quota error reporting back to user code.
- Encryption / signing / size-checking of stored payloads.

**Key decisions:**

1. **`localStorage` only via outgoing port + flags.** No restore port; restore is one-shot at boot via flags. Save is a port the user subscribes to. Two pieces of JS glue total.

2. **Flags are `Json.Decode.Value`.** Rad accepts a raw string (parses via `Json.Decode.decodeString Decode.value`), a parsed JSON value (uses directly), or `null` (fresh start). Single code path inside Rad. Same flags type whether `persist = Nothing` or `Just`.

3. **Schema-driven save/restore.** `BuildResult` gains a `List PersistEntry` populated by each builder primitive. Each entry knows the cell's key, type tag, and how to encode/decode that cell's slot(s). Runtime iterates the schema for save and restore.

4. **Strict restore.** Any failure (version mismatch, decode error, non-null-tolerant codec failing on missing cell) discards the whole restore and falls back to init defaults. No half-restored state.

5. **Missing-cell semantic is codec-driven.** Adding a non-null-tolerant cell after deploy invalidates the saved state (strict-fail). Adding a null-tolerant codec silently graceful-restores. Forces explicit thinking about schema drift; migrations cover the harder cases later.

6. **Crash recovery via `inFlight` field on reaction guts.** Reactions self-report whether their target is in-flight; runtime re-fires those after restore. No new "recovering" status — recovery dispatches are indistinguishable from normal trigger-change firings.

7. **Form snapshot keyed by `cell.key` strings.** Layer 5's stringified-runtime-IDs scheme is replaced. Stable across releases as long as the user-supplied keys (and Layer 6 prefixes) don't change.

8. **No migrations in MVP.** `version` mismatch ≡ discard. Any saved state from a previous schema version is dropped. Migrations land in a future Layer (likely 8 or 9).

---

## 2. Module layout after Layer 7

| Module | Audience | New / Changed |
|---|---|---|
| `Rad` | App authors | + `PersistConfig`, `persistNow`. `AppDef` gains `persist`. `run` flags type changes to `Json.Decode.Value`. |
| `Rad.Engine` | Engine authors | + `PersistTimerFired Int`, `PersistRequested` Msg variants. |
| `Rad.Form` | App authors | `field`/`validatedField` capture `cell.key` into `Member`. `dirty`/`reset`/`advanceSnapshot` look up by `cell.key` strings. |
| `Rad.View`, `Rad.Read`, `Rad.Http` | App authors | — (unchanged) |
| `Rad.Internal.Persist` | private | **NEW**: `PersistEntry`, schema-walk save/restore logic, crash-recovery scan. |
| `Rad.Internal.CellBuilder` | private | + `persist : List PersistEntry` field on `BuildResult`. |
| `Rad.Internal.Debounced` | private | + `key : String` field on internal record. |
| `Rad.Internal.Validated` | private | + `key : String` field on internal record. |
| `Rad.Internal.Form` | private | `Member` gains `inputKey : String`. `stateCodec` tolerates `null → initialState`. |
| `Rad.Internal.Reaction` | private | `Guts` gains `inFlight : Registry -> Bool` field. |

**Dependency graph:** `Rad.Internal.Persist` imports `Rad.Internal.Registry`, `Rad.Internal.CellBuilder`, `Rad.Internal.Reaction` (for the `Guts` type and crash-recovery walking). `Rad.elm` imports `Rad.Internal.Persist`. No cycles.

---

## 3. Public API surface

```elm
-- Rad (additions)

type alias PersistConfig msg =
    { key : String                            -- localStorage key (e.g. "myapp")
    , version : Int                            -- schema version (always 1 for MVP)
    , save : ( String, String ) -> Cmd msg     -- outgoing port the user supplies
    }


type alias AppDef view model computed =       -- BREAKING: + persist field
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
    , persist : Maybe (PersistConfig (Rad.Engine.Msg model))
    }


run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program Json.Decode.Value (AppModel model) (Rad.Engine.Msg model)


persistNow : Action model
```

**User wiring (one Elm port + ~5 lines of JS):**

```elm
port module Main exposing (main)

import Json.Decode
import Rad

port persistSave : ( String, String ) -> Cmd msg


app : Rad.AppDef ...
app =
    { init = ...
    , computed = \_ -> {}
    , view = ...
    , reactions = ...
    , persist = Just { key = "myapp", version = 1, save = persistSave }
    }


main : Program Json.Decode.Value (Rad.AppModel Model) (Rad.Engine.Msg Model)
main =
    Rad.run engine app
```

```js
const stored = localStorage.getItem("myapp");                              // string | null
const app = Elm.Main.init({ node: document.getElementById("app"), flags: stored });
app.ports.persistSave.subscribe(([key, json]) => localStorage.setItem(key, json));
```

`persist = Nothing` ⇒ flags ignored, no save ever fires. Existing-style apps work unchanged after adding `persist = Nothing`.

---

## 4. Per-cell persistence schema

`BuildResult` extends:

```elm
type alias BuildResult ctor =
    { nextId : Int
    , metas : List ( Int, Decode.Value )
    , persist : List PersistEntry            -- NEW
    , ctor : ctor
    }
```

`PersistEntry` lives in `Rad.Internal.Persist`:

```elm
type alias PersistEntry =
    { key : String
    , typeTag : String
    , encode : Registry -> Maybe Encode.Value           -- reads the cell's slot(s) from registry
    , decode : Encode.Value -> Registry -> Result String Registry
                                                       -- writes decoded slots into registry
    }
```

**Per cell type:**

| Type | typeTag | blob shape |
|---|---|---|
| `Cell a` | `"cell"` | `{"value": <encoded a>}` |
| `DebouncedCell a` | `"debounced"` | `{"raw": <encoded a>, "settled": <encoded a>, "timerSeq": <int>}` |
| `ValidatedCell err a` | `"validated"` | `{"input": <encoded a>, "validation": <encoded Validation>, "activationSeq": <int>}` |
| `Cell Form.State` (via `Form.withState`) | `"cell"` (uses generic Cell encoder with `stateCodec`) | `{"value": {"snapshot": ..., "submitSeq": <int>, "lastResolvedSubmitSeq": <int>}}` |

In-flight detection for crash recovery is reaction-side, not cell-side — see Section 8.

**Top-level stored format** (one localStorage key, one JSON object):

```json
{
  "version": 1,
  "cells": {
    "search":            {"type": "debounced", "raw": "cats", "settled": "cats", "timerSeq": 0},
    "name":              {"type": "validated", "input": "alice", "validation": {"tag":"Valid","value":"alice"}, "activationSeq": 1},
    "page":              {"type": "cell", "value": 3},
    "category.selected": {"type": "cell", "value": "photos"},
    "category.search":   {"type": "debounced", "raw": "", "settled": "", "timerSeq": 0},
    "profile-form":      {"type": "cell", "value": {"snapshot": null, "submitSeq": 0, "lastResolvedSubmitSeq": 0}}
  }
}
```

The `"type"` tag is included in each blob even though the schema entry already knows the type. This is for human-readability and a sanity check during decode (mismatch ⇒ strict fail). `Rad.Internal.Persist`'s decoders verify the `type` field matches `entry.typeTag` before decoding the rest.

---

## 5. Save flow

**Trigger:** any change to the registry. Implementation: the runtime tracks a `dirtyCounter : Int` bumped on every `ApplyAction` / `ReactionResult`-driven registry transition.

**Debounce:** when the registry mutates, dispatch:

```elm
Process.sleep 500
    |> Task.perform (\_ -> Engine.PersistTimerFired n)
```

where `n` is the current `dirtyCounter` value. When `PersistTimerFired n` arrives, the runtime checks `n == currentDirty`. If yes, save fires; if no, a fresher mutation has already scheduled another timer — this firing is stale. Same latest-wins pattern Layer 3 uses for `DebouncedCell`.

**Save action:**
1. Walk `persist : List PersistEntry` from the schema.
2. For each entry: call `entry.encode registry` → `Maybe Encode.Value`. `Nothing` is a programmer error (cell missing from registry post-init); skipped silently for robustness.
3. Build top-level object:
   ```elm
   Encode.object
       [ ( "version", Encode.int config.version )
       , ( "cells", Encode.object cellPairs )
       ]
   ```
4. `Json.Encode.encode 0 obj` → string.
5. Dispatch `config.save (config.key, jsonString)`.

**`persistNow : Action model`:** sets a per-registry-transition flag; the runtime saves immediately on the next update tick, bypassing the debounce. Encoding path is identical.

**No save on first restore:** when the runtime restores from flags at boot, it does not bump `dirtyCounter` — avoids saving the just-restored state right back.

**Engine changes:**
- `Rad.Engine.Msg model` adds two internal variants: `PersistTimerFired Int` and `PersistRequested`.
- `Rad.run`'s `update` injects a `Cmd` that schedules `Process.sleep 500` whenever the registry changed, parameterised by current `dirtyCounter`.
- No `Sub` is needed — `Process.sleep` returns a `Task`.

---

## 6. Restore flow

**Boot sequence in `Rad.run` (when `persist = Just config`):**

1. Receive `flags : Json.Decode.Value`.
2. Run `runBuilder` → initial model + initial Registry.
3. Try restore:
   ```
   Decode flags as Json.Decode.value (always succeeds; flags IS a Value):
     If null → fresh start (no error).
     If string → Json.Decode.decodeString Decode.value <flags>:
       Err _ → discard, fresh start.
       Ok envelope → continue to (4).
     Otherwise → use flags directly as envelope; continue to (4).

   4. Decode envelope:
        version : Int
        cells   : Dict String Encode.Value
      Any decode error → discard, fresh start.

   5. If storedVersion ≠ config.version → discard, fresh start.

   6. Walk persist schema:
        For each entry:
          If entry.key in cells dict:
            entry.decode (cells.get entry.key) accumulatedRegistry
              Err _ → DISCARD entire restore, fresh start.
              Ok r' → r' becomes accumulatedRegistry.
          If entry.key NOT in cells dict:
            entry.decode Encode.null accumulatedRegistry
              Err _ → DISCARD entire restore, fresh start.
              Ok r' → r' becomes accumulatedRegistry.

      Walk completes successfully → use accumulatedRegistry as the boot registry.
   ```

4. Strict policy throughout. Any failure at any step → fresh start.

5. Cells present in the schema but missing from the stored blob: codec-driven null fallback (Section 4 / per-cell-type missing-fallback). Cells present in stored blob but missing from schema: silently dropped (schema may have shrunk).

**Implementation:** `Rad.Internal.Persist.restore : PersistConfig msg -> List PersistEntry -> Registry -> Decode.Value -> Registry`. Always returns a Registry. If anything fails, it returns the input `initialRegistry` unchanged.

---

## 7. Missing-cell semantic (codec-driven)

When a cell's `entry.key` is absent from the stored `cells` dict, Rad invokes `entry.decode Encode.null registry`. Each cell type's decoder handles null-input as follows:

| Cell type | If `codec.decode null` succeeds with `v : a` | If `codec.decode null` fails |
|---|---|---|
| `Cell a` | write `codec.encode v` to `id` | strict fail → discard whole restore |
| `DebouncedCell a` | write `codec.encode v` to `rawId` and `settledId`; write `Encode.int 0` to `timerSeqId` | strict fail → discard whole restore |
| `ValidatedCell err a` | write `codec.encode v` to `inputId`; write encoded `Dormant` to `validationId`; write `Encode.int 0` to `activationSeqId` | strict fail → discard whole restore |
| `Cell Form.State` | special-cased: `Form.stateCodec.decode null` ALWAYS produces `initialState`. Missing form-state cells transparently restore as fresh forms. | n/a (always tolerant) |

**`Form.stateCodec` amendment:** Layer 5's `stateCodec.decode` is amended to accept `null`:

```elm
stateCodec : { encode : State -> Decode.Value, decode : Decode.Decoder State }
stateCodec =
    { encode = ...
    , decode =
        Decode.oneOf
            [ Decode.null initialState
            , Decode.map3 State
                (Decode.field "snapshot" Decode.value)
                (Decode.field "submitSeq" Decode.int)
                (Decode.field "lastResolvedSubmitSeq" Decode.int)
            ]
    }
```

**User-facing rule:** "Use a null-tolerant codec for any cell where graceful schema-drift is OK; use a strict codec to force re-init on schema change." This puts the choice explicitly in the user's hands.

---

## 8. Crash recovery

After a successful restore, the runtime walks the user's reaction list and re-fires any reaction whose target is in-flight. Handles the case where the page was closed mid-effect.

**Mechanism:** `IReaction.Guts` gains a new field:

```elm
type alias Guts =
    { readTrigger : Registry -> Encode.Value
    , buildRequest : Registry -> InternalRequest
    , writeLoading : Registry -> Registry
    , writeResult : Encode.Value -> Registry -> Registry
    , inFlight : Registry -> Bool                    -- NEW
    }
```

After restore + first `view` cycle, the runtime invokes `recoverInFlight` for each reaction:

```elm
recoverInFlight : Registry -> List (Reaction model) -> List (Cmd (Engine.Msg model))
recoverInFlight registry reactions =
    reactions
        |> List.filterMap
            (\(IReaction.Reaction g) ->
                if g.inFlight registry then
                    case g.buildRequest registry of
                        IReaction.DispatchTask task ->
                            Just (Task.perform Engine.ReactionResult task)

                        IReaction.SkipRequest ->
                            Nothing

                else
                    Nothing
            )
```

**Per-reaction `inFlight` implementations:**

- **`Rad.on`** — decodes target `Cell (Remote err r)` and checks `tag == "Loading"`.
- **`Rad.validationReaction`** — decodes `validationId` slot and checks `tag == "Checking"`.
- **`Form.onSubmit`** — `submitSeq > lastResolvedSubmitSeq` AND target Cell is in `Loading` state.
- **`Form.onValid`** — `submitSeq > lastResolvedSubmitSeq` (no target cell to check).
- **`Form.reactions`'s child validations** — lifted from the captured `reactionGuts` of each `ValidatedMember`; uses the `Rad.validationReaction` `inFlight` directly.

**Order independence:** recovery walks reactions sequentially. Reactions are independent (Layer 2 invariant). Latest-wins seq machinery handles any genuine race between recovered reactions and freshly-triggered ones (rare in practice — would require user interaction during the boot frame).

**No special "recovering" status:** the dispatched recovery firing is indistinguishable from a normal trigger-change firing. `writeLoading` re-asserts `Loading`/`Checking` (idempotent), then the task lands like any other.

---

## 9. Form snapshot key fix

Layer 5's `Form.State.snapshot` is keyed by `String.fromInt cellId`. That makes the snapshot fragile across releases — adding a `with` earlier in the pipeline shifts every cell's runtime ID.

**Fix:** key the snapshot by `cell.key` strings (the namespaced persistence keys Layer 6 stamps on each `Cell`).

**Changes:**
1. `Rad.Internal.Form.Member` gains an `inputKey : String` field on both `PlainMember` and `ValidatedMember`. Captured at construction time via `Rad.cellKey cell` for plain cells, and `Rad.cellKey (Rad.input vcell)` for validated cells.
2. `Form.dirty` and `Form.reset` look up by `inputKey` instead of `String.fromInt inputId`.
3. `advanceSnapshot` writes pairs `(member.inputKey, current)` into the snapshot object.
4. New private helper `memberInputKey : Member -> String` (sibling of `memberInputId`).

**Test impact:** `FormDirtyTest`'s "non-null snapshot" test currently writes a snapshot keyed by `String.fromInt cellId`. Updated to use the cell's `cellKey`. Same change for `FormResetTest` if it has equivalent setup.

**Migration concern:** any user with Layer 5 snapshots in storage will hit a strict-fail on first restore (the snapshot keyed by old IDs won't match the new key-based lookup). Acceptable — Layer 5 is freshly shipped, no published apps yet, and the strict-fail discards cleanly.

---

## 10. Tests

| Suite | Coverage |
|---|---|
| `PersistEntryTest` | Per-cell-type encode/decode round-trip for `Cell`, `DebouncedCell`, `ValidatedCell`, `Cell Form.State`. Missing-cell + null-tolerant codec → fallback. Missing-cell + non-null codec → strict fail. Malformed blob → strict fail. |
| `PersistRestoreTest` | Strict version mismatch → discard. Strict decode failure on any cell → discard. Whole flow: serialize → deserialize → equal Registry. Tests use `Encode.Value` directly (no JSON round-trip needed). |
| `PersistSaveDebounceTest` | Multiple registry mutations within 500ms → single save fires after window with latest content. `persistNow` action bypasses debounce. |
| `PersistCrashRecoveryTest` | Restore with a `Loading` Remote → reaction's `inFlight` is True → recovery dispatches. Same for `Checking` validation. Settled cells don't re-fire. |
| `FormSnapshotKeyTest` | `Form.dirty` / `Form.reset` / `advanceSnapshot` use `cell.key` strings post-fix. Layer 6 namespacing produces correct snapshot keys (`"profile.name"`, etc.). |

**Existing test updates:** `FormDirtyTest` and `FormResetTest` re-keyed to `cell.key`.

**Expected test count:** 118 → ~150 (~30 new tests across 5 new suites + 2 updated).

---

## 11. Examples

**`L07E01-persist-counter`** — minimal demo:
- One `Cell Int` counter.
- `persist = Just { key = "L07E01-counter", version = 1, save = persistSave }`.
- Increment / decrement buttons; counter persists across page refresh.
- One Elm port declaration + 5 lines of JS glue.

**Why one example:** the persistence machinery is invisible at the call site — adding `persist = Just { ... }` to an existing app is the entire user experience. A single counter example demonstrates the wiring without bloating the example list. Layer 5's `L05E01-profile-form` could be retrofitted with persistence in a docs/cookbook follow-up.

---

## 12. Edge cases

| Scenario | Behavior |
|---|---|
| `persist = Nothing` with non-null flags | flags ignored. No restore. No save. |
| `persist = Just`, flags = `null` | fresh start. No error. |
| `persist = Just`, flags = unparseable string | discard, fresh start. |
| `persist = Just`, flags = parsed-but-malformed object | discard, fresh start. |
| `persist = Just`, version mismatch | discard, fresh start. |
| Cell missing in stored blob, codec accepts `null` | initialize with codec's null-decoded value. |
| Cell missing in stored blob, codec rejects `null` | strict fail → discard whole restore. |
| Cell present in stored blob with malformed inner shape | strict fail → discard whole restore. |
| Cell present in stored blob, schema removed it | silently dropped. |
| Save fires while another save is in flight | both write to localStorage; latest wins. (No batching needed; localStorage writes are synchronous from JS's perspective.) |
| User clicks `persistNow` while debounce timer pending | immediate save dispatches; the pending timer fires with no-op (its `n != currentDirty` check). |
| Crash recovery: restore puts a `Loading` cell back; reaction re-fires with current source | matches Layer 2 semantics; recovery is indistinguishable from normal trigger-change. |
| Storage quota exceeded | save fails silently in JS (the user's JS subscription is responsible). Rad doesn't surface quota errors in MVP. |
| Storage cleared between save and restore | flags = `null` → fresh start. No special handling needed. |

---

## 13. Non-goals

- Layer 7 does not provide encryption, signing, or compression of stored data.
- Layer 7 does not ship migration helpers; version mismatch ⇒ discard.
- Layer 7 does not introduce any user-facing "is restoring" status; the restore happens before `view` is first called.
- Layer 7 does not change the runtime's reaction-seq semantics; recovery dispatches use the same machinery as any reaction.
- Layer 7 does not require changes to existing `Rad.Engine.ViewEngine` interface; engines are unaffected.
- Layer 7 does not add a `Sub` for storage events (no cross-tab sync); the user can wire that themselves if desired.
