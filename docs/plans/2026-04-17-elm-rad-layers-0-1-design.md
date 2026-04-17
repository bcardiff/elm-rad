# elm-rad — Layers 0 & 1 Implementation Design

**Date:** 2026-04-17
**Scope:** First incremental pass of the DSL defined in [`docs/design-elm-rad.md`](../design-elm-rad.md).
**Strategy:** Example-driven vertical slices. Sync-only. API shapes must stay forward-compatible with Layers 2–8.

---

## 1. Scope & non-goals

**In scope:**
- **Layer 0 — Foundation:** `Cell`, `Source`, `CellBuilder`, sync actions (`set`, `modify`, `copy`, `batch`), `bind` / `onClick` / `watch`, `ViewEngine` type, shipped `htmlEngine`, `run`, `AppDef`.
- **Layer 1 — Reactivity:** `Read` monad (`Read.map`, `Read.map2`), `read`, `derive`, computed record threaded through `AppDef`.
- Six example apps covering every Layer 0 and Layer 1 primitive.
- An in-examples `SimpleView` engine that proves the `ViewEngine` abstraction is real.
- `elm-test` harness and behavioural tests for every new primitive.

**Out of scope:**
- Reactions, async, `Handler`, `Request`, `Remote` (Layer 2).
- `DebouncedCell` (Layer 3), `ValidatedCell` (Layer 4), `Form` (Layer 5).
- `ComponentDef` / `embed` / `include` / `withInstance` (Layer 6).
- Persistence, codec-driven save/restore, migrations, crash recovery (Layer 7).
- SVG and Canvas engines, cross-engine mounting (Layer 8).
- A built-in testing harness for *consumer* apps (deferred to pair with Layer 2's `Handler`).

**Sync-only constraint:** no timers, HTTP, localStorage, or subscriptions beyond what Elm's `Browser.sandbox` offers natively.

---

## 2. The `SimpleView` engine — rationale

The package ships `htmlEngine` in `Rad.View`. Examples additionally define a second engine, `SimpleView`, in `examples/src/SimpleView.elm`. This is **deliberately not shipped** with the package.

### Primitives (examples-local)

```elm
type SimpleView model   -- opaque

col    : List (SimpleView model) -> SimpleView model
input  : { label : String, cell : Cell String } -> SimpleView model
button : { label : String, onClick : Action model } -> SimpleView model
text   : String -> SimpleView model

simpleViewEngine : ViewEngine (SimpleView model) model
```

`simpleViewEngine.toHtml` renders `col` as stacked `<div>`, `input` as `<label>…<input></label>` with the cell's value and input handler wired through the runtime, `button` with an `onClick` that dispatches the action, `text` as plain text. No styling, no attributes, no HTML pass-through.

Reactive text is expressed with the runtime's generic `watch`:

```elm
col
    [ input { label = "Name", cell = model.name }
    , watch (toSource model.name) (\n -> text ("Hello " ++ n))
    ]
```

### Why it lives in examples, not the package

1. **It proves `ViewEngine` pluggability is real from day one.** Two working engines on the same runtime is a much stronger claim than the abstraction existing "in theory". Layers 3–8 (and later SVG/Canvas engines) inherit that proof instead of having to re-earn it.
2. **It proves the abstraction survives a radically different primitive shape.** `SimpleView.input` takes `Cell String` directly; `SimpleView.button` takes `Action model` directly — no `Attribute`s list. If the runtime accommodates that as cleanly as HTML's attr-based model, the engine contract is genuinely generic, not a thin skin over `elm/html`.
3. **It keeps example code short and readable**, so readers focus on cells, actions, and computed values rather than HTML plumbing.
4. **Shipping it would invite scope creep** ("add padding", "add row", "add onFocus") — at which point it stops being a demonstration and becomes a second UI library to maintain. As an example artifact it can stay tiny and opinionated forever.
5. **It mirrors how real consumers might build a domain-specific engine.** A charting-focused or form-focused engine would live in the app's codebase. `SimpleView` shows the shape of that pattern.

---

## 3. Module layout

| Module | Audience | Contents |
|---|---|---|
| `Rad` | App authors | Core types (`Cell`, `Source`, `Codec`, `Action`, `CellBuilder`, `AppDef`); actions (`set`, `modify`, `copy`, `batch`); `watch`; basic codecs (`stringCodec`, `intCodec`, `floatCodec`, `boolCodec`, `listCodec`, `maybeCodec`); `build`, `with`, `toSource`; `run`. |
| `Rad.View` | App authors | `htmlEngine`, HTML view primitives (`col`, `input`, `button`, `text`), `Attribute model`, `bind`, `onClick`. |
| `Rad.Read` | App authors | `Read a`, `read`, `Read.map`, `Read.map2`, `derive`. |
| `Rad.Engine` | Engine authors only | `ViewEngine`, `Msg model` (opaque), `fromAction : Action model -> Msg model`. |

App authors never import `Rad.Engine`. Engine authors (SimpleView, future SVG/Canvas) never need `Rad.View`.

---

## 4. Six vertical slices

Each slice ends with a visible working app plus `elm-test`s for any new primitive. Commits are frequent and atomic within each slice.

### Slice 1 — Runtime skeleton + `greeting-html` ships *(biggest slice)*

Package additions:
- Types: `Cell a`, `Source a`, `Codec a`, `CellBuilder ctor`, `Action model`, `Attribute model`, `AppDef view model computed`.
- `Rad`: `build`, `with`, `toSource`, `set`, basic codecs, `run`, `watch`.
- `Rad.View`: `htmlEngine`, HTML primitives `col`, `input`, `text`, `bind`.
- `Rad.Engine`: `ViewEngine`, `Msg`, `fromAction`.
- `tests/` directory with `elm-explorations/test` wired. Tests: `CellBuilder` assigns unique IDs; cells capture their persistence key and codec; `set` updates the right cell; `toSource` round-trips; codec encode/decode pairs round-trip.

Examples restructure:
- Convert `examples/` from single-entry Vite app to multi-entry.
- Add landing page `examples/index.html` with links to each example.
- First app: `examples/greeting-html.html` + `examples/src/GreetingHtml.elm`.

### Slice 2 — `SimpleView` engine + `greeting` ships

Package changes: none.

Examples:
- `examples/src/SimpleView.elm` (type + primitives + `simpleViewEngine`).
- `examples/greeting.html` + `examples/src/Greeting.elm` using `simpleViewEngine`.

Proves the `ViewEngine` abstraction survives a structurally-different primitive shape.

### Slice 3 — `counter` ships

Package additions: `modify` action; `onClick : Action model -> Attribute model`; HTML `button` primitive. Tests for `modify`.

Examples: SimpleView gains `button`; `examples/counter.html` + `examples/src/Counter.elm` (inc / dec / reset on a `Cell Int`).

### Slice 4 — `swap` ships

Package additions: `copy`, `batch` actions. Tests: `copy` reads source *then* writes target; `batch` applies actions in declaration order; empty `batch` is a no-op; nested `batch` flattens.

Examples: `examples/swap.html` + `examples/src/Swap.elm` (two `Cell String` inputs + swap button via `batch` + intermediate cell).

### Slice 5 — `full-name` ships *(Layer 1 begins)*

Package additions: `Rad.Read` module (`Read a`, `read`, `Read.map`, `Read.map2`, `derive`); `AppDef.computed` invoked and its record threaded to `view`. Tests: `Read.map` and `Read.map2` produce correct values after each dependency change; `derive` yields a `Source` whose read matches the mapped value.

Examples: `examples/full-name.html` + `examples/src/FullName.elm` (first + last inputs → `Read.map2` → derived full name).

### Slice 6 — `temperature` ships

Package changes: none (verification example only).

Examples: `examples/temperature.html` + `examples/src/Temperature.elm` (one °C input, two derived displays via chained `Read.map`: °F and K).

---

## 5. Directory layout after Slice 6

```
elm-rad/
  elm.json                         ← package
  src/
    Rad.elm
    Rad/
      View.elm
      Read.elm
      Engine.elm
      Internal/                    ← private, not exposed
        …
  tests/
    …                              ← elm-test suites
  examples/
    elm.json                       ← source-directories: ["src", "../src"]
    package.json
    vite.config.js
    index.html                     ← landing page with links
    greeting-html.html
    greeting.html
    counter.html
    swap.html
    full-name.html
    temperature.html
    src/
      GreetingHtml.elm
      Greeting.elm
      Counter.elm
      Swap.elm
      FullName.elm
      Temperature.elm
      SimpleView.elm
    README.md
  docs/
    design-elm-rad.md              ← the DSL spec (existing)
    plans/
      2026-04-17-elm-rad-layers-0-1-design.md   ← this document
```

Each `*.html` contains an inline `<script type="module">` that imports its Elm module and calls `Elm.<ModuleName>.init({ node: … })`.

---

## 6. Forward-compat shaping

Decisions we make in Layer 0+1 specifically so Layers 2–8 can land without rewriting earlier slices.

- **`Codec` threaded through `with` from Slice 1**, even though nothing reads codecs until Layer 7 (persistence). Avoids rewriting every call site later.
- **`Action model` and `Attribute model` parameterized over `model`** from day one. Layer 0 primitives don't use the parameter, but `batch : List (Action model) -> Action model` and later reaction-driven actions do.
- **`Source a` kept distinct from `Cell a`.** Layer 0 could collapse them, but `DebouncedCell`, `ValidatedCell`, and `derive` all produce `Source` values without a backing `Cell`.
- **`AppDef` is a record that will grow.** `reactions` at Layer 2, `persist` at Layer 7. Existing field *types* stay stable; consumers add new fields as they adopt later layers.
- **`Msg model` is opaque.** Engine authors construct via `fromAction` only. Internal variants (reaction ticks, HTTP responses, timer fires) can be added without breaking engines.
- **`run` may gain a `Handler` parameter at Layer 2** — a pre-registered breaking change, acceptable pre-1.0.

---

## 7. Testing strategy

**Harness:** `elm-test` at the package root, with `elm-explorations/test` in `test-dependencies`. Lands in Slice 1.

**Division of labor:**
- `elm-test` covers pure behaviour: action semantics, `CellBuilder` output, `Read` composition, codec round-trips. No rendering, no DOM.
- **Examples** cover end-to-end behaviour: rendering, event dispatch, multiple engines. Manual/visual verification in a browser.
- **Slice definition of done:** new primitives have `elm-test`s *and* the slice's example runs correctly in the browser.

**Tests per slice:**

| Slice | Tests |
|---|---|
| 1 | `CellBuilder` assigns unique IDs; cells capture their persistence key and codec; `set` updates the right cell; `toSource` round-trips; codec encode/decode pairs round-trip; `run` type-checks (compilation smoke). |
| 2 | None (examples-only slice). |
| 3 | `modify` applies its function; `onClick` attribute wraps an action. |
| 4 | `copy` reads source *before* writing target; `batch` applies actions in declaration order; empty `batch` is a no-op; nested `batch` flattens. |
| 5 | `Read.map` and `Read.map2` produce correct values after each dep change; `derive` yields a `Source` whose read matches the mapped value; recomputation happens on each render cycle. |
| 6 | None (verification example only). |

**Deliberately not tested yet:**
- Internal dep-graph structure. Layer 0+1 uses naive "recompute on every render"; behavioural tests pass without asserting the `Set CellId` a `Read` accumulates. Dep tracking becomes test-worthy at Layer 2 when reactions depend on it.
- Anything that requires a browser (view rendering, event wiring).

**Future extension (noted, not in scope):** a testing mini-framework for *consumer* apps that pairs with Layer 2's `Handler` — swap a mock handler for deterministic tests of entire `AppDef`s. Deferred until `Handler` exists.

---

## 8. Risks & open questions

Shape-level unknowns that Slice 1 will resolve during the writing-plans phase.

1. **Cell storage representation.** Two viable shapes:
   - **(a)** Cells are opaque references (ID + codec); values live in the user's `Model` record. `Action`s are `model -> model` functions plus metadata. No JSON in the hot path.
   - **(b)** Cells hold `Json.Value` internally; codecs convert on read/write. Simpler runtime, JSON overhead on every access.

   Default is **(a)** — cleaner Elm, zero serialization cost, persistence in Layer 7 serializes at save-time only. Flagged because it shapes the entire runtime.

2. **Engine dispatch plumbing.** Resolved in Section 3: `Rad.Engine` exposes opaque `Msg model` plus `fromAction`. Engines produce `Html (Msg model)`. Concrete shape to finalize in Slice 1.

3. **`CellBuilder` plumbing.** The applicative builder threads an ID counter and collects (key, codec, initial) triples. Output is both the user's `Model` record *and* the runtime's cell registry. Implementation shape to nail down in Slice 1.

4. **Hot reload state preservation.** `vite-plugin-elm` re-initializes the Elm program with prior state via flags. Assumed to work; verify during Slice 1. If it does, no README caveat needed. If not, revisit.

5. **Landing page is static HTML.** No Elm required; just a `<ul>` of links. Keeps adding new examples trivial in later slices (copy HTML template, add to Vite input list).

---

## 9. Success criteria

The implementation is complete when:

- The package (`Rad`, `Rad.View`, `Rad.Read`, `Rad.Engine`) compiles cleanly via `elm make --docs`.
- `elm-test` passes for every suite listed in Section 7.
- All six example apps render and behave correctly in a browser via `npm run dev` in `examples/`.
- `npm run build` in `examples/` produces a multi-entry production build for all six apps plus the landing page.
- Commit history is granular: one coherent change per commit, ordered such that each commit individually compiles and passes whatever tests exist at that point.
