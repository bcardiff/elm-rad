# elm-rad Layer 3 Design — Debounced Cells

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Prerequisite:** Layers 0–2 shipped (cells, reactions, remote/request, `Rad.Http`).

---

## 1. Scope

Layer 3 adds debounced cells: a single logical "field" with two observable values — the *raw* value updated on every keystroke, and the *settled* value committed on configurable triggers (Enter, Blur, Timeout) or by explicit Action.

**In scope:**
- `DebouncedCell a` opaque type.
- Builder entry: `withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest`.
- Three source accessors: `raw`, `settled`, `synced : DebouncedCell a -> Source Bool`.
- Two pure actions: `commit`, `revert`.
- `type CommitTrigger = OnEnter | OnBlur | OnTimeout` in `Rad.View`.
- Bindings: `bindDebounced` (all triggers default) and `bindDebouncedWith` (subset).
- New `Msg` variants `DebouncedInput` / `DebouncedTimerFire` and public helper `fromDebouncedInput : DebouncedCell a -> a -> Msg model` in `Rad.Engine` for view engines.
- `Process.sleep`-based timer scheduling, latest-wins via per-cell `timerSeq`.
- Three example apps: `debounce-echo`, `search-debounced`, `custom-triggers`.
- `elm-test` suites for construction, semantics, synced, latest-wins.
- `SimpleView` gains a parallel `debouncedInput` primitive.

**Out of scope:**
- Layers 4–7.
- Non-String bindings. Cells are polymorphic and usable via explicit `set` / `commit` / `revert`, but only `String` has a `Rad.View` binding in this layer.

---

## 2. Module layout after Layer 3

**`Rad`** (public, re-exports) gains:
- `DebouncedCell`, `withDebounced`, `raw`, `settled`, `synced`, `commit`, `revert`.

**`Rad.View`** gains:
- `type CommitTrigger = OnEnter | OnBlur | OnTimeout`.
- `bindDebounced : DebouncedCell String -> ViewBinding model` (all three triggers).
- `bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> ViewBinding model`.

**`Rad.Engine`** (public) gains:
- Two new `Msg model` variants: `DebouncedInput` and `DebouncedTimerFire` (opaque via existing `Msg` opacity).
- `fromDebouncedInput : DebouncedCell a -> a -> Msg model` — public constructor for view engines to dispatch raw input.

**`Rad.Internal.Debounced`** (new, private) owns:
- `DebouncedCell` record internals (two cell IDs: raw, settled; codec; delayMs; `timerSeq` counter key).
- Timer-fire handler: checks current timer seq vs the fire's seq; no-op if superseded; otherwise copies raw→settled.
- No `elm/http`; uses `Process.sleep` + `Task.perform`.

**`SimpleView`** (examples, parallel primitive):
- `debouncedInput : { label : String, cell : DebouncedCell String, triggers : List CommitTrigger } -> SimpleView model`.

No changes to `Rad.Read`, `Rad.Http`, or `Rad.Internal.{Action,Source,Reaction,Registry,Request}`.

---

## 3. Runtime shape and timer semantics

**Registry additions.** `DebouncedCell a` holds two cell IDs (raw, settled) plus a `timerSeq` counter stored in the Registry under a dedicated key. Each raw-write bumps `timerSeq` and schedules a `Process.sleep delayMs` Task that resolves with that seq number.

**Msg dispatch.** In `update`:
- `DebouncedInput cellRef newValue` → write `newValue` to raw cell, increment the cell's `timerSeq`, schedule `Process.sleep` producing `DebouncedTimerFire cellRef seq`, then run the normal reaction-fire pass (reactions on `raw` see the change immediately).
- `DebouncedTimerFire cellRef seq` → if `seq < currentTimerSeq` for that cell, no-op. Otherwise copy raw→settled via the cell's codec and run the reaction-fire pass (reactions on `settled` see the change).

**Commit and revert as plain Actions.**
- `commit cell` = pure `Registry → Registry` that copies raw→settled.
- `revert cell` = pure `Registry → Registry` that copies settled→raw.
- Neither touches `timerSeq`. If a pending timer fires after commit/revert, raw and settled already match, so the copy is a no-op. If the user typed again after commit/revert, that input bumped the seq, making any earlier pending fire stale.

**Synced source.** `synced cell` is a `Source Bool` derived via `Read.map2 (==)` over raw and settled using the cell's codec for equality (JSON-encoded comparison, consistent with Layer 2 reaction change detection).

**Reaction interaction.** Reactions fire on every registry change, so reactions reading `raw` fire on every keystroke; reactions reading `settled` fire only on commit/timeout/revert. Latest-wins (Layer 2) continues to apply orthogonally.

**Infinite-loop stance.** Unchanged from Layer 2 — consumer responsibility. Debounce does not itself write back to raw, so no new loop surface is introduced.

---

## 4. Examples and Vite middleware additions

**Example 1: `debounce-echo`** — Minimal semantics showcase.
- One `DebouncedCell String` with 800ms delay.
- SimpleView shows: debounced input (all triggers), live `raw` value, live `settled` value, live `synced` indicator ("✓ synced" / "… pending"), manual **Commit** and **Revert** buttons.
- No reactions, no HTTP. Pure demonstration of the four observable sources (raw/settled/synced + commit/revert actions).

**Example 2: `search-debounced`** — Layer 2 + Layer 3 composition.
- `DebouncedCell String` (500ms) for the query.
- `Remote RequestError (List String)` cell for search results.
- Reaction: trigger on `settled query`, fire `Rad.Http.httpGet` to `/api/search?q=...`, write result to the remote cell.
- SimpleView: debounced input, "searching…" indicator driven by `Remote.Loading`, results list.
- Confirms that reactions on `settled` debounce correctly (no request per keystroke; one request per commit/timeout).

**Example 3: `custom-triggers`** — Trigger-set per binding.
- Same `DebouncedCell String` rendered twice via two bindings:
  - Top input: `bindDebouncedWith [OnEnter]` (Enter-only commit).
  - Bottom input: `bindDebouncedWith [OnBlur, OnTimeout]` (blur + 1500ms timeout).
- Both inputs show the same live `settled` below.
- Demonstrates per-binding trigger customization against one shared cell.

**Vite middleware additions** (`examples/mock-api-plugin.js`):
- `GET /api/search?q=<string>` → ~2s delay → returns `{ results: ["foo", "foo bar", "foo baz"] }` (deterministic derivation from query for test predictability).

Entries added to `examples/vite.config.js` `rollupOptions.input`:
- `debounce-echo`, `search-debounced`, `custom-triggers`.

Corresponding `.html` files and Elm modules under `examples/src/`.

---

## 5. Testing strategy

**Pure elm-test suites** under `tests/`:

- **`DebouncedTest.elm`** — construction & accessors
  - `withDebounced` adds two cells to the builder and both appear in the initial Registry with their initial values.
  - `raw`, `settled` return `Source a` reading the correct cell.
  - `synced` returns `Source Bool` starting `True` when initial values match.

- **`DebouncedSemanticsTest.elm`** — state transitions driven by dispatching Msgs into a built `AppModel`
  - Dispatch `DebouncedInput cell "x"` → raw becomes `"x"`, settled unchanged, synced `False`.
  - Dispatch `DebouncedTimerFire cell seq` with stale `seq` → no change (superseded).
  - Dispatch `DebouncedTimerFire cell seq` with current `seq` → settled equals raw, synced `True`.
  - `commit cell` Action → settled equals raw, synced `True`; pending timer fire after commit is a no-op.
  - `revert cell` Action → raw equals settled, synced `True`; pending timer fire is a no-op.

- **`DebouncedLatestWinsTest.elm`** — interleaving
  - Write "a", schedule fire seq 1, write "b" (bumps to seq 2), fire seq 1 arrives → settled stays at initial. Then fire seq 2 → settled = "b".

**Scrappy `TestRunner` additions** (examples-side, introduced in Layer 2):
- Manual timing scenario for `search-debounced`: types query, waits delay, verifies one request observed via mocked handler.
- Trigger-customization scenario: dispatches `DebouncedInput` without timer fire, then `commit` via Enter-binding Action for Example 3.

**Out of scope for Layer 3 tests:**
- Real-clock timing assertions (flaky); we test by dispatching the timer-fire Msg directly.
- DOM-level keyboard/blur simulation (punted; view-binding code paths exercised manually in examples and via `fromDebouncedInput` helper in tests).

---

## 6. Forward-compat shaping

- **`DebouncedCell a` is opaque and parametric in `a`.** Only `String` bindings ship in Layer 3; the cell, its sources, and commit/revert are polymorphic and usable today over custom types via the codec and `fromDebouncedInput`.
- **`CommitTrigger` lives in `Rad.View`, not in the core.** The core runtime knows only `DebouncedInput` and `DebouncedTimerFire`. Alternative view engines with different trigger semantics can plug in without runtime changes.
- **Timer-seq counter is stored in the Registry keyed per-cell.** Uniform latest-wins mechanism consistent with Layer 2 reaction-seq.
- **`commit` / `revert` as plain `Action model`** compose with `Rad.Engine.batch` / future action combinators for free.
- **`fromDebouncedInput` is the only new public dispatch constructor.** View engines never construct timer-fire Msgs; timer scheduling stays internal and swappable.
- **No changes to `Rad.Read`, `Rad.Http`, reactions, or `Source` internals.** Layer 3 is purely additive on top of Layer 2.
- **SimpleView parallel primitive, not a rewrite.** `SimpleView.input` and `SimpleView.debouncedInput` coexist.

**Explicitly deferred:**
- `DebouncedCell` bindings for non-String types.
- Cancellable timers — unneeded given seq-based supersession.
- Observable "in-flight timer count" source — YAGNI; `synced` covers the stable-state question.

---

## 7. Risks and open questions

**Risks**

1. **`Process.sleep` timing on inactive tabs.** Browser throttles sleep timers when the tab is background. Settled updates after a longer-than-expected delay. Acceptable; documented. Consumers needing strict timing use explicit `commit` actions.
2. **Msg ordering under rapid input.** Stale `DebouncedTimerFire` messages are cheap (Dict lookup + `<` + no-op), but each still runs. Non-issue for keystroke rates; observable under burst programmatic writes. Profile if it ever matters.
3. **`synced` comparison cost.** JSON-encodes both cells on every read. Acceptable at Layer 3; a cache bit can be added later if large-value cells bite.
4. **Commit/revert with a pending fire.** `commit` copies raw→settled; stale fire is a no-op. `revert` copies settled→raw and does not bump `timerSeq`; a pending fire then copies the just-reverted raw to settled, which is a no-op. An invariant test in `DebouncedSemanticsTest` locks this in.

**Open questions (decisions recorded here)**

1. **Should `synced` be stored atomically rather than derived?** **No.** Derivation from `raw == settled` (codec JSON equality) is the source of truth. A stored flag would require every raw/settled write site to maintain it — drift risk for no observable win in any trace we considered.
2. **Should `DebouncedCell` expose `delayMs` as a `Source Float`?** Deferred (YAGNI). Backward-compatible to add later.
3. **Should `bindDebounced` default include `OnTimeout`?** Yes — matches common debounce expectation. `bindDebouncedWith []` is an explicit escape hatch for commit-only-via-Action.
4. **Reactions firing on `raw` fire per keystroke.** Intentional. Consumers who want "one request per stable value" key on `settled`. Documented.

---

## 8. Six vertical slices

Each slice ends with a passing build + committed code. Slices stack; no slice breaks the previous.

**Slice 1 — `DebouncedCell` type + `withDebounced` builder**
- `Rad.Internal.Debounced` module with opaque record (raw cellId, settled cellId, codec, delayMs).
- `Rad.withDebounced` extends `CellBuilder` with two cell allocations.
- `DebouncedTest.elm`: initial registry contains both cells at the initial value.
- No Msg wiring yet; no timer.

**Slice 2 — Source accessors + commit/revert Actions**
- `Rad.raw`, `Rad.settled`, `Rad.synced` (derived via `Read.map2` + codec JSON equality).
- `Rad.commit`, `Rad.revert` as pure `Action model`.
- `DebouncedSemanticsTest.elm`: commit and revert tests; synced flips correctly.
- Still no Msg variants — commit/revert dispatchable via existing Action plumbing.

**Slice 3 — Msg variants + `fromDebouncedInput` + timer scheduling**
- Add `DebouncedInput` and `DebouncedTimerFire` to `Rad.Engine.Msg`.
- `fromDebouncedInput` public constructor.
- `update` handles `DebouncedInput`: write raw, bump per-cell `timerSeq`, return `Cmd` from `Process.sleep delayMs |> Task.perform (\_ -> DebouncedTimerFire cellRef seq)`.
- `update` handles `DebouncedTimerFire`: seq check, raw→settled copy.
- `DebouncedLatestWinsTest.elm`: interleaved writes + stale fires yield latest value only.

**Slice 4 — `Rad.View.bindDebounced{,With}` + SimpleView primitive**
- `CommitTrigger` type in `Rad.View`.
- `bindDebounced` wires `onInput → fromDebouncedInput`, `onKeyDown Enter → commit`, `onBlur → commit`.
- `bindDebouncedWith` subsets triggers.
- `SimpleView.debouncedInput` in `examples/src/SimpleView.elm`.
- `debounce-echo` example + html entry + vite.config entry. Manual verification in browser.

**Slice 5 — `search-debounced` example (Layer 2 integration)**
- `GET /api/search?q=` mock endpoint in `examples/mock-api-plugin.js` (2s delay).
- `SearchDebounced.elm`: reaction keyed on `settled query` firing `Rad.Http.httpGet`.
- html entry + vite.config entry.
- Scrappy TestRunner: mocked handler sees exactly one request after debounce window.

**Slice 6 — `custom-triggers` example + docs sweep**
- `CustomTriggers.elm`: two bindings of one cell, `[OnEnter]` vs `[OnBlur, OnTimeout]`.
- html entry + vite.config entry.
- `@docs` comments on all new public symbols in `Rad`, `Rad.View`, `Rad.Engine`.
- Update `docs/design-elm-rad.md` Layer 3 section with the "derive over store" decision from Section 6.

Each slice gets its own commit (or small series). No slice touches `Rad.Read`, `Rad.Http`, or reaction internals.

---

## 9. Success criteria

Layer 3 is done when all of the following hold:

1. **API surface.** `Rad` exports `DebouncedCell`, `withDebounced`, `raw`, `settled`, `synced`, `commit`, `revert`. `Rad.View` exports `CommitTrigger`, `bindDebounced`, `bindDebouncedWith`. `Rad.Engine` exports the new `Msg` variants (opaque) and `fromDebouncedInput`.
2. **Build green.** `elm make` succeeds in both `src/` (package) and `examples/`. `npm run build` in `examples/` produces all 14 entries (11 existing + `debounce-echo`, `search-debounced`, `custom-triggers`).
3. **Tests green.** `elm-test` passes: `DebouncedTest`, `DebouncedSemanticsTest`, `DebouncedLatestWinsTest`, plus all existing Layer 0–2 suites untouched.
4. **Examples work in-browser.**
   - `debounce-echo`: typing updates `raw` immediately; `settled` updates after 800ms pause, Enter, or Blur; `synced` indicator accurate; Commit and Revert buttons behave.
   - `search-debounced`: one network request per settled query (verified in Network tab); loading state visible during 2s mock delay; results render.
   - `custom-triggers`: top input commits on Enter only; bottom input commits on Blur or after 1.5s; both share one `settled`.
5. **Zero regressions.** All 11 Layer 0–2 examples still build and run unchanged.
6. **Core stays effect-agnostic.** `src/Rad/Internal/Debounced.elm` uses only `Process`, `Task`, and existing Rad internals. No `elm/http`, no new package deps in `elm.json`.
7. **Design decisions locked in docs.** `docs/design-elm-rad.md` Layer 3 section records: two cells internally, seq-based supersession, commit/revert as pure Actions, `synced` derived not stored, per-binding trigger sets.
8. **Scrappy TestRunner scenarios.** Manual runner in examples exercises `search-debounced` (one-request-per-debounce) and `custom-triggers` (trigger-set per binding) and reports pass/fail.
