# elm-rad — Layer 2 Implementation Design

**Date:** 2026-04-19
**Scope:** Second incremental pass of the DSL defined in [`docs/design-elm-rad.md`](../design-elm-rad.md). Builds on the Layers 0 & 1 foundation in [`2026-04-17-elm-rad-layers-0-1-design.md`](2026-04-17-elm-rad-layers-0-1-design.md).
**Strategy:** Example-driven vertical slices. Reactions dispatched through user-constructed effect libraries. Core stays effect-library-agnostic.

---

## 1. Scope & non-goals

**In scope:**
- **`Remote err a`** — parametric over error type: `Idle | Loading | Failed err | Done a`, plus `remoteCodec : Codec err -> Codec a -> Codec (Remote err a)`.
- **`Request err a`** — opaque, parametric over error type; constructor `noRequest`, combinator `mapRequestError`.
- **`Reaction model`** — opaque; constructed via `on : Source a -> (a -> Request err r) -> Cell (Remote err r) -> Reaction model`.
- **`AppDef.reactions : model -> computed -> List (Reaction model)`** — new field.
- **Latest-wins cancellation** — monotonic sequence number per reaction index; stale results discarded.
- **`Source a` carries a `Codec a`** — required for trigger-change detection. Breaking change: `derive : Codec a -> Read a -> Source a`.
- **`Rad.Http` module** — `Handler`, `prodHandler`, `httpGet`, `httpPost`, `RequestError`, `requestErrorCodec`. Depends on `elm/http`. Core package stays HTTP-free.
- **Four example apps** — `fetch-joke`, `github-user`, `post-note`, `derived-search`.
- **Vite dev-server mock middleware** — four `/api/*` endpoints with ~2s delay, hosted in-examples.
- **Scrappy `TestRunner.elm`** in examples — demonstrates the mock-handler testing pattern.
- **`elm-test` suites** — `RemoteCodecTest`, `SourceCodecTest`, `RequestTest`, `ReactionTriggerTest`, `LatestWinsTest`.

**Out of scope:**
- Debounce (Layer 3), Validation (Layer 4), Forms (Layer 5).
- Components, `embed`, `include`, `withInstance` (Layer 6).
- Persistence and crash-recovery re-fire (Layer 7).
- SVG/Canvas engines (Layer 8).
- A polished public `Rad.Test` harness — deferred until after Layer 2 has shaken out.
- WebSockets, timers, subscriptions beyond what reactions need.

**Key decisions (for future user-facing docs):**

1. **Core is effect-library-agnostic.** `Request err a` is opaque and carries a `Task err a`. Effect libraries (HTTP today, WebSocket/Timer later) ship as separate modules with their own `Handler` types and `Request` constructors. Core has zero `elm/http` dependency. The `Rad.Http` module owns HTTP entirely.

2. **Error type is user-chosen.** `Remote err a` and `Request err a` are parametric over their error type. `Rad.Http.RequestError` is offered as a convenient default; apps that want a domain error type call `mapRequestError` to convert.

3. **Trigger change detection via JSON equality.** The runtime compares the encoded JSON of a trigger source's current vs. previous value. `Source a` therefore carries `Codec a`; `derive` gains a codec argument.

4. **Latest-wins via monotonic sequence numbers.** Each reaction index has a seq counter. A dispatch increments it; a result arriving with a stale seq is dropped. Task cancellation is not real in Elm; the HTTP request still completes on the wire, but the result never reaches the registry.

5. **Infinite loops are a consumer concern.** Layer 2 prevents the immediate feedback case (a reaction writing its own target doesn't re-check triggers after writing) but pathological multi-reaction cycles remain possible and are documented as consumer responsibility. Future layers may add structural checks.

---

## 2. Module layout after Layer 2

| Module | Audience | New in Layer 2 |
|---|---|---|
| `Rad` | App authors | `Remote err a`, `remoteCodec`, `Request err a` (opaque), `noRequest`, `mapRequestError`, `Reaction model` (opaque), `on`, new `AppDef.reactions` field |
| `Rad.View` | App authors | — (unchanged) |
| `Rad.Read` | App authors | — (unchanged) |
| `Rad.Engine` | Engine authors | `Msg model` gains an internal `ReactionResult` variant (runtime-only; opaque to engines) |
| `Rad.Http` | App authors | **new** — `Handler`, `prodHandler`, `httpGet`, `httpPost`, `RequestError`, `requestErrorCodec` |
| `Rad.Internal.Reaction` | private | Internal shape of `Reaction`, trigger read/encode, request build, registry writers |
| `Rad.Internal.Source` | private | `Source a` grows a `codec : Codec a` field (breaking: `derive` signature changes) |

**Breaking changes to Layer 0-1 user code (all in-repo):**

1. `derive : Read a -> Source a` → `derive : Codec a -> Read a -> Source a`. Call sites in `FullName.elm` and `Temperature.elm` add `stringCodec`.
2. `AppDef` gains a `reactions` field. Layer 0-1 examples set it to `\_ _ -> []` as a one-line edit.

Both are mechanical, migrated in the same commits that land the breaking changes so the tree compiles at every step.

**What does NOT change:**
- `run : ViewEngine -> AppDef -> Program ...` — identical signature. No `Handler` parameter in core.
- `Cell a`, `Source a` as a type, `Action model`, `Attribute model` — unchanged at the type level.
- HTML engine primitives, SimpleView engine — unchanged.

---

## 3. Runtime shape and reaction semantics

### Runtime model

`AppModel model` grows from `(model, Registry)` to include reaction bookkeeping:

```elm
type alias AppModel model =
    ( model
    , Registry
    , ReactionState
    )

type alias ReactionState =
    { triggers : Dict Int Encode.Value
    , seqs : Dict Int Int
    }
```

Reaction index = position in the list produced by `AppDef.reactions model computed` on the current cycle. The list's length and order are expected to be stable across cycles in Layer 2. If the length shrinks, orphan entries in `triggers` / `seqs` are dropped at the top of the next cycle.

### Reaction internal shape (private)

```elm
-- Rad.Internal.Reaction
type Reaction model
    = Reaction
        { readTrigger   : Registry -> Encode.Value
        , buildRequest  : Registry -> InternalRequest
        , writeLoading  : Registry -> Registry
        , writeSuccess  : Encode.Value -> Registry -> Registry
        , writeFailure  : Encode.Value -> Registry -> Registry
        }

type InternalRequest
    = DispatchTask (Task Encode.Value Encode.Value)
    | SkipRequest
```

`on` closes over the trigger source's codec, the target cell's codec (a `Codec (Remote err r)` built via `remoteCodec`), and the user's `transform` function. Type-erasure to `Encode.Value` at the boundary lets the runtime store reactions in a homogeneous list.

`remoteCodec` is implemented so the runtime can get at the component codecs (for `err` and `a`) — likely as a record bundling the components alongside the combined encode/decode. Resolved in Slice 1.

### Reaction firing lifecycle

After each `update` cycle, with the user's action already applied to the registry:

1. Rebuild the reaction list from `AppDef.reactions`.
2. For each reaction at index `i`:
   - `newTrigger = reaction.readTrigger currentRegistry`
   - If `Dict.get i triggers == Just newTrigger`, skip.
   - Otherwise: set `triggers[i] = newTrigger`; `seqs[i] = seqs[i] + 1`; capture `newSeq = seqs[i]`.
   - Build the request: `reaction.buildRequest currentRegistry`.
     - `SkipRequest` → nothing more (target stays as-is).
     - `DispatchTask task` → apply `writeLoading` to the registry; emit `Cmd` via `Task.attempt (ReactionResult i newSeq) task`.
3. Emit accumulated `Cmd`s.

On `ReactionResult i receivedSeq result`:
- If `seqs[i] /= receivedSeq` → stale, discard.
- Otherwise apply `writeSuccess` / `writeFailure` to the registry.
- Do **not** re-check triggers after writing the result (prevents the immediate feedback loop).

### `Msg model` new variants (in `Rad.Engine`)

```elm
type Msg model
    = ApplyAction (Action model)
    | ReactionResult Int Int (Result Encode.Value Encode.Value)
```

Engines still only produce `ApplyAction` via `fromAction`. `ReactionResult` is runtime-only.

### Semantics of `on`

```elm
on : Source a -> (a -> Request err r) -> Cell (Remote err r) -> Reaction model
```

- **First cycle on fresh init:** `triggers` is empty, every reaction fires once with its initial trigger value. Target cells start at whatever initial value the user gave (typically `Idle`); they immediately transition to `Loading`. Users who want "fire only on change" can inspect the trigger in `transform` and return `noRequest` for the initial value.
- **Subsequent cycles:** fire only when `newTrigger ≠ oldTrigger` by JSON equality.
- **Latest-wins:** stale results never written.
- **Error path:** `writeFailure` sets the target to `Failed err`; the view renders via pattern match on `Remote`.

---

## 4. Examples and Vite middleware

### Four new example apps

Each is a standalone Vite entry (html + Elm module), mirroring the Layer 0-1 structure.

**1. `fetch-joke`** — simplest end-to-end reaction.

- Model: `{ tick : Cell Int, joke : Cell (Remote RequestError Joke) }` (using `Rad.Http.RequestError` directly).
- Button click: `modify tick (\n -> n + 1)`.
- Reaction: `on (toSource tick) (\_ -> Rad.Http.httpGet handler "/api/joke" jokeDecoder) joke`.
- View: button plus `watch (toSource joke)` pattern-matching Remote states.
- Demonstrates: `Remote`, `remoteCodec`, `on`, `httpGet`, `AppDef.reactions`.

**2. `github-user`** — input + button, latest-wins observable by eye.

- Model: `{ input : Cell String, query : Cell String, user : Cell (Remote RequestError User) }`.
- "Fetch" button: `copy (toSource input) query`.
- Reaction: `on (toSource query) (\name -> Rad.Http.httpGet handler ("/api/github/users/" ++ name) userDecoder) user`.
- With the ~2s mock delay, rapid clicks show only the last result landing — visually clear.

**3. `post-note`** — `httpPost` plus custom error type via `mapRequestError`.

- Model: `{ draft : Cell String, submitTrigger : Cell String, note : Cell (Remote NoteError SavedNote) }`.
- Custom error: `type NoteError = NetworkFailure | ValidationFailure String`.
- Save button: `copy (toSource draft) submitTrigger`.
- Reaction: `on (toSource submitTrigger) (\text -> Rad.Http.httpPost handler "/api/note" (encodeNote text) noteDecoder |> mapRequestError toNoteError) note`.
- Demonstrates: `httpPost`, user-chosen error type, `remoteCodec` with a user-defined error codec.

**4. `derived-search`** — Layer 1 composes with Layer 2.

- Model: `{ first : Cell String, last : Cell String, results : Cell (Remote RequestError (List Match)) }`.
- Computed: `{ query : Source String }` = `Read.map2 (\a b -> a ++ " " ++ b) (read (toSource first)) (read (toSource last)) |> derive stringCodec`.
- Reaction: `on computed.query (\q -> Rad.Http.httpGet handler ("/api/search?q=" ++ q) matchDecoder) results`.
- Demonstrates: derived source (with its codec) driving a reaction.

### Vite dev-server middleware

A single new file `examples/mock-api-plugin.js`, registered in `vite.config.js`:

```js
export function mockApi() {
  return {
    name: "mock-api",
    configureServer(server) {
      const delayed = (res, body, ms = 2000) => {
        setTimeout(() => {
          res.setHeader("Content-Type", "application/json");
          res.end(JSON.stringify(body));
        }, ms);
      };

      server.middlewares.use("/api/joke", (_req, res) =>
        delayed(res, { text: randomJoke() })
      );
      server.middlewares.use("/api/github/users/", (req, res) =>
        delayed(res, { login: req.url.split("/").pop(), bio: "mock bio" })
      );
      server.middlewares.use("/api/note", (req, res) => {
        if (req.method !== "POST") { res.statusCode = 405; res.end(); return; }
        let body = ""; req.on("data", c => body += c);
        req.on("end", () => delayed(res, { id: 1, echoed: JSON.parse(body) }));
      });
      server.middlewares.use("/api/search", (req, res) =>
        delayed(res, { matches: ["alpha", "beta", "gamma"] })
      );
    },
  };
}
```

Endpoints exist only during `npm run dev`. Production builds (`npm run build`) omit them, which is fine — the examples are illustrative, not production-deployable.

### In-examples `TestRunner.elm`

A scrappy, deliberately rough demonstration of the mock-handler pattern:

```elm
module TestRunner exposing (main)

main : Program () () Never
main = Platform.worker { ... }  -- steps fetch-joke, Debug.logs registry snapshots

mockHandler : Rad.Http.Handler
mockHandler =
    { httpGet  = \_url -> Task.succeed "{\"text\":\"mock joke\"}"
    , httpPost = \_url _body -> Task.succeed "{}"
    }
```

Intentionally unpolished: no assertions, no CI wiring, output via `Debug.log`. Demonstrates the pattern so a future proper `Rad.Test` harness has a reference artifact.

---

## 5. Directory layout after Layer 2

```
elm-rad/
  elm.json                         ← package (now depends on elm/http via Rad.Http)
  src/
    Rad.elm
    Rad/
      View.elm
      Read.elm
      Engine.elm
      Http.elm                     ← new
      Internal/
        Action.elm
        Registry.elm
        Source.elm                 ← Source grows a codec field
        Reaction.elm               ← new
  tests/
    ActionTest.elm
    CellBuilderTest.elm
    CodecTest.elm
    ReadTest.elm
    RemoteCodecTest.elm            ← new
    SourceCodecTest.elm            ← new
    RequestTest.elm                ← new
    ReactionTriggerTest.elm        ← new
    LatestWinsTest.elm             ← new
  examples/
    elm.json
    package.json
    vite.config.js                 ← registers mock-api plugin
    mock-api-plugin.js             ← new
    index.html                     ← landing page grows four links
    greeting-html.html
    greeting.html
    counter.html
    swap.html
    full-name.html
    temperature.html
    fetch-joke.html                ← new
    github-user.html               ← new
    post-note.html                 ← new
    derived-search.html            ← new
    src/
      GreetingHtml.elm
      Greeting.elm
      Counter.elm
      Swap.elm
      FullName.elm                 ← updated: derive stringCodec
      Temperature.elm              ← updated: derive stringCodec
      SimpleView.elm
      FetchJoke.elm                ← new
      GithubUser.elm               ← new
      PostNote.elm                 ← new
      DerivedSearch.elm            ← new
      TestRunner.elm               ← new, scrappy harness
    README.md
  docs/
    design-elm-rad.md
    plans/
      2026-04-17-elm-rad-layers-0-1-design.md
      2026-04-17-elm-rad-layers-0-1-plan.md
      2026-04-19-elm-rad-layer-2-design.md   ← this document
```

---

## 6. Forward-compat shaping

Decisions in Layer 2 so Layers 3–8 land without rework.

- **`Source a` carries `Codec a`** — serves trigger comparison in Layer 2 and persistence/debug-output in Layer 7. Paid once, reused.
- **`Request err a` is opaque, carrying a `Task err a`** — future effect libraries (WebSocket in Layer 8+, timers for Debounce in Layer 3) construct their own `Request` values without coordinating with core. Core owns the type; extension authors own the constructors.
- **`Handler` lives in effect-library modules, not core** — Layer 3's Debounce timers will not route through `Rad.Http.Handler`; they'll be their own thing or use `Browser` subscriptions directly. No conflict with HTTP.
- **Reaction list rebuilt every cycle** — allows Layer 6 (`include : ComponentDef -> cells -> List (Reaction model)`) to prepend component reactions with no special runtime handling.
- **`Msg model` stays opaque with only `fromAction` as the public constructor** — the `ReactionResult` variant added in Layer 2 is an internal-only pattern; Debounce timer ticks, validation async results, and persistence save-complete events all follow the same shape in later layers without breaking engines.
- **Reaction identity is list-index for now.** Layer 7 crash recovery needs to re-fire reactions whose target is `Loading`, which requires inspecting cell state at restore, not comparing triggers. Layer 2 does not persist triggers. When Layer 7 lands: persist `triggers` alongside the registry, add restore-path logic that fires reactions whose target is `Loading` regardless of trigger change. The Layer 2 "first cycle fires all" policy refines into "fresh init fires all; restore fires only Loading targets." The public API is unaffected.
- **`AppDef.reactions` returns `List (Reaction model)`** — a plain list. Layer 6's `include` concatenates; Layer 5's form-scoped reactions prepend. All additive.
- **`ReactionState` is an internal tuple slot** — can grow fields (`pendingTimers`, `validationSeqs`) in later layers without changing the public `AppModel` alias, which stays opaque.

---

## 7. Testing strategy

**Division of labor:** pure `elm-test` for pure parts; browser + mock-server for end-to-end; scrappy `TestRunner.elm` as a bridge pattern.

### `elm-test` suites (Layer 2 additions)

| Suite | Covers |
|---|---|
| `RemoteCodecTest` | Round-trip all four variants (`Idle`, `Loading`, `Failed e`, `Done v`) with `remoteCodec stringCodec stringCodec`. Nested `remoteCodec remoteCodec ...` for sanity. |
| `SourceCodecTest` | `toSource` produces a source whose codec matches the cell's codec. `derive codec read` wires the codec through. |
| `RequestTest` | `noRequest` dispatches `SkipRequest` internally. `mapRequestError` composes: `mapRequestError f . mapRequestError g ≡ mapRequestError (f . g)`. |
| `ReactionTriggerTest` | Given a fresh `ReactionState` and a sequence of registries, the set of reactions that fire matches expectations: first cycle fires all, subsequent cycles fire only those whose encoded trigger changed. Edge case: JSON encoding determinism. |
| `LatestWinsTest` | Given two dispatches with seq `n` and `n+1`, a result tagged `n` arriving second must be ignored; tagged `n+1` must be written. |

No browser, no HTTP, no Tasks — all suites operate on pure data structures and synthetic `Msg`s.

### Browser verification (per-slice done criteria)

Each Layer 2 example app must:
- Render `Idle` on first load.
- Transition to `Loading` on trigger.
- Transition to `Done v` or `Failed e` after the ~2s mock delay.
- For `github-user`: rapid clicks → only last result visible.
- For `post-note`: error mapping visible (custom error variants rendered).
- For `derived-search`: editing either input changes the query → triggers a new fetch.

### Scrappy `TestRunner.elm`

Counts as demonstration, not verification. `npm run test-runner` in `examples/` compiles and runs a `Platform.worker` that `Debug.log`s step output. Acceptance: one pass prints the expected sequence of registry snapshots. Left in-repo as the future-harness reference.

### Deliberately not tested yet

- Reaction list length changes across cycles (orphan cleanup) — edge case, verified manually.
- Concurrent reactions dispatching in one cycle — works by construction, not asserted.
- The Vite middleware — if it breaks, examples don't render, which is the real signal.

**Future extension (noted, not in scope):** a proper public `Rad.Test` module. Deferred until Layer 2 has settled and we know what testing surface consumers actually want.

---

## 8. Risks and open questions

Unknowns the implementation plan will resolve during Slice 1–2.

1. **JSON equality semantics for trigger comparison.** Elm's `Json.Encode.encode 0 v1 == Json.Encode.encode 0 v2` works for primitives, lists, and records with deterministic field ordering (Elm's `Encode.object` preserves declaration order). Flag a test case asserting round-trip equality is stable across cycles. If we hit a case where two semantically-equal triggers encode differently, revisit (possible fix: canonicalize before compare).

2. **Self-writing reactions and feedback loops.** A reaction writing its own target cell could in theory loop if that target is also a trigger source. Layer 2 prevents the immediate case by not re-checking triggers after writing results. Pathological multi-reaction cycles remain possible and are **a consumer responsibility** — not something the library defends against in Layer 2. Documented as a known limitation for future consideration.

3. **`remoteCodec` internal structure.** The runtime needs to construct `Loading` and `Failed e` values and encode them — meaning it needs the component codecs (for `err` and `a`), not just the combined `Codec (Remote err a)`. Options: (a) store `remoteCodec`'s result as an opaque record internally bundling the components; (b) expose a private helper in `Rad.Internal` that accesses them. Resolved in Slice 1.

4. **Reaction list stability across cycles.** Expected to be structurally stable. If `AppDef.reactions` ever returns a shorter list, orphan `triggers` / `seqs` entries are stale. Layer 2 cleans them at the top of each cycle (size check, drop extras). Length growing fires the new reactions on that cycle normally.

5. **Breaking change coordination.** `derive` gains a `Codec a` argument; `AppDef` gains a `reactions` field. Both touch existing Layer 0-1 examples. Plan: migrate all Layer 0-1 examples in the same commit that lands the breaking change, so the tree compiles at every commit.

6. **Handler plumbing ergonomics.** Users write `myApp : Handler -> AppDef ...` then `run htmlEngine (myApp prodHandler)`. Acceptable for Layer 2. If it becomes a friction point, Layer 7+ could add a convenience wrapper — no action for now.

7. **Task cancellation is not real in Elm.** Latest-wins via seq numbers means stale results are ignored, but the Task continues running and its HTTP request completes on the wire. Acceptable for Layer 2; noted as an efficiency consideration, not correctness.

8. **`TestRunner.elm` output format.** `Platform.worker` + `Debug.log` is the minimum viable harness. If output gets too noisy, we may switch to structured stdout via a port — deferred unless it hurts.

---

## 9. Six vertical slices

Each slice ends with green `elm make`, green `elm-test` (where applicable), and a visible checkpoint. Within each slice, commits stay small and atomic.

### Slice 1 — `Remote` + Source/derive codec migration

Package:
- Add `Remote err a` and `remoteCodec : Codec err -> Codec a -> Codec (Remote err a)` in `Rad`.
- Change `Rad.Internal.Source` so `Source a` carries a `codec : Codec a` field.
- Update `toSource` (pulls codec from cell) and `derive` (takes codec as first arg).

Examples:
- `FullName.elm` and `Temperature.elm` add `stringCodec` to their `derive` calls.

Tests: `RemoteCodecTest`, `SourceCodecTest`.

Checkpoint: all existing examples still build and run.

### Slice 2 — `Request` + `Rad.Http` module

Package:
- `Request err a` opaque in `Rad`, with `noRequest`, `mapRequestError`.
- New `Rad.Http` module: `Handler`, `prodHandler`, `httpGet`, `httpPost`, `RequestError`, `requestErrorCodec`.
- Add `elm/http` to package dependencies; add `Rad.Http` to exposed-modules.

Examples: no changes yet.

Tests: `RequestTest`.

Checkpoint: `Rad.Http.httpGet prodHandler "/api/joke" jokeDecoder` type-checks in a scratch module.

### Slice 3 — Vite mock middleware

Examples:
- `examples/mock-api-plugin.js` with all four endpoints and ~2s delay.
- `vite.config.js` wires the plugin.

Checkpoint: `curl localhost:5173/api/joke` returns a JSON joke after ~2s. All four endpoints verified manually.

### Slice 4 — Reaction runtime + `fetch-joke` ships *(biggest slice)*

Package:
- New `Rad.Internal.Reaction`.
- `on` in `Rad`.
- `AppDef.reactions : model -> computed -> List (Reaction model)` field.
- Runtime updates: `AppModel` gains `ReactionState`; `Rad.Engine.Msg` gains `ReactionResult` variant; `run` dispatches reactions per Section 3.
- Existing Layer 0-1 examples get `reactions = \_ _ -> []` in the same commit.

Examples:
- `examples/fetch-joke.html` + `examples/src/FetchJoke.elm` — button-driven one-shot fetch.

Tests: `ReactionTriggerTest`, `LatestWinsTest`.

Checkpoint: `fetch-joke` renders Idle → Loading → Done/Failed in browser, driven by the Vite mock.

### Slice 5 — `github-user` + `post-note` ship

Package: no changes.

Examples:
- `examples/github-user.html` + `examples/src/GithubUser.elm`.
- `examples/post-note.html` + `examples/src/PostNote.elm`.

Checkpoint: both render correctly; rapid clicks on `github-user` show only last result; `post-note` displays custom error variants.

### Slice 6 — `derived-search` + `TestRunner.elm` ship

Examples:
- `examples/derived-search.html` + `examples/src/DerivedSearch.elm`.
- `examples/src/TestRunner.elm` — scrappy `Platform.worker` harness exercising `FetchJoke` with a mock handler.

Checkpoint: `derived-search` fetches on any input change; `TestRunner` prints expected registry snapshots via `Debug.log`.

---

## 10. Success criteria

Layer 2 is complete when:

- `Rad`, `Rad.View`, `Rad.Read`, `Rad.Engine`, `Rad.Http` all compile cleanly via `elm make --docs`.
- Every `elm-test` suite in Section 7 passes.
- All six Layer 0-1 example apps still render and behave correctly.
- All four new Layer 2 example apps render and behave correctly against the Vite mock server.
- `TestRunner.elm` compiles and runs a complete mock-driven cycle.
- `npm run build` in `examples/` produces a multi-entry production build for all ten apps (six Layer 0-1 + four Layer 2) plus the landing page.
- Commit history is granular: one coherent change per commit, ordered such that each commit individually compiles and passes whatever tests exist at that point.
