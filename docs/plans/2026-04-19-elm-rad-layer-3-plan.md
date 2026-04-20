# elm-rad Layer 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 3 — debounced cells. Add `DebouncedCell a` with two observable values (raw, settled) plus a derived `synced : Source Bool`; `commit`/`revert` actions; Vite-view commit triggers (OnEnter, OnBlur, OnTimeout); `Process.sleep`-based latest-wins timer scheduling; three new example apps. Purely additive on Layer 2.

**Architecture:** Each `DebouncedCell a` owns three Registry slots — raw cellId, settled cellId, and a `timerSeq` counter cellId. `fromDebouncedInput` writes raw, bumps seq, and schedules `Process.sleep`; the fire msg checks seq and copies raw→settled if still current. Stale fires are silently dropped. `commit` and `revert` are plain `Registry → Registry` actions that copy between raw and settled without touching seq.

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x, `elm/core` `Process`/`Task`, Vite 6, `vite-plugin-elm`. **No new package dependencies.**

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per memory `feedback_commit_cadence.md`). Each commit must be reviewable on its own and must leave the tree green.
- **One task = one commit** unless the header says otherwise.
- **Before every commit that touches `.elm` files, run `elm-format`** (per memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes` (from repo root).
  - Examples: `npx --yes elm-format src --yes` (from `examples/`).
  - Stage formatting changes in the same commit.
- Verification commands: `npx --yes elm-test` (from repo root). `cd examples && npm run build` for examples build. `cd examples && npm run dev` for visual browser checks (use curl against the running server instead of starting a new one — the user typically has one live).
- **Commit messages are the imperative single-line style of prior commits** (`Add X`, `Ship Y`). No Co-Authored-By trailers unless explicitly requested.

**Key design decision resolved in this plan (design Section 7, `bindDebouncedWith []` escape hatch):**
- `fromDebouncedInput` **always** schedules a timer. Bindings whose `triggers` list does NOT include `OnTimeout` must NOT use `fromDebouncedInput` on `onInput` — they use an internal `Rad.Internal.Debounced.rawSetAction` instead, which writes raw and bumps `timerSeq` (invalidating any prior timer) without scheduling a new one. Public `fromDebouncedInput` keeps the design's signature; `rawSetAction` is internal-only, accessed from `Rad.View` inside the package.

**Module layout at the end:**

```
src/
  Rad.elm                         ← + DebouncedCell, withDebounced, raw, settled, synced, commit, revert
  Rad/
    Engine.elm                    ← + fromDebouncedInput public constructor
    Http.elm                      ← unchanged
    Read.elm                      ← unchanged
    View.elm                      ← + CommitTrigger, bindDebounced, bindDebouncedWith (Attribute variant)
    Internal/
      Action.elm                  ← unchanged
      Debounced.elm               ← NEW: DebouncedCell opaque record + Ref + applyInput/applyTimerFire/rawSetAction
      Msg.elm                     ← + DebouncedInput and DebouncedTimerFire variants
      Reaction.elm                ← unchanged
      Registry.elm                ← unchanged
      Request.elm                 ← unchanged
      Source.elm                  ← unchanged
tests/
  <all Layer 0-2 suites unchanged>
  DebouncedTest.elm               ← NEW
  DebouncedSemanticsTest.elm      ← NEW
  DebouncedLatestWinsTest.elm     ← NEW
examples/
  elm.json                        ← unchanged
  package.json                    ← unchanged
  vite.config.js                  ← + 3 new entries
  mock-api-plugin.js              ← unchanged (reuses existing /api/search endpoint)
  index.html                      ← + 3 new links
  debounce-echo.html              ← NEW
  search-debounced.html           ← NEW
  custom-triggers.html            ← NEW
  <existing .html files unchanged>
  src/
    SimpleView.elm                ← + debouncedInput primitive
    DebounceEcho.elm              ← NEW
    SearchDebounced.elm           ← NEW
    CustomTriggers.elm            ← NEW
    <existing .elm files unchanged>
```

**Note on `examples/mock-api-plugin.js`:** the design doc Section 4 says to add `GET /api/search?q=...` → `{ results: [...] }`. The existing Layer 2 `/api/search` endpoint returns `{ query, matches }` and is used by `derived-search`. **This plan keeps the existing shape and uses `matches` in the new `SearchDebounced` example** — changing the shape would break `derived-search`. Design-level deviation; noted here and in Task 5.1.

---

## Slice 1 — `DebouncedCell` type + `withDebounced` builder

### Task 1.1: Create `Rad.Internal.Debounced` module

**Files:**
- Create: `src/Rad/Internal/Debounced.elm`

- [ ] **Step 1: Create the module:**

```elm
module Rad.Internal.Debounced exposing
    ( DebouncedCell(..)
    , Ref
    , core
    , ref
    )

{-| Internal shape of `DebouncedCell a`. The constructor is exposed to `Rad`
(for `withDebounced`, `raw`, `settled`, `commit`, `revert`), to `Rad.Engine`
(for `fromDebouncedInput`), and to `Rad.View` (for `bindDebouncedWith`).
User code only sees `Rad.DebouncedCell a`, opaquely.
-}

import Json.Decode as Decode


{-| Full internal record. Holds the three Registry slot IDs, the codec,
delay, and initial value (used for decode fallback in source readers).
-}
type DebouncedCell a
    = DebouncedCell (Core a)


type alias Core a =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , delayMs : Float
    , initial : a
    }


core : DebouncedCell a -> Core a
core (DebouncedCell c) =
    c


{-| A type-erased slice used by `Msg` variants. Carries everything `update`
needs to dispatch debounced-input and timer-fire messages (the three slot IDs
and the delay), but not the codec — values are already encoded by the time
they reach the Msg, and the timer-fire handler just copies bytes raw→settled.
-}
type alias Ref =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , delayMs : Float
    }


ref : DebouncedCell a -> Ref
ref (DebouncedCell c) =
    { rawId = c.rawId
    , settledId = c.settledId
    , timerSeqId = c.timerSeqId
    , delayMs = c.delayMs
    }
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm make src/Rad/Internal/Debounced.elm --output=/dev/null`
Expected: success.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Debounced.elm
git commit -m "Add internal DebouncedCell type"
```

---

### Task 1.2: Expose `DebouncedCell` and `withDebounced`; add `DebouncedTest`

**Atomic commit.** Lands the public surface (just the type alias + builder entry) and the first test suite verifying construction allocates three Registry slots.

**Files:**
- Modify: `src/Rad.elm` (exposing list, import, body)
- Create: `tests/DebouncedTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/DebouncedTest.elm`:

```elm
module DebouncedTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (DebouncedCell, build, stringCodec, withDebounced)
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { text : DebouncedCell String }


init : Rad.CellBuilder Model
init =
    build Model |> withDebounced "text" 800 "hello" stringCodec


suite : Test
suite =
    describe "withDebounced"
        [ test "allocates three Registry slots with initial values" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    decode id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)

                    decodeInt id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                in
                Expect.equal
                    { raw = Just "hello", settled = Just "hello", timerSeq = Just 0 }
                    { raw = decode r.rawId, settled = decode r.settledId, timerSeq = decodeInt r.timerSeqId }
        , test "IDs are distinct and sequential" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text
                in
                Expect.equal
                    ( r.rawId, r.settledId, r.timerSeqId )
                    ( 0, 1, 2 )
        , test "delayMs is preserved on the ref" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.within (Expect.Absolute 0.001)
                    800
                    (IDebounced.ref model.text |> .delayMs)
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/DebouncedTest.elm`
Expected: compile error — `Rad.DebouncedCell`, `Rad.withDebounced` not found.

- [ ] **Step 3: Update `src/Rad.elm`.**

In the exposing list, add after `Cell`:
```elm
    , DebouncedCell, withDebounced
```

In the `@docs` block, add after the `Cell` line:
```elm
@docs DebouncedCell, withDebounced
```

Add the import (alphabetically between `Rad.Internal.Action` and `Rad.Internal.Msg`):
```elm
import Rad.Internal.Debounced as IDebounced
```

Add the type alias and `withDebounced` body. Place them right after `runBuilder`:

```elm
{-| A cell with settle semantics. Holds two observable values — `raw` (updates
on every keystroke or `fromDebouncedInput`) and `settled` (updates on commit,
revert, or after a timer). Constructed via `withDebounced`. Opaque.
-}
type alias DebouncedCell a =
    IDebounced.DebouncedCell a


{-| Add a debounced cell to the builder. Allocates three Registry slots
(raw, settled, and a per-cell timer sequence counter) seeded from `initial`.
-}
withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withDebounced _ delayMs initial codec (CellBuilder b) =
    let
        rawId =
            b.nextId

        settledId =
            b.nextId + 1

        timerSeqId =
            b.nextId + 2

        cell =
            IDebounced.DebouncedCell
                { rawId = rawId
                , settledId = settledId
                , timerSeqId = timerSeqId
                , codec = codec
                , delayMs = delayMs
                , initial = initial
                }

        encodedInitial =
            codec.encode initial
    in
    CellBuilder
        { nextId = b.nextId + 3
        , metas =
            ( timerSeqId, Encode.int 0 )
                :: ( settledId, encodedInitial )
                :: ( rawId, encodedInitial )
                :: b.metas
        , ctor = b.ctor cell
        }
```

Note: the `key` argument (first positional) is currently ignored (matches the `with` convention where `key` is metadata for future persistence; Layer 0-1 also ignores it in `with`). The underscore in the destructured parameter name (`_ delayMs ...`) documents this.

- [ ] **Step 4: Run tests to confirm pass.**

Run: `npx --yes elm-test`
Expected: all Layer 0-2 suites pass + 3 new tests in DebouncedTest. Total 36.

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/DebouncedTest.elm
git commit -m "Expose DebouncedCell and withDebounced"
```

---

## Slice 2 — Source accessors + commit/revert Actions

### Task 2.1: Add `raw` and `settled` Source accessors

**Files:**
- Modify: `src/Rad.elm` (exposing list, body)
- Modify: `tests/DebouncedTest.elm` (add 2 more tests exercising raw and settled)

- [ ] **Step 1: Extend `tests/DebouncedTest.elm`** `suite` list with two tests (append inside the `describe` body, after the existing three):

```elm
        , test "raw reads the raw value" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "hello" (Rad.readSource (Rad.raw model.text) registry)
        , test "settled reads the settled value" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "hello" (Rad.readSource (Rad.settled model.text) registry)
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/DebouncedTest.elm`
Expected: compile error — `Rad.raw`, `Rad.settled` not found.

- [ ] **Step 3: Update `src/Rad.elm`** exposing list — add after `DebouncedCell, withDebounced`:

```elm
    , raw, settled
```

Add to `@docs` block:

```elm
@docs raw, settled
```

Add the implementations (near `withDebounced`):

```elm
{-| A `Source` for the raw value of a debounced cell — updates on every
`fromDebouncedInput` (or keystroke via a view binding) and via `revert`.
-}
raw : DebouncedCell a -> Source a
raw (IDebounced.DebouncedCell d) =
    IS.Source
        { read =
            \registry ->
                case Registry.get d.rawId registry of
                    Just v ->
                        Result.withDefault d.initial (Decode.decodeValue d.codec.decode v)

                    Nothing ->
                        d.initial
        , codec = d.codec
        }


{-| A `Source` for the settled value of a debounced cell — updates on
`commit`, `revert`, or after the debounce timer fires.
-}
settled : DebouncedCell a -> Source a
settled (IDebounced.DebouncedCell d) =
    IS.Source
        { read =
            \registry ->
                case Registry.get d.settledId registry of
                    Just v ->
                        Result.withDefault d.initial (Decode.decodeValue d.codec.decode v)

                    Nothing ->
                        d.initial
        , codec = d.codec
        }
```

- [ ] **Step 4: Run tests to confirm pass.**

Run: `npx --yes elm-test`
Expected: all suites green, total 38.

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/DebouncedTest.elm
git commit -m "Add raw and settled source accessors"
```

---

### Task 2.2: Add `synced` derived Source

**Files:**
- Modify: `src/Rad.elm` (exposing list, body)
- Modify: `tests/DebouncedTest.elm` (add synced test)

- [ ] **Step 1: Extend the test suite** with:

```elm
        , test "synced starts True when raw equals settled" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal True (Rad.readSource (Rad.synced model.text) registry)
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/DebouncedTest.elm`
Expected: compile error — `Rad.synced` not found.

- [ ] **Step 3: Update `src/Rad.elm`** exposing list — add `, synced` alongside raw and settled, and to `@docs`.

Implementation:

```elm
{-| A derived `Source Bool` reporting whether a debounced cell's raw and
settled values are equal. Uses JSON-encoded equality via the cell's codec,
consistent with Layer 2 trigger-change detection.
-}
synced : DebouncedCell a -> Source Bool
synced cell =
    let
        rawSource =
            raw cell

        settledSource =
            settled cell
    in
    derive boolCodec
        (Rad.Read.map2
            (\r s ->
                Encode.encode 0 ((IS.codec rawSource).encode r)
                    == Encode.encode 0 ((IS.codec settledSource).encode s)
            )
            (Rad.Read.read rawSource)
            (Rad.Read.read settledSource)
        )
```

- [ ] **Step 4: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total 39.

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/DebouncedTest.elm
git commit -m "Add synced derived source"
```

---

### Task 2.3: Add `commit` and `revert` Actions; create `DebouncedSemanticsTest`

**Files:**
- Modify: `src/Rad.elm` (exposing list, body)
- Create: `tests/DebouncedSemanticsTest.elm`

- [ ] **Step 1: Write `tests/DebouncedSemanticsTest.elm`:**

```elm
module DebouncedSemanticsTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (DebouncedCell, build, commit, revert, stringCodec, withDebounced)
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { text : DebouncedCell String }


init : Rad.CellBuilder Model
init =
    build Model |> withDebounced "text" 800 "hello" stringCodec


{-| Test helper: simulate a raw write without going through the Msg layer.
Writes the encoded value and bumps timerSeq. Used to set up pre-conditions
for commit/revert tests before Slice 3's Msg wiring lands.
-}
writeRaw : DebouncedCell String -> String -> Registry.Registry -> Registry.Registry
writeRaw cell value registry =
    let
        r =
            IDebounced.ref cell

        currentSeq =
            Registry.get r.timerSeqId registry
                |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                |> Maybe.withDefault 0
    in
    registry
        |> Registry.insert r.rawId (Encode.string value)
        |> Registry.insert r.timerSeqId (Encode.int (currentSeq + 1))


suite : Test
suite =
    describe "Debounced commit and revert"
        [ test "commit copies raw to settled" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0

                    registry2 =
                        Rad.applyAction (commit model.text) registry1
                in
                Expect.equal
                    { raw = "world", settled = "world" }
                    { raw = Rad.readSource (Rad.raw model.text) registry2
                    , settled = Rad.readSource (Rad.settled model.text) registry2
                    }
        , test "revert copies settled to raw" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0

                    registry2 =
                        Rad.applyAction (revert model.text) registry1
                in
                Expect.equal
                    { raw = "hello", settled = "hello" }
                    { raw = Rad.readSource (Rad.raw model.text) registry2
                    , settled = Rad.readSource (Rad.settled model.text) registry2
                    }
        , test "synced is True after commit" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0

                    registry2 =
                        Rad.applyAction (commit model.text) registry1
                in
                Expect.equal True (Rad.readSource (Rad.synced model.text) registry2)
        , test "synced is True after revert" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0

                    registry2 =
                        Rad.applyAction (revert model.text) registry1
                in
                Expect.equal True (Rad.readSource (Rad.synced model.text) registry2)
        , test "synced is False while raw differs from settled" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0
                in
                Expect.equal False (Rad.readSource (Rad.synced model.text) registry1)
        , test "commit neither touches timerSeq nor allocates new cells" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        writeRaw model.text "world" registry0

                    seqBefore =
                        Registry.get (IDebounced.ref model.text |> .timerSeqId) registry1
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)

                    registry2 =
                        Rad.applyAction (commit model.text) registry1

                    seqAfter =
                        Registry.get (IDebounced.ref model.text |> .timerSeqId) registry2
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                in
                Expect.equal seqBefore seqAfter
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/DebouncedSemanticsTest.elm`
Expected: compile error — `Rad.commit`, `Rad.revert` not found.

- [ ] **Step 3: Update `src/Rad.elm`** exposing list — add `, commit, revert` alongside raw, settled, synced. Add to `@docs`.

Implementation (place after `synced`):

```elm
{-| Commit a debounced cell's raw value to its settled value (copies raw →
settled). A pure `Action`; does not touch the timer sequence, so any in-flight
timer will fire harmlessly (raw and settled already match).
-}
commit : DebouncedCell a -> Action model
commit (IDebounced.DebouncedCell d) =
    IA.Action
        (\registry ->
            case Registry.get d.rawId registry of
                Just rawValue ->
                    Registry.insert d.settledId rawValue registry

                Nothing ->
                    registry
        )


{-| Revert a debounced cell's raw value to its settled value (copies settled
→ raw). Dual of `commit`. Does not touch the timer sequence.
-}
revert : DebouncedCell a -> Action model
revert (IDebounced.DebouncedCell d) =
    IA.Action
        (\registry ->
            case Registry.get d.settledId registry of
                Just settledValue ->
                    Registry.insert d.rawId settledValue registry

                Nothing ->
                    registry
        )
```

- [ ] **Step 4: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total 45 (39 + 6 new in DebouncedSemanticsTest).

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/DebouncedSemanticsTest.elm
git commit -m "Add commit and revert actions"
```

---

## Slice 3 — Msg variants + `fromDebouncedInput` + timer scheduling

### Task 3.1: Add `DebouncedInput` and `DebouncedTimerFire` variants to `Rad.Internal.Msg`

**Files:**
- Modify: `src/Rad/Internal/Msg.elm` (new variants + updated `apply`)

- [ ] **Step 1: Rewrite `src/Rad/Internal/Msg.elm`:**

```elm
module Rad.Internal.Msg exposing (Msg(..), apply)

{-| Internal definition of `Msg model`. The constructor is exposed so that
`Rad.elm` (runtime) can pattern-match, while `Rad.Engine` re-exports `Msg`
opaquely — keeping engines unaware of variants.
-}

import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type.
-}
type Msg model
    = ApplyAction (IA.Action model)
    | ReactionResult Int Int (Result Never Encode.Value)
    | DebouncedInput IDebounced.Ref Encode.Value
    | DebouncedTimerFire IDebounced.Ref Int


{-| Apply an engine-originated message to the registry. Reaction results and
debounced dispatches are handled by the runtime separately.
-}
apply : Msg model -> Registry -> Registry
apply msg registry =
    case msg of
        ApplyAction action ->
            IA.apply action registry

        ReactionResult _ _ _ ->
            registry

        DebouncedInput _ _ ->
            registry

        DebouncedTimerFire _ _ ->
            registry
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm-test`
Expected: all 45 tests pass. Engines never produce these new variants, so existing tests and examples are unaffected.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Msg.elm
git commit -m "Add DebouncedInput and DebouncedTimerFire Msg variants"
```

---

### Task 3.2: Add `applyInput`, `applyTimerFire`, `rawSetAction` helpers to `Rad.Internal.Debounced`

**Files:**
- Modify: `src/Rad/Internal/Debounced.elm`

- [ ] **Step 1: Extend `src/Rad/Internal/Debounced.elm`**. Add the following exposing entries: `applyInput`, `applyTimerFire`, `getTimerSeq`, `rawSetAction`. Add the imports `Rad.Internal.Action as IA`, `Rad.Internal.Registry as Registry exposing (Registry)`, and `Json.Decode as Decode`, `Json.Encode as Encode` at the top.

Full updated file:

```elm
module Rad.Internal.Debounced exposing
    ( DebouncedCell(..)
    , Ref
    , applyInput
    , applyTimerFire
    , core
    , getTimerSeq
    , rawSetAction
    , ref
    )

{-| Internal shape of `DebouncedCell a` plus the pure helpers the runtime,
`Rad.View`, and tests call. User code only sees `Rad.DebouncedCell a`.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Registry as Registry exposing (Registry)


type DebouncedCell a
    = DebouncedCell (Core a)


type alias Core a =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , delayMs : Float
    , initial : a
    }


core : DebouncedCell a -> Core a
core (DebouncedCell c) =
    c


type alias Ref =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , delayMs : Float
    }


ref : DebouncedCell a -> Ref
ref (DebouncedCell c) =
    { rawId = c.rawId
    , settledId = c.settledId
    , timerSeqId = c.timerSeqId
    , delayMs = c.delayMs
    }


{-| Read the current timer sequence counter for a debounced cell. Defaults
to 0 if absent or non-integer.
-}
getTimerSeq : Int -> Registry -> Int
getTimerSeq timerSeqId registry =
    Registry.get timerSeqId registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
        |> Maybe.withDefault 0


{-| Apply a DebouncedInput message's state change: write the encoded value
to the raw slot and bump the timer sequence. Returns the registry plus the
newly-assigned seq number (used by the caller to schedule the fire task).
-}
applyInput : Ref -> Encode.Value -> Registry -> ( Registry, Int )
applyInput r encodedValue registry =
    let
        newSeq =
            getTimerSeq r.timerSeqId registry + 1
    in
    ( registry
        |> Registry.insert r.rawId encodedValue
        |> Registry.insert r.timerSeqId (Encode.int newSeq)
    , newSeq
    )


{-| Apply a DebouncedTimerFire message's state change: if the fired seq is
stale (less than the current seq), no-op. Otherwise copy raw → settled.
-}
applyTimerFire : Ref -> Int -> Registry -> Registry
applyTimerFire r firedSeq registry =
    let
        currentSeq =
            getTimerSeq r.timerSeqId registry
    in
    if firedSeq < currentSeq then
        registry

    else
        case Registry.get r.rawId registry of
            Just rawValue ->
                Registry.insert r.settledId rawValue registry

            Nothing ->
                registry


{-| A plain `Action` that writes raw and bumps timerSeq without scheduling a
timer. Used by `Rad.View.bindDebouncedWith` for bindings whose trigger list
does not include `OnTimeout`, so keystrokes don't spawn timers that would
auto-commit.
-}
rawSetAction : DebouncedCell a -> a -> IA.Action model
rawSetAction (DebouncedCell c) value =
    IA.Action
        (\registry ->
            let
                newSeq =
                    getTimerSeq c.timerSeqId registry + 1
            in
            registry
                |> Registry.insert c.rawId (c.codec.encode value)
                |> Registry.insert c.timerSeqId (Encode.int newSeq)
        )
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm-test`
Expected: all 45 tests pass.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Debounced.elm
git commit -m "Add applyInput, applyTimerFire, rawSetAction helpers"
```

---

### Task 3.3: Wire debounced dispatch into `run` with `Process.sleep`

**Files:**
- Modify: `src/Rad.elm` (extend `update` inside `run`; add imports)

- [ ] **Step 1: Add `import Process` at the top of `src/Rad.elm`** (alphabetically, between `Json.Encode` and `Rad.Engine`).

- [ ] **Step 2: Extend the `case msg of` in the `update` handler inside `run`.** Add two new branches after the existing `IMsg.ReactionResult` branch. The full updated update block reads:

```elm
        , update =
            \msg ( m, registry, state ) ->
                case msg of
                    IMsg.ApplyAction action ->
                        let
                            reg1 =
                                IA.apply action registry

                            ( reg2, state2, cmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), cmd )

                    IMsg.ReactionResult i receivedSeq result ->
                        -- unchanged from Layer 2
                        case Dict.get i state.seqs of
                            Just expected ->
                                if expected /= receivedSeq then
                                    ( ( m, registry, state ), Cmd.none )

                                else
                                    case result of
                                        Ok encoded ->
                                            let
                                                reactions =
                                                    app.reactions m (app.computed m)

                                                maybeReaction =
                                                    reactions
                                                        |> List.drop i
                                                        |> List.head
                                            in
                                            case maybeReaction of
                                                Just (IReaction.Reaction r) ->
                                                    ( ( m, r.writeResult encoded registry, state )
                                                    , Cmd.none
                                                    )

                                                Nothing ->
                                                    ( ( m, registry, state ), Cmd.none )

                                        Err _ ->
                                            ( ( m, registry, state ), Cmd.none )

                            Nothing ->
                                ( ( m, registry, state ), Cmd.none )

                    IMsg.DebouncedInput dRef encodedValue ->
                        let
                            ( reg1, newSeq ) =
                                IDebounced.applyInput dRef encodedValue registry

                            timerCmd =
                                Process.sleep dRef.delayMs
                                    |> Task.perform
                                        (\_ -> IMsg.DebouncedTimerFire dRef newSeq)

                            ( reg2, state2, reactionCmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), Cmd.batch [ timerCmd, reactionCmd ] )

                    IMsg.DebouncedTimerFire dRef firedSeq ->
                        let
                            reg1 =
                                IDebounced.applyTimerFire dRef firedSeq registry

                            ( reg2, state2, reactionCmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), reactionCmd )
```

Leave the other `Browser.element` fields (`init`, `subscriptions`, `view`) unchanged.

- [ ] **Step 3: Verify compilation.**

Run: `npx --yes elm-test`
Expected: 45 tests pass (no new tests yet; Task 3.5 adds the latest-wins suite).

Run: `cd examples && npm run build`
Expected: all 11 example entries still build.

- [ ] **Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 5: Commit.**

```bash
git add src/Rad.elm
git commit -m "Wire debounced dispatch into run with Process.sleep"
```

---

### Task 3.4: Add `fromDebouncedInput` public constructor to `Rad.Engine`

**Files:**
- Modify: `src/Rad/Engine.elm` (expose + implement)

- [ ] **Step 1: Update `src/Rad/Engine.elm`.** Add `fromDebouncedInput` to the exposing list and `@docs` block, add the import, and implement it:

```elm
module Rad.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput, applyMsg)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, fromDebouncedInput, applyMsg

-}

import Html exposing (Html)
import Rad.Internal.Action as IA
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Msg as IMsg
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type. Opaque. Engines construct values via
`fromAction` or `fromDebouncedInput`; the runtime may add internal variants
without breaking engines.
-}
type alias Msg model =
    IMsg.Msg model


{-| Convert a user-level action into a runtime message that engines can
attach to event handlers.
-}
fromAction : IA.Action model -> Msg model
fromAction =
    IMsg.ApplyAction


{-| Construct a runtime message that writes `value` to a debounced cell's
raw slot and schedules a `Process.sleep` timer that commits raw → settled
after the cell's configured delay. Used by view engines on `onInput` for
debounced bindings.

Engines that want a raw write without scheduling a timer should use
`Rad.View.bindDebouncedWith` with a trigger list that excludes `OnTimeout`
(that binding dispatches a plain Action instead).
-}
fromDebouncedInput : IDebounced.DebouncedCell a -> a -> Msg model
fromDebouncedInput cell value =
    let
        c =
            IDebounced.core cell
    in
    IMsg.DebouncedInput (IDebounced.ref cell) (c.codec.encode value)


{-| Apply a runtime message to the registry. Used by the Layer 0-1 runtime
wrapper; reaction and debounced messages are handled by the runtime directly.
-}
applyMsg : Msg model -> Registry -> Registry
applyMsg =
    IMsg.apply


{-| A view engine transforms the engine's view type into `Html (Msg model)`.
-}
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
```

Note: `fromDebouncedInput` takes `IDebounced.DebouncedCell a` directly. Since `Rad.DebouncedCell` is a type alias for this, callers pass a `Rad.DebouncedCell a` and it type-checks.

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm-test`
Expected: all 45 tests pass.

Run: `cd examples && npm run build`
Expected: 11 entries build.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Engine.elm
git commit -m "Add fromDebouncedInput public constructor"
```

---

### Task 3.5: Add `DebouncedLatestWinsTest`

**Files:**
- Create: `tests/DebouncedLatestWinsTest.elm`

- [ ] **Step 1: Write `tests/DebouncedLatestWinsTest.elm`** — exercises `applyInput` + `applyTimerFire` directly to verify latest-wins without going through the update cycle:

```elm
module DebouncedLatestWinsTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (DebouncedCell, build, stringCodec, withDebounced)
import Rad.Internal.Debounced as IDebounced
import Test exposing (..)


type alias Model =
    { text : DebouncedCell String }


init : Rad.CellBuilder Model
init =
    build Model |> withDebounced "text" 800 "hello" stringCodec


suite : Test
suite =
    describe "Debounced latest-wins"
        [ test "a stale timer fire (seq < current) is a no-op" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    -- Write "a" → seq 1, write "b" → seq 2.
                    ( registry1, seq1 ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, _seq2 ) =
                        IDebounced.applyInput r (Encode.string "b") registry1

                    -- Stale fire for seq 1 — current is 2; should no-op.
                    registry3 =
                        IDebounced.applyTimerFire r seq1 registry2
                in
                Expect.equal
                    { raw = "b", settled = "hello" }
                    { raw = Rad.readSource (Rad.raw model.text) registry3
                    , settled = Rad.readSource (Rad.settled model.text) registry3
                    }
        , test "a current timer fire (seq == current) copies raw to settled" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    ( registry1, _seq1 ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, seq2 ) =
                        IDebounced.applyInput r (Encode.string "b") registry1

                    registry3 =
                        IDebounced.applyTimerFire r seq2 registry2
                in
                Expect.equal
                    { raw = "b", settled = "b" }
                    { raw = Rad.readSource (Rad.raw model.text) registry3
                    , settled = Rad.readSource (Rad.settled model.text) registry3
                    }
        , test "applyInput bumps timerSeq monotonically" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    ( _registry1, seq1 ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, seq2 ) =
                        IDebounced.applyInput r (Encode.string "b")
                            (IDebounced.applyInput r (Encode.string "a") registry0 |> Tuple.first)

                    ( _registry3, seq3 ) =
                        IDebounced.applyInput r (Encode.string "c") registry2
                in
                Expect.equal ( seq1, seq2, seq3 ) ( 1, 2, 3 )
        ]
```

- [ ] **Step 2: Run tests.**

Run: `npx --yes elm-test`
Expected: all green. Total 48 (45 + 3 new).

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add tests/DebouncedLatestWinsTest.elm
git commit -m "Add DebouncedLatestWinsTest"
```

---

## Slice 4 — `Rad.View` bindings + `SimpleView.debouncedInput` + `debounce-echo` example

### Task 4.1: Add `CommitTrigger`, `bindDebounced`, `bindDebouncedWith` to `Rad.View`

**Files:**
- Modify: `src/Rad/View.elm` (exposing list, new Attribute variant, wiring in `input`)

- [ ] **Step 1: Update `src/Rad/View.elm`** to expose and implement the debounced binding. Full updated module:

```elm
module Rad.View exposing
    ( Attribute, HtmlView
    , CommitTrigger(..)
    , bind, bindDebounced, bindDebouncedWith, onClick
    , button, col, input, text, watch
    , htmlEngine
    )

{-| The HTML view engine and its primitives.

@docs Attribute, HtmlView
@docs CommitTrigger
@docs bind, bindDebounced, bindDebouncedWith, onClick
@docs button, col, input, text, watch
@docs htmlEngine

-}

import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Rad exposing (Action, Cell, DebouncedCell, Source, commit, readSource, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput)
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry exposing (Registry)


{-| A commit trigger for debounced bindings.
-}
type CommitTrigger
    = OnEnter
    | OnBlur
    | OnTimeout


{-| An attribute applied to an HTML primitive. Encodes reactive intent (bind,
bindDebounced, onClick) that `htmlEngine` wires into real `Html.Attribute`s
at render time.
-}
type Attribute model
    = BindString (Cell String)
    | BindDebouncedString (DebouncedCell String) (List CommitTrigger)
    | OnClick (Action model)


{-| Dispatch an action when an element is clicked.
-}
onClick : Action model -> Attribute model
onClick =
    OnClick


{-| The HTML view value.
-}
type HtmlView model
    = HtmlView (Registry -> Html.Html (Msg model))


{-| Two-way bind an input's value to a `Cell String`.
-}
bind : Cell String -> Attribute model
bind =
    BindString


{-| Bind an input to a `DebouncedCell String` with all commit triggers
enabled (`OnEnter`, `OnBlur`, `OnTimeout`) — the common debounce case.
-}
bindDebounced : DebouncedCell String -> Attribute model
bindDebounced cell =
    BindDebouncedString cell [ OnEnter, OnBlur, OnTimeout ]


{-| Bind an input to a `DebouncedCell String` with a custom set of commit
triggers. The empty list is a valid escape hatch: no view trigger commits;
the only paths to settled are explicit `commit` / `revert` actions.
-}
bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> Attribute model
bindDebouncedWith triggers cell =
    BindDebouncedString cell triggers


{-| A vertical stack.
-}
col : List (Attribute model) -> List (HtmlView model) -> HtmlView model
col _ children =
    HtmlView
        (\r ->
            Html.div [] (List.map (\(HtmlView f) -> f r) children)
        )


{-| An HTML `<input>`.
-}
input : List (Attribute model) -> List (HtmlView model) -> HtmlView model
input attrs _ =
    HtmlView
        (\registry ->
            let
                ( valueAttr, evtAttrs ) =
                    List.foldl
                        (\a ( vs, evts ) ->
                            case a of
                                BindString cell ->
                                    ( Html.Attributes.value (readSource (toSource cell) registry) :: vs
                                    , Html.Events.onInput (\v -> fromAction (set cell v)) :: evts
                                    )

                                BindDebouncedString cell triggers ->
                                    let
                                        inputHandler =
                                            if List.member OnTimeout triggers then
                                                \v -> fromDebouncedInput cell v

                                            else
                                                \v -> fromAction (IDebounced.rawSetAction cell v)

                                        triggerEvents =
                                            debouncedTriggerEvents triggers cell
                                    in
                                    ( Html.Attributes.value
                                        (readSource (Rad.raw cell) registry)
                                        :: vs
                                    , Html.Events.onInput inputHandler
                                        :: (triggerEvents ++ evts)
                                    )

                                OnClick _ ->
                                    ( vs, evts )
                        )
                        ( [], [] )
                        attrs
            in
            Html.input (valueAttr ++ evtAttrs) []
        )


{-| Plain text.
-}
text : String -> HtmlView model
text s =
    HtmlView (\_ -> Html.text s)


{-| An HTML `<button>`.
-}
button : List (Attribute model) -> List (HtmlView model) -> HtmlView model
button attrs children =
    HtmlView
        (\registry ->
            let
                clickAttrs =
                    List.concatMap
                        (\a ->
                            case a of
                                OnClick action ->
                                    [ Html.Events.onClick (fromAction action) ]

                                _ ->
                                    []
                        )
                        attrs
            in
            Html.button clickAttrs
                (List.map (\(HtmlView f) -> f registry) children)
        )


{-| Subscribe a view region to a source.
-}
watch : Source a -> (a -> HtmlView model) -> HtmlView model
watch source f =
    HtmlView
        (\registry ->
            let
                (HtmlView g) =
                    f (readSource source registry)
            in
            g registry
        )


{-| The shipped HTML engine.
-}
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = \registry (HtmlView f) -> f registry }



-- INTERNALS


debouncedTriggerEvents :
    List CommitTrigger
    -> DebouncedCell String
    -> List (Html.Attribute (Msg model))
debouncedTriggerEvents triggers cell =
    let
        commitMsg =
            fromAction (commit cell)
    in
    List.filterMap
        (\t ->
            case t of
                OnEnter ->
                    Just
                        (Html.Events.on "keydown"
                            (Decode.field "key" Decode.string
                                |> Decode.andThen
                                    (\k ->
                                        if k == "Enter" then
                                            Decode.succeed commitMsg

                                        else
                                            Decode.fail "non-Enter key"
                                    )
                            )
                        )

                OnBlur ->
                    Just (Html.Events.onBlur commitMsg)

                OnTimeout ->
                    Nothing
        )
        triggers
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm-test`
Expected: 48 tests pass.

Run: `cd examples && npm run build`
Expected: 11 entries build. The `greeting-html` example (which uses `Rad.View`) still compiles — its usage of `Attribute` and `input` is unchanged.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/View.elm
git commit -m "Add CommitTrigger, bindDebounced, bindDebouncedWith"
```

---

### Task 4.2: Add `debouncedInput` primitive to `examples/src/SimpleView.elm`

**Files:**
- Modify: `examples/src/SimpleView.elm`

- [ ] **Step 1: Update `examples/src/SimpleView.elm`.** Add `debouncedInput` to the exposing list and implement it. Full updated module:

```elm
module SimpleView exposing
    ( SimpleView
    , button
    , col
    , debouncedInput
    , input
    , simpleViewEngine
    , text
    , watch
    )

import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Rad
    exposing
        ( Action
        , Cell
        , DebouncedCell
        , Source
        , commit
        , readSource
        , set
        , toSource
        )
import Rad.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput)
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry exposing (Registry)
import Rad.View exposing (CommitTrigger(..))


type SimpleView model
    = SimpleView (Registry -> Html.Html (Msg model))


col : List (SimpleView model) -> SimpleView model
col children =
    SimpleView
        (\r ->
            Html.div [] (List.map (\(SimpleView f) -> f r) children)
        )


input : { label : String, cell : Cell String } -> SimpleView model
input { label, cell } =
    SimpleView
        (\registry ->
            Html.label []
                [ Html.text (label ++ ": ")
                , Html.input
                    [ Html.Attributes.value (readSource (toSource cell) registry)
                    , Html.Events.onInput (\v -> fromAction (set cell v))
                    ]
                    []
                ]
        )


debouncedInput :
    { label : String, cell : DebouncedCell String, triggers : List CommitTrigger }
    -> SimpleView model
debouncedInput { label, cell, triggers } =
    SimpleView
        (\registry ->
            let
                inputHandler =
                    if List.member OnTimeout triggers then
                        \v -> fromDebouncedInput cell v

                    else
                        \v -> fromAction (IDebounced.rawSetAction cell v)

                commitMsg =
                    fromAction (commit cell)

                triggerAttrs =
                    List.filterMap
                        (\t ->
                            case t of
                                OnEnter ->
                                    Just
                                        (Html.Events.on "keydown"
                                            (Decode.field "key" Decode.string
                                                |> Decode.andThen
                                                    (\k ->
                                                        if k == "Enter" then
                                                            Decode.succeed commitMsg

                                                        else
                                                            Decode.fail "non-Enter key"
                                                    )
                                            )
                                        )

                                OnBlur ->
                                    Just (Html.Events.onBlur commitMsg)

                                OnTimeout ->
                                    Nothing
                        )
                        triggers
            in
            Html.label []
                [ Html.text (label ++ ": ")
                , Html.input
                    ([ Html.Attributes.value (readSource (Rad.raw cell) registry)
                     , Html.Events.onInput inputHandler
                     ]
                        ++ triggerAttrs
                    )
                    []
                ]
        )


text : String -> SimpleView model
text s =
    SimpleView (\_ -> Html.text s)


watch : Source a -> (a -> SimpleView model) -> SimpleView model
watch source f =
    SimpleView
        (\registry ->
            let
                (SimpleView g) =
                    f (readSource source registry)
            in
            g registry
        )


button : { label : String, onClick : Action model } -> SimpleView model
button { label, onClick } =
    SimpleView
        (\_ ->
            Html.button
                [ Html.Events.onClick (fromAction onClick) ]
                [ Html.text label ]
        )


simpleViewEngine : ViewEngine (SimpleView model) model
simpleViewEngine =
    { toHtml = \registry (SimpleView f) -> f registry }
```

- [ ] **Step 2: Verify compilation of examples.**

Run: `cd examples && npm run build`
Expected: 11 entries build. No changes to existing examples' behavior.

- [ ] **Step 3: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 4: Commit.**

```bash
git add examples/src/SimpleView.elm
git commit -m "Add SimpleView.debouncedInput primitive"
```

---

### Task 4.3: Ship `debounce-echo` example

**Files:**
- Create: `examples/src/DebounceEcho.elm`
- Create: `examples/debounce-echo.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/DebounceEcho.elm`:**

```elm
module DebounceEcho exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , DebouncedCell
        , build
        , commit
        , revert
        , run
        , stringCodec
        , withDebounced
        )
import Rad.Engine exposing (Msg)
import Rad.View exposing (CommitTrigger(..))
import SimpleView
    exposing
        ( SimpleView
        , button
        , col
        , debouncedInput
        , simpleViewEngine
        , text
        , watch
        )


type alias Model =
    { text : DebouncedCell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model |> withDebounced "text" 800 "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ debouncedInput
                    { label = "Type here"
                    , cell = model.text
                    , triggers = [ OnEnter, OnBlur, OnTimeout ]
                    }
                , watch (Rad.raw model.text) (\r -> text ("raw: " ++ r))
                , watch (Rad.settled model.text) (\s -> text ("settled: " ++ s))
                , watch (Rad.synced model.text)
                    (\s ->
                        if s then
                            text "✓ synced"

                        else
                            text "… pending"
                    )
                , button { label = "Commit", onClick = commit model.text }
                , button { label = "Revert", onClick = revert model.text }
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/debounce-echo.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>debounce-echo</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/DebounceEcho.elm";
      Elm.DebounceEcho.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** `input` map, after `derived-search`:

```javascript
"debounce-echo": resolve(__dirname, "debounce-echo.html"),
```

- [ ] **Step 4: Add a link to `examples/index.html`** after `derived-search`:

```html
<li><a href="debounce-echo.html">debounce-echo</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 12 entries (index + 11 examples).

- [ ] **Step 7: Visual verification (optional, via user's running dev server).** The dev server hot-reloads `vite.config.js`. Visit `localhost:5173/debounce-echo.html` in a browser. Expected behavior:
- Typing updates the `raw:` line immediately.
- After 800ms of no typing, `settled:` updates to match and "… pending" flips to "✓ synced".
- Pressing Enter or blurring commits immediately.
- `Commit` / `Revert` buttons work as expected.

If a browser isn't handy, a smoke via curl against the running server (just confirming the page builds) is sufficient:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://localhost:5173/debounce-echo.html'
```

Expected: `200`.

- [ ] **Step 8: Commit.**

```bash
git add examples/src/DebounceEcho.elm examples/debounce-echo.html examples/vite.config.js examples/index.html
git commit -m "Ship debounce-echo example"
```

---

## Slice 5 — `search-debounced` example

### Task 5.1: Ship `search-debounced` example

**Files:**
- Create: `examples/src/SearchDebounced.elm`
- Create: `examples/search-debounced.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

**Note:** This example reuses the existing `/api/search` endpoint from Layer 2's `derived-search` example (returns `{ query, matches }`). The design doc Section 4 proposed a new `results` shape, but changing the mock would break `derived-search`. Deviation documented in the plan header. The example consumes the `matches` field, identical to `derived-search`.

- [ ] **Step 1: Write `examples/src/SearchDebounced.elm`:**

```elm
module SearchDebounced exposing (main)

import Json.Decode as Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , DebouncedCell
        , Remote(..)
        , build
        , listCodec
        , on
        , remoteCodec
        , run
        , stringCodec
        , withDebounced
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView
    exposing
        ( SimpleView
        , col
        , debouncedInput
        , simpleViewEngine
        , text
        , watch
        )
import Rad.View exposing (CommitTrigger(..))


type alias Model =
    { query : DebouncedCell String
    , results : Cell (Remote RequestError (List String))
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withDebounced "query" 500 "" stringCodec
            |> with "results" Idle (remoteCodec requestErrorCodec (listCodec stringCodec))
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ debouncedInput
                    { label = "Search"
                    , cell = model.query
                    , triggers = [ OnEnter, OnBlur, OnTimeout ]
                    }
                , watch (Rad.settled model.query) (\q -> text ("settled query: \"" ++ q ++ "\""))
                , watch (Rad.toSource model.results) renderResults
                ]
    , reactions =
        \model _ ->
            [ on (Rad.settled model.query)
                (\q ->
                    if String.trim q == "" then
                        Rad.noRequest

                    else
                        Http.httpGet prodHandler ("/api/search?q=" ++ q) matchesDecoder
                )
                model.results
            ]
    }


matchesDecoder : Decode.Decoder (List String)
matchesDecoder =
    Decode.field "matches" (Decode.list Decode.string)


renderResults : Remote RequestError (List String) -> SimpleView Model
renderResults r =
    case r of
        Idle ->
            text "(type to search)"

        Loading ->
            text "searching…"

        Failed _ ->
            text "(error)"

        Done matches ->
            col (List.map (\m -> text (" • " ++ m)) matches)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/search-debounced.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>search-debounced</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/SearchDebounced.elm";
      Elm.SearchDebounced.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after `debounce-echo`):

```javascript
"search-debounced": resolve(__dirname, "search-debounced.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="search-debounced.html">search-debounced</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 13 entries.

- [ ] **Step 7: Live curl check (against running dev server).**

```bash
curl -s 'http://localhost:5173/api/search?q=elm'
```

Expected: `{"query":"elm","matches":["elm-alpha","elm-beta","elm-gamma"]}` after ~2s.

- [ ] **Step 8: Commit.**

```bash
git add examples/src/SearchDebounced.elm examples/search-debounced.html examples/vite.config.js examples/index.html
git commit -m "Ship search-debounced example"
```

---

## Slice 6 — `custom-triggers` example + docs sweep

### Task 6.1: Ship `custom-triggers` example

**Files:**
- Create: `examples/src/CustomTriggers.elm`
- Create: `examples/custom-triggers.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/CustomTriggers.elm`:**

```elm
module CustomTriggers exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , DebouncedCell
        , build
        , run
        , stringCodec
        , withDebounced
        )
import Rad.Engine exposing (Msg)
import Rad.View exposing (CommitTrigger(..))
import SimpleView
    exposing
        ( SimpleView
        , col
        , debouncedInput
        , simpleViewEngine
        , text
        , watch
        )


type alias Model =
    { text : DebouncedCell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model |> withDebounced "text" 1500 "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ text "Top input commits on Enter only:"
                , debouncedInput
                    { label = "Enter-only"
                    , cell = model.text
                    , triggers = [ OnEnter ]
                    }
                , text "Bottom input commits on Blur or after 1.5s timeout:"
                , debouncedInput
                    { label = "Blur + Timeout"
                    , cell = model.text
                    , triggers = [ OnBlur, OnTimeout ]
                    }
                , watch (Rad.settled model.text) (\s -> text ("shared settled: \"" ++ s ++ "\""))
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/custom-triggers.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>custom-triggers</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/CustomTriggers.elm";
      Elm.CustomTriggers.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after `search-debounced`):

```javascript
"custom-triggers": resolve(__dirname, "custom-triggers.html"),
```

- [ ] **Step 4: Add link to `examples/index.html`:**

```html
<li><a href="custom-triggers.html">custom-triggers</a></li>
```

- [ ] **Step 5: Run `elm-format` on examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build check.**

Run: `cd examples && npm run build`
Expected: 14 entries (index + 13 examples).

- [ ] **Step 7: Commit.**

```bash
git add examples/src/CustomTriggers.elm examples/custom-triggers.html examples/vite.config.js examples/index.html
git commit -m "Ship custom-triggers example"
```

---

### Task 6.2: Sweep `docs/design-elm-rad.md` Layer 3 section

**Files:**
- Modify: `docs/design-elm-rad.md`

- [ ] **Step 1: Read the existing Debounce section** in `docs/design-elm-rad.md` (around line 284). It already describes the public API (`DebouncedCell`, `raw`, `settled`, `synced`, `commit`, `revert`, `bindDebounced`, `bindDebouncedWith`). Layer 3's design doc (Section 6) locks in five implementation decisions that the reference docs should also mention:

  1. **Two cells + one timerSeq counter internally** (three Registry slots per `DebouncedCell`).
  2. **Seq-based supersession for latest-wins** — stale timer fires are silently dropped.
  3. **`commit` / `revert` are pure `Action`s** — do not touch `timerSeq`; any pending fire becomes a harmless no-op because raw and settled match.
  4. **`synced` is derived, not stored** — `raw == settled` via codec JSON equality. A stored flag was explicitly rejected.
  5. **Per-binding trigger sets** — `bindDebouncedWith [OnEnter]` excludes timer-based commits by dispatching a plain `Action` on input, not `fromDebouncedInput`.

- [ ] **Step 2: Append an "Implementation notes" subsection** at the end of the Debounce section. Use this content:

```markdown
### Implementation notes

Recorded here so future contributors don't re-debate them.

1. **Three Registry slots per `DebouncedCell`.** `withDebounced` allocates raw, settled, and a per-cell timer sequence counter. The raw and settled slots hold encoded `a` values; the timer-sequence slot holds an `Int`.

2. **Seq-based supersession.** Each `fromDebouncedInput` bumps the timer sequence; the scheduled `Process.sleep` task captures the seq it was created with. On fire, the runtime compares: if the fire's seq is less than the current seq, the fire is stale and the update is dropped. Latest input always wins without cancelling tasks.

3. **`commit` and `revert` are pure Actions.** They copy between raw and settled via the Registry. They do **not** touch the timer sequence. A pending timer fire after `commit` or `revert` finds raw and settled equal and performs a no-op copy. If the user typed again, that input bumped the seq and the pending fire is already stale.

4. **`synced` is derived.** Reads raw and settled via the cell's codec, compares their JSON-encoded forms. No stored flag — the source of truth is `raw == settled`. A stored flag would require every raw/settled write site to maintain it; the drift risk outweighed any observable win.

5. **Per-binding trigger sets.** `bindDebouncedWith` decides its `onInput` handler at attribute-wiring time: if the trigger list contains `OnTimeout`, the handler uses `Rad.Engine.fromDebouncedInput` (schedules a timer); otherwise it uses an internal `Action` that writes raw and bumps the seq without scheduling. `OnEnter` and `OnBlur` attach commit handlers regardless of whether `OnTimeout` is present.
```

- [ ] **Step 2b:** Insert the subsection immediately before the Section 317-320 paragraph that begins "Debounce is fundamentally about..." — that paragraph is the natural close of the Debounce section. Place the new `### Implementation notes` before it.

- [ ] **Step 3: Verify the file still reads coherently.** Skim around the insertion point to check flow.

- [ ] **Step 4: Commit.**

```bash
git add docs/design-elm-rad.md
git commit -m "docs: record Layer 3 implementation decisions"
```

---

## Final Checkpoint — Task 7.1: Full verification sweep

- [ ] **Step 1: Package tests.**

Run: `npx --yes elm-test`
Expected: **48 tests pass** (33 prior + 15 new in Layer 3). Breakdown:
- Layer 0-1 (19): ActionTest, CellBuilderTest, CodecTest, ReadTest.
- Layer 2 (14): RemoteCodecTest, SourceCodecTest, RequestTest, ReactionTriggerTest, LatestWinsTest.
- Layer 3 (15): DebouncedTest (3 from Task 1.2 + 2 from Task 2.1 + 1 from Task 2.2 = 6), DebouncedSemanticsTest (6 from Task 2.3), DebouncedLatestWinsTest (3 from Task 3.5).

Report the actual output.

- [ ] **Step 2: Package docs build.**

Run: `npx --yes elm make --docs docs.json`
Expected: success.

- [ ] **Step 3: Examples build.**

Run: `cd examples && npm run build`
Expected: **14 HTML entries** build (index + 10 Layer 0-2 + 3 Layer 3).

- [ ] **Step 4: Live smoke (against user's running dev server).** Curl each new example (just checking they load as 200):

```bash
for e in debounce-echo search-debounced custom-triggers; do
    echo "$e: $(curl -s -o /dev/null -w '%{http_code}' "http://localhost:5173/$e.html")"
done
```

Expected: all `200`.

Plus confirm the existing mocked endpoint used by `search-debounced`:

```bash
curl -s 'http://localhost:5173/api/search?q=elm'
```

Expected: `{"query":"elm","matches":["elm-alpha","elm-beta","elm-gamma"]}` after ~2s.

- [ ] **Step 5: TestRunner still compiles.**

Run: `cd examples && npx --yes elm make src/TestRunner.elm --output=/dev/null`
Expected: success.

- [ ] **Step 6: Visual behavioral smoke (manual, in browser).**
- `debounce-echo`: type in the input. Raw updates immediately. After 800ms pause, settled matches and "✓ synced" displays. Enter commits immediately. Blur commits immediately. Commit/Revert buttons work.
- `search-debounced`: type "el". No request fires yet. After 500ms, a request fires and results render after ~2s delay.
- `custom-triggers`: type in the top input. After 1500ms, settled does NOT update (no OnTimeout on this binding). Press Enter — settled updates. Type in the bottom input. Blur or wait 1500ms — settled updates via shared cell.

- [ ] **Step 7: Commit history sanity.**

Run: `git log --oneline main ^<base-sha> | wc -l`
Replace `<base-sha>` with the commit immediately prior to this slice (the Layer 2 HEAD). Expected: roughly 18 commits (16 task commits + 1 plan commit + ≤1 follow-up).

- [ ] **Step 8: Clean tree.**

Run: `git status`
Expected: clean working tree.

---

## Out-of-slice notes

- **If `Process.sleep` times look off on certain browsers (especially backgrounded tabs):** this is expected — design Section 7 risk 1. Not a bug. Document in the example README if noise becomes an issue.
- **If adding `debouncedInput` to `SimpleView` breaks an unrelated Layer 0-1 example via an unintended import:** unlikely (SimpleView's existing consumers don't import `debouncedInput`), but if so, the break surfaces at `elm make --optimize`. Trace the compile error and either remove the stray import or add a stub.
- **If `bindDebouncedWith [OnTimeout]` alone (no Enter, no Blur) is desired:** supported — the view binding wires only the timer via `fromDebouncedInput`.
- **If you need to dispatch a raw write from outside a view binding** (e.g., a programmatic "type into the debounced cell" action): use `Rad.Engine.fromDebouncedInput` (schedules timer) or — if timer suppression is wanted — call `Rad.Internal.Debounced.rawSetAction` via `fromAction`. The `rawSetAction` helper is internal; if a public escape hatch becomes useful, expose `Rad.setRawDebounced` in a follow-up. YAGNI for Layer 3.
- **Design decision reference:** Section 7 of the Layer 3 design doc records the "derive synced, don't store" and "commit/revert as pure Actions" trade-offs. Keep this plan aligned; if a decision changes, update the design doc and re-propagate.
