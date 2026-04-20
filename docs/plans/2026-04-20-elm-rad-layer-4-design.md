# elm-rad Layer 4 Design — Validated Cells

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–3 shipped (cells, reactions, `Remote`/`Request`, `Rad.Http`, debounced cells).

---

## 1. Scope

Layer 4 adds validation as a cell-level concern. A `ValidatedCell err a` wraps a writable input with a reactive validation state that reports whether the current value satisfies a user-supplied `Validator`. Validators can be synchronous, asynchronous (via `Request err a`), or composed in sequence.

**In scope:**
- `Validation err a` — `Dormant | Checking | Valid a | Invalid (List err)`.
- `validationCodec : Codec err -> Codec a -> Codec (Validation err a)` — tagged-object wire format, mirrors `remoteCodec`.
- `Validator err a` opaque type. Builder functions: `sync`, `async`, `compose`.
- `ValidatedCell err a` opaque type. Builder entry: `withValidated : String -> a -> Codec a -> Validator err a -> CellBuilder (ValidatedCell err a -> rest) -> CellBuilder rest`.
- Accessors: `input : ValidatedCell err a -> Cell a` (writable), `validation : ValidatedCell err a -> Source (Validation err a)` (read-only).
- Actions: `validate : ValidatedCell err a -> Action model` (activates), `resetValidation : ValidatedCell err a -> Action model` (returns to Dormant).
- `validationReactions : ValidatedCell err a -> List (Reaction model)` — user composes into `AppDef.reactions`.
- Three example apps: `required-name`, `email-format`, `username-available`.
- `elm-test` suites: construction & accessors, validator evaluation, lifecycle, latest-wins.
- Vite mock endpoint `GET /api/username-check?q=`.

**Out of scope:**
- Forms (Layer 5), `ValidatedGroup`, form-level gating.
- Persistence and validation-state re-fire on restore (Layer 7).
- New view primitives (`bindValidated`, etc.) — users compose `bind (input vcell)` + `watch (validation vcell)` with existing primitives.
- Debounced validation — achievable by orchestrating `DebouncedCell` + `ValidatedCell` via a user-written reaction that copies settled → input.
- Fast-path for sync validators (one Cmd round-trip is accepted).

**Key decisions (for future user-facing docs):**

1. **Polymorphic error type.** `Validator err a` and `Validation err a` carry the user's error type. Hardcoded `List String` was rejected for consistency with Layer 2's `Remote err a`.

2. **Validator constructors are opaque.** Users build validators via `sync`, `async`, `compose`. The internal variants live in `Rad.Internal.Validated` and aren't re-exported. Keeps the API surface small and lets later layers add variants (`deferred`, `whenDirty`) without breaking call sites.

3. **Reuse Layer 2 reaction machinery.** Each `ValidatedCell` produces one `Reaction` (built manually, not via `Rad.on` because `on` writes to `Cell (Remote err r)`). The reaction fires on trigger changes and dispatches the validator via the existing `Task Never Encode.Value` path.

4. **Activation via integer seq, not Bool.** `validate` bumps the activation seq (1 → 2 → 3); each bump changes the reaction's trigger and re-fires the validator. `resetValidation` writes 0. A Bool would miss repeated `validate` clicks against unchanged input.

5. **Sync validators go through the Cmd loop** — they dispatch through the reaction like async validators. Users see a one-frame `Checking` flash on sync validation. Acceptable for MVP; fast-path deferred.

6. **`validationReactions` composed manually by the user.** Keeps Layer 2's runtime surface unchanged and keeps control flow grep-able. Layer 5 Forms will collect and pre-compose.

---

## 2. Module layout after Layer 4

| Module | Audience | New in Layer 4 |
|---|---|---|
| `Rad` | App authors | `Validation(..)`, `validationCodec`, `Validator`, `sync`, `async`, `compose`, `ValidatedCell`, `withValidated`, `input`, `validation`, `validate`, `resetValidation`, `validationReactions` |
| `Rad.Engine` | Engine authors | — (unchanged) |
| `Rad.View` | App authors | — (unchanged) |
| `Rad.Read` | App authors | — (unchanged) |
| `Rad.Http` | App authors | — (unchanged) |
| `Rad.Internal.Validated` | private | **NEW**: `ValidatedCell(..)`, `Core err a`, `Ref`, `Validator(..)`, `core`, `ref`, `applyValidator`, `validationReaction` |

**What does NOT change:**
- Runtime signature: `run : ViewEngine -> AppDef -> Program ...` — unchanged.
- `AppModel`, `AppDef`, all existing types and fields — unchanged.
- No new `Msg` variants. Layer 4 dispatches through existing Layer 2 reaction machinery.
- No new package dependencies.

---

## 3. Types and wire format

```elm
-- Rad (public)

type Validation err a
    = Dormant
    | Checking
    | Valid a
    | Invalid (List err)

validationCodec : Codec err -> Codec a -> Codec (Validation err a)

type Validator err a  -- opaque

sync : (a -> Result (List err) a) -> Validator err a
async : (a -> Request (List err) a) -> Validator err a
compose : List (Validator err a) -> Validator err a

type ValidatedCell err a  -- type alias Rad.DebouncedCell-style over internal type

withValidated :
    String -> a -> Codec a -> Validator err a
    -> CellBuilder (ValidatedCell err a -> rest) -> CellBuilder rest

input      : ValidatedCell err a -> Cell a
validation : ValidatedCell err a -> Source (Validation err a)
validate        : ValidatedCell err a -> Action model
resetValidation : ValidatedCell err a -> Action model
validationReactions : ValidatedCell err a -> List (Reaction model)
```

**`validationCodec` wire format** — tagged objects, consistent with `remoteCodec`:

- `{"tag":"Dormant"}`
- `{"tag":"Checking"}`
- `{"tag":"Valid","value":<encoded a>}`
- `{"tag":"Invalid","errors":[<encoded err>, ...]}`

**`Request`'s err channel is `List err`.** Users wrapping HTTP validators do:

```elm
async (\name ->
    Http.httpGet prodHandler ("/api/check?q=" ++ name) availabilityDecoder
        |> mapRequestError (\netErr -> [ LookupFailed netErr ])
)
```

---

## 4. Runtime shape and activation semantics

### Registry slots per `ValidatedCell`

Three slots allocated sequentially by `withValidated`:

| Slot | Contents | Initial value |
|---|---|---|
| `inputId` | encoded `a` | `codec.encode initial` |
| `validationId` | encoded `Validation err a` | `validationCodec.encode Dormant` |
| `activationSeqId` | encoded `Int` | `Encode.int 0` |

### Internal shape

```elm
-- Rad.Internal.Validated
type ValidatedCell err a
    = ValidatedCell (Core err a)

type alias Core err a =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    , codec : { encode : a -> Value, decode : Decoder a }
    , validationCodec : { encode : Validation err a -> Value, decode : Decoder (Validation err a) }
    , validator : Validator err a
    , initial : a
    }

type alias Ref =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    }
```

### Action semantics

- **`validate vcell`** — reads `activationSeqId`, writes `current + 1` back. Trigger-change semantics: on first `validate`, seq moves 0 → 1 (trigger changes, reaction fires). Repeated `validate` calls with unchanged input still fire (1 → 2 → 3 → ...).

- **`resetValidation vcell`** — writes `Dormant` (encoded) to `validationId` AND `0` to `activationSeqId`. Trigger changes; reaction fires; `buildRequest` sees seq=0 and returns `SkipRequest`. No dispatch. Validation stays Dormant.

### The validation reaction

`validationReaction vcell` builds the `Reaction` record directly (not via `Rad.on`):

```elm
-- Simplified; actual code reads through Registry with codec fallback.
Reaction
    { readTrigger = \reg ->
          Encode.list identity
              [ codec.encode (readInput reg)
              , Encode.int (readActivationSeq reg)
              ]

    , buildRequest = \reg ->
          let activationSeq = readActivationSeq reg in
          if activationSeq == 0 then
              SkipRequest
          else
              DispatchTask
                  (applyValidator validator (readInput reg)
                      |> Task.map validationCodec.encode)

    , writeLoading = \reg ->
          insert validationId (validationCodec.encode Checking) reg

    , writeResult = \encoded reg ->
          insert validationId encoded reg
    }
```

### `applyValidator : Validator err a -> a -> Task Never (Validation err a)`

```elm
applyValidator validator value =
    case validator of
        Sync f ->
            case f value of
                Ok a -> Task.succeed (Valid a)
                Err errs -> Task.succeed (Invalid errs)

        Async buildReq ->
            case buildReq value of
                NoRequest -> Task.succeed (Valid value)
                DispatchRequest task ->
                    task
                        |> Task.map Valid
                        |> Task.onError (\errs -> Task.succeed (Invalid errs))

        Compose validators ->
            List.foldl
                (\v accTask ->
                    accTask |> Task.andThen (\vState ->
                        case vState of
                            Valid currentValue -> applyValidator v currentValue
                            _ -> Task.succeed vState  -- short-circuit
                    )
                )
                (Task.succeed (Valid value))
                validators
```

**Compose semantics:**
- Validators run left-to-right.
- On first `Invalid`, the fold short-circuits (subsequent validators skipped).
- `Async NoRequest` is treated as `Valid value` — a validator that says "nothing to check, pass through."
- Between sequential async validators, the outer cell stays `Checking` for the whole duration (set once by `writeLoading`, updated at the end by `writeResult`).

### Reaction firing lifecycle (integration with Layer 2)

Nothing new at the runtime level. Once `validationReactions vcell` is concatenated into the user's `AppDef.reactions` list, Layer 2's runtime:
1. Computes the trigger (combined JSON of input value + activation seq).
2. Detects change, bumps Layer 2's per-reaction seq, calls `buildRequest`.
3. If `SkipRequest`, no dispatch.
4. If `DispatchTask task`, calls `writeLoading` (sets `Checking`) and `Task.attempt` dispatches.
5. On task resolution, checks Layer 2's reaction seq; applies `writeResult` if current.

**Latest-wins is inherited from Layer 2** — no new mechanism.

---

## 5. Examples and Vite middleware additions

### Three new example apps

**1. `required-name`** — Sync validator baseline.

- Model: `{ nameCell : ValidatedCell String String }`.
- Validator: `sync (\s -> if String.trim s == "" then Err [ "name required" ] else Ok s)`.
- View: name input (`bind (input model.nameCell)`), Validate button (calls `validate`), Reset button (calls `resetValidation`), and a `watch (validation model.nameCell)` that renders:
  - `Dormant` → empty string
  - `Checking` → "checking…"
  - `Valid _` → "✓ looks good"
  - `Invalid errs` → joined err text
- `AppDef.reactions = \model _ -> validationReactions model.nameCell`.
- Demonstrates: lifecycle, dormant-until-activated, reactive re-validation after activation.

**2. `email-format`** — Sync validator with typed error type.

- Model: `{ emailCell : ValidatedCell EmailError String }`.
- Custom type: `type EmailError = Empty | MissingAt | TooLong`.
- `emailValidator : Validator EmailError String` uses `sync` and accumulates errors into `List EmailError`.
- View pattern-matches each `EmailError` variant to a human string.
- Demonstrates: polymorphic err, multiple simultaneous errors, user-defined error codec.

**3. `username-available`** — Async validator via `Rad.Http` with `compose`.

- Model: `{ username : ValidatedCell UsernameError String }`.
- Custom type: `type UsernameError = EmptyName | AlreadyTaken | LookupFailed Rad.Http.RequestError`.
- Validator: `compose [ sync (nonEmpty >> mapErr singleton), async checkAvailability ]`.
- `checkAvailability` hits new mock endpoint; on `{available: true}` returns `Ok name`, on `{available: false}` returns `Err [AlreadyTaken]`. Network errors map via `mapRequestError (\e -> [LookupFailed e])`.
- View renders `Checking` during the ~1.5s mock delay.
- Demonstrates: async validator, compose short-circuit (empty name never hits the network), typed error type wrapping `RequestError`.

### Vite middleware addition

Add to `examples/mock-api-plugin.js`:

```javascript
server.middlewares.use("/api/username-check", (req, res, next) => {
  if (req.method !== "GET") return next();
  const url = new URL(req.url || "/", "http://localhost");
  const q = url.searchParams.get("q") || "";
  sendJson(res, { available: q !== "taken" }, 1500);
});
```

"taken" → unavailable; anything else → available. ~1.5s delay for visible `Checking` state.

### Entries added to `examples/vite.config.js` `rollupOptions.input`

- `required-name`, `email-format`, `username-available`.

### New `.html` + `.elm` files under `examples/`

Standard MPA entry + `Elm.X.init` pattern; matches existing examples.

---

## 6. Testing strategy

### Pure elm-test suites (four new files)

**`ValidatedTest.elm`** — construction & accessors
- `withValidated` allocates exactly three Registry slots with correct initial values (input = initial, validation = encoded Dormant, activationSeq = 0).
- Slot IDs are distinct and sequential from `CellBuilder.nextId`.
- `input vcell` returns a `Cell a` whose `id` matches `Core.inputId`; writes via `set (input vcell) v` land in the input slot.
- `validation vcell` returns a `Source (Validation err a)` reading `Core.validationId`.
- Codec round-trip: all four `Validation` variants survive encode/decode via `validationCodec`.

**`ValidatorTest.elm`** — `applyValidator` behavior
- `sync` with `Ok a` → `Valid a`; with `Err errs` → `Invalid errs`. (Testable directly because the Sync case resolves synchronously inside the Task — use the pattern-matching extraction helper exposed in `Rad.Internal.Validated`.)
- `compose` with first validator failing → second never runs (assert via a sentinel `sync` that would `Debug.crash` or a counter cell that fails the test if ever touched).
- `compose` with first validator passing → second validator receives the first's `Ok` value.
- `async` with `NoRequest` → resolves to `Valid value`.
- Empty `compose []` → `Valid value` (identity).

**`ValidatedLifecycleTest.elm`** — actions + reaction trigger
- `validate` action increments `activationSeqId` (0 → 1 → 2 → 3).
- `resetValidation` action writes `Dormant` to `validationId` AND `0` to `activationSeqId`.
- `validationReactions vcell` returns exactly one `Reaction`.
- The reaction's `readTrigger` is stable when input and activationSeq don't change.
- `readTrigger` differs when input changes.
- `readTrigger` differs when activationSeq changes.
- `buildRequest` returns `SkipRequest` when activationSeq is 0.
- `buildRequest` returns `DispatchTask _` when activationSeq is non-zero.
- `writeLoading` writes encoded `Checking` to `validationId`.
- `writeResult` writes the given encoded value to `validationId`.

**`ValidatedLatestWinsTest.elm`** — async supersession
- Simulate two sequential dispatches by manually invoking `writeLoading` / `writeResult` twice with different encoded values. Verify that the last `writeResult` wins (latest-wins is property of the runtime's reaction-seq check, not of `writeResult` itself — this test pins the contract).

### Live browser verification

Each example must exhibit:
- `required-name`: type in a name → nothing shown. Click Validate → if empty, "name required" shown; else "✓ looks good". Change input → error/success updates reactively. Click Reset → back to blank state.
- `email-format`: fill an invalid email → click Validate → multiple errors shown via pattern match.
- `username-available`: type a name → click Validate → "checking…" visible for ~1.5s → success or "already taken" (for "taken" input).

### Deliberately not tested

- Real-clock timing.
- DOM event simulation beyond what view bindings provide.
- `applyValidator` for Async via actual task execution (Elm test runner can't drive Tasks). Structural assertion via `DispatchTask` shape is the substitute.

---

## 7. Forward-compat shaping

Decisions in Layer 4 so Layers 5–8 land without rework:

- **`Validator err a` opaque behind `sync`/`async`/`compose`.** Future layers add `deferred`, `whenDirty`, or time-limited validators by adding builder functions; existing call sites don't change.
- **`Validation err a` wire format matches `Remote err a` style.** Layer 7 persistence serializes identically. On restore, `Checking` states re-fire the validator (the cell's reaction re-triggers on boot, same as Layer 2 reactions).
- **`validationReactions` is a plain list.** Layer 5 Forms will produce `formReactions : Form fields -> List (Reaction model)` that concatenates field-level reactions. No runtime change.
- **Three Registry slots per `ValidatedCell`** — matches `DebouncedCell`'s three-slot footprint. Predictable builder cost; Layer 5 `Form` builder multiplies this by the number of fields without surprises.
- **No new `Msg` variants.** Layer 4 uses Layer 2's existing `ReactionResult` path. Engines stay unchanged through Layer 4 regardless of what the app wires.
- **Async validators use `Request err a`.** The same effect-library seam used for HTTP reactions. WebSocket or timer-based validators (Layer 8+) plug in with no runtime changes.
- **`Rad.Internal.Validated` mirrors `Rad.Internal.Debounced`.** Consistent sibling pattern means Layer 5 (Forms) has a clear template for `Rad.Internal.Form`.

**Explicitly deferred:**
- Single-error convenience (`Validation err a` always uses `List err`; a single-error variant is not worth the API split).
- Async-validator debounce integration — user-orchestrated via Layer 3.
- View primitive for validation state — users compose existing `watch` + pattern match.

---

## 8. Risks and open questions

**Risks**

1. **Sync validators flash `Checking` for one frame.** Because all validators go through the Cmd loop, a pure-sync validator shows `Checking` for one render cycle before landing on `Valid`/`Invalid`. In practice imperceptible; documented. If problematic, a future sync fast-path can write directly from the Action.

2. **`compose` of many async validators accumulates latency.** Sequential `Task.andThen` means total time is the sum. Consumers who want parallel validation can roll their own (e.g., fire multiple reactions against the same input). Layer 4 documents the sequential semantics; parallel compose not in scope.

3. **User forgets to include `validationReactions vcell`** in `AppDef.reactions`. Consequence: the cell never transitions out of `Dormant` regardless of `validate` calls. Discoverable via the "no Checking ever appears" symptom in example browser tests. Design choice: explicit composition beats hidden auto-wiring; grep-ability wins.

4. **Async supersession relies on Layer 2's reaction-seq.** If Layer 2's seq invariant ever shifts, Layer 4 inherits the change — but also for free if the mechanism improves. Acceptable coupling; the alternative (per-cell seq) duplicates Layer 2 code.

**Open questions (decided here)**

1. **Should `validate` re-run the validator even when input hasn't changed since the last `validate`?** Yes — the design uses an integer seq that bumps on each `validate` call, so click-click fires the validator twice. This supports "re-validate to pick up server-side state" UX patterns. A Bool-activation alternative would only fire once and was rejected.

2. **Should `Validator` constructors be exposed?** No. Opaque behind `sync`/`async`/`compose`. Keeps the API small and lets later layers add variants without breaking call sites.

3. **Should `input` return `Cell a` or `Source a`?** `Cell a` (writable). Matches the design doc and lets users wire `bind (input vcell)` directly. The returned `Cell` shares the ValidatedCell's inputId — reads and writes both flow through the same Registry slot.

4. **Should Layer 4 add a view primitive (`bindValidated`, `validatedInput`)?** No for MVP. `bind (input vcell)` + `watch (validation vcell)` composes existing primitives cleanly. A future convenience wrapper is additive.

5. **Should sync validators skip the Cmd loop?** No for MVP. Uniform dispatch through the reaction is simpler and the one-frame Checking flash is imperceptible. Fast-path deferred to if it becomes a measured problem.

---

## 9. Six vertical slices

Each slice ends with green `elm make`, green `elm-test` (where applicable), and a visible checkpoint.

### Slice 1 — Types + `Rad.Internal.Validated` + `withValidated`

Package:
- New `Rad.Internal.Validated` with `ValidatedCell(..)`, `Core err a`, `Ref`, `Validator(..)`, `core`, `ref`.
- `Rad.Validation(..)`, `Rad.validationCodec`, `Rad.ValidatedCell` (type alias), `Rad.withValidated` exposed.

Tests: `ValidatedTest.elm` — construction, three-slot allocation, initial values, source accessors (to be fleshed out in Slice 2).

Checkpoint: `withValidated` compiles; initial registry carries three expected slots.

### Slice 2 — Validator builders + Source/Action accessors

Package:
- `Rad.sync`, `Rad.async`, `Rad.compose` — opaque constructors via `Rad.Internal.Validated`.
- `Rad.input`, `Rad.validation` sources.
- `Rad.validate`, `Rad.resetValidation` actions.

Tests: `ValidatedTest.elm` extended (read input/validation via sources); `ValidatedLifecycleTest.elm` starts with `validate`/`resetValidation` semantics.

Checkpoint: an app can construct a `ValidatedCell`, read its sources, dispatch lifecycle actions — no reactions yet.

### Slice 3 — `applyValidator` + `ValidatorTest`

Package:
- `applyValidator : Validator err a -> a -> Task Never (Validation err a)` in `Rad.Internal.Validated`.
- Plus any pattern-matching helpers that make Sync-case assertions pure-testable.

Tests: `ValidatorTest.elm` — sync ok/err, compose short-circuit, async NoRequest, composed-with-failing-first doesn't fire async.

Checkpoint: the validator evaluation logic is exhaustively tested in isolation.

### Slice 4 — `validationReactions` + `ValidatedLatestWinsTest`

Package:
- `Rad.Internal.Validated.validationReaction : ValidatedCell err a -> Reaction model` — builds the Reaction record directly.
- `Rad.validationReactions vcell = [ validationReaction vcell ]` — public helper.

Tests:
- `ValidatedLifecycleTest.elm` extended with trigger semantics (SkipRequest when seq=0, DispatchTask otherwise, readTrigger sensitivity to both input and activationSeq).
- `ValidatedLatestWinsTest.elm` — writeResult overwrite semantics (Layer-2-inherited latest-wins).

Checkpoint: a user can plug `validationReactions vcell` into `AppDef.reactions` and validation becomes reactive.

### Slice 5 — `required-name` + `email-format` examples

Examples:
- `RequiredName.elm` + html + vite entry + index link.
- `EmailFormat.elm` + html + vite entry + index link.

Checkpoint: both sync examples render and transition through Dormant → Valid/Invalid correctly in-browser.

### Slice 6 — `username-available` example + docs sweep

Examples:
- Mock endpoint `GET /api/username-check?q=` in `examples/mock-api-plugin.js` (~1.5s, `available: name != "taken"`).
- `UsernameAvailable.elm` (compose sync+async) + html + vite entry + index link.

Docs:
- Append "Implementation notes" subsection to the Validation section of `docs/design-elm-rad.md` recording the five Layer 4 decisions (three slots, seq-based activation, reactions reused, sync through Cmd loop, validator opacity).

Checkpoint: the async example shows `Checking` for ~1.5s before landing; typing "taken" produces `Invalid [AlreadyTaken]`.

---

## 10. Success criteria

Layer 4 is complete when:

- `Rad`, `Rad.Engine`, `Rad.Http`, `Rad.Read`, `Rad.View` all compile cleanly via `elm make --docs`.
- Every `elm-test` suite in Section 6 passes (four new suites with ~15–18 tests; previous Layer 0-3 suites unchanged).
- All 13 Layer 0-3 example apps still render and behave correctly.
- All three new Layer 4 example apps render and behave correctly against the Vite mock server.
- `npm run build` in `examples/` produces a multi-entry production build for all **17 entries** (13 pre-Layer-4 example apps + 3 new Layer 4 apps + the landing page).
- Commit history is granular: one coherent change per commit, ordered such that each commit individually compiles and passes whatever tests exist at that point.
- `docs/design-elm-rad.md`'s Validation section gains an Implementation notes subsection recording the five Layer 4 decisions.
