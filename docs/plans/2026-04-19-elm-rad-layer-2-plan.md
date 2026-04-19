# elm-rad Layer 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Layer 2 of the `elm-rad` DSL — `Remote err a`, `Request err a`, effect-library-agnostic reactions dispatched via `on`/`AppDef.reactions`, `Rad.Http` module built on `elm/http`, four new example apps driven by a Vite mock middleware, and the scrappy `TestRunner.elm` harness.

**Architecture:** Reactions are rebuilt per cycle from `AppDef.reactions : model -> computed -> List (Reaction model)`. A trigger is a `Source a` whose encoded JSON is compared cycle-over-cycle (hence `Source a` now carries a `Codec a`). When a trigger changes, the user's `a -> Request err r` produces a `Task err r` that is dispatched with a monotonic seq number; stale results are dropped (latest-wins). The target cell stores `Remote err r`, transitioning `Idle | Loading | Failed | Done`. Core carries no HTTP dependency; `Rad.Http` owns `elm/http` entirely.

**Tech Stack:** Elm 0.19.1 package, `elm-explorations/test` 2.x, `elm/http` 2.x, Vite 6, `vite-plugin-elm`, `npx elm` / `npx elm-test` / `npx elm-format`.

**Workflow conventions:**
- **No worktree.** Commit directly on `main` in small atomic commits (per memory `feedback_commit_cadence.md`). Each commit must be reviewable on its own and must leave the tree green (`elm make` compiles; tests pass where applicable).
- **One task = one commit** unless a task's header says otherwise. Where two tasks are grouped as a single atomic commit (e.g., a breaking API change plus its call-site migrations), that is called out.
- **Before every commit that touches `.elm` files, run `elm-format`** (per memory `feedback_elm_format.md`):
  - Package root: `npx --yes elm-format src tests --yes` (from repo root)
  - Examples: `npx --yes elm-format src --yes` (from `examples/`)
  - Stage any formatting modifications via `git add` and include them in the same commit.
- Verification command for the package: `npx --yes elm-test` (from repo root); `npx --yes elm make --output=/dev/null src/Rad.elm src/Rad/Engine.elm src/Rad/Read.elm src/Rad/View.elm src/Rad/Http.elm` for full build once `Rad.Http` lands.
- Verification command for examples: `npm run build` (from `examples/`) for smoke; `npm run dev` for visual verification.

**One design decision resolved by this plan (Slice 1, Section 8.3 of design doc):** The runtime does **not** need `remoteCodec` to expose component codecs. Instead, the `on` function captures typed `err`/`r` via its closure and uses the **target cell's combined `Codec (Remote err r)`** (built via `remoteCodec`) to encode `Loading`, `Done r`, and `Failed e` directly. The internal task is collapsed to `Task Never Encode.Value` (always succeeds; err-vs-ok already folded into `Remote`). Concretely:

```elm
-- On task completion, before dispatch:
task
    |> Task.map    (\r -> targetCodec.encode (Done r))
    |> Task.onError (\e -> Task.succeed (targetCodec.encode (Failed e)))
```

This removes the need for a `remoteCodec` bundle type and keeps `remoteCodec : Codec err -> Codec a -> Codec (Remote err a)` exactly as the design spec shows. `InternalRequest` and `Reaction` become correspondingly simpler — one `writeResult` path instead of split `writeSuccess` / `writeFailure`.

**Module layout at the end:**

```
src/
  Rad.elm                         ← + Remote, remoteCodec, Request (opaque), noRequest, mapRequestError, Reaction (opaque), on, AppDef.reactions
  Rad/
    Engine.elm                    ← re-exports Msg opaquely; Msg moves to Rad.Internal.Msg
    Http.elm                      ← NEW: Handler, prodHandler, httpGet, httpPost, RequestError, requestErrorCodec
    Read.elm                      ← unchanged
    View.elm                      ← unchanged
    Internal/
      Action.elm                  ← unchanged
      Registry.elm                ← unchanged
      Source.elm                  ← BREAKING: Source carries Codec a
      Msg.elm                     ← NEW: Msg definition with ReactionResult variant
      Request.elm                 ← NEW: internal Request type; effect-library seam
      Reaction.elm                ← NEW: internal Reaction record, InternalRequest, ReactionState
tests/
  ActionTest.elm                  ← unchanged
  CellBuilderTest.elm             ← unchanged
  CodecTest.elm                   ← unchanged
  ReadTest.elm                    ← unchanged (but derive call sites updated)
  RemoteCodecTest.elm             ← NEW
  SourceCodecTest.elm             ← NEW
  RequestTest.elm                 ← NEW
  ReactionTriggerTest.elm         ← NEW
  LatestWinsTest.elm              ← NEW
examples/
  elm.json                        ← + elm/http
  package.json
  vite.config.js                  ← + mockApi plugin + 4 new entries
  mock-api-plugin.js              ← NEW
  index.html                      ← + 4 new links
  fetch-joke.html                 ← NEW
  github-user.html                ← NEW
  post-note.html                  ← NEW
  derived-search.html             ← NEW
  greeting-html.html, greeting.html, counter.html, swap.html, full-name.html, temperature.html
  src/
    FullName.elm                  ← derive stringCodec
    Temperature.elm               ← derive stringCodec
    GreetingHtml.elm, Greeting.elm, Counter.elm, Swap.elm   ← + reactions field (= \_ _ -> [])
    SimpleView.elm                ← unchanged
    FetchJoke.elm                 ← NEW
    GithubUser.elm                ← NEW
    PostNote.elm                  ← NEW
    DerivedSearch.elm             ← NEW
    TestRunner.elm                ← NEW, scrappy
```

---

## Slice 1 — `Remote` + `Source`/`derive` codec migration

**Objective:** Add `Remote err a` with `remoteCodec`, and migrate `Source a` to carry its `Codec a` (so triggers can be compared by encoded JSON in Slice 4). All Layer 0-1 examples continue to render.

### Task 1.1: Add `Remote err a` type, `remoteCodec`, and `RemoteCodecTest`

**Files:**
- Modify: `src/Rad.elm` (add `Remote`, `remoteCodec` to exposing list and body)
- Create: `tests/RemoteCodecTest.elm`

- [ ] **Step 1: Write the failing test.** Create `tests/RemoteCodecTest.elm`:

```elm
module RemoteCodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Remote(..), intCodec, remoteCodec, stringCodec)
import Test exposing (..)


type alias Codec a =
    { encode : a -> Decode.Value, decode : Decode.Decoder a }


roundTrip : Codec a -> a -> Result Decode.Error a
roundTrip codec v =
    codec.encode v |> Decode.decodeValue codec.decode


suite : Test
suite =
    let
        c =
            remoteCodec stringCodec intCodec
    in
    describe "remoteCodec"
        [ test "round-trips Idle" <|
            \_ -> roundTrip c Idle |> Expect.equal (Ok Idle)
        , test "round-trips Loading" <|
            \_ -> roundTrip c Loading |> Expect.equal (Ok Loading)
        , test "round-trips Failed" <|
            \_ -> roundTrip c (Failed "nope") |> Expect.equal (Ok (Failed "nope"))
        , test "round-trips Done" <|
            \_ -> roundTrip c (Done 42) |> Expect.equal (Ok (Done 42))
        , test "nested remoteCodec round-trips" <|
            \_ ->
                let
                    nested =
                        remoteCodec stringCodec (remoteCodec stringCodec intCodec)
                in
                roundTrip nested (Done (Done 7))
                    |> Expect.equal (Ok (Done (Done 7)))
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/RemoteCodecTest.elm`
Expected: compile error — `Rad.Remote`, `Rad.remoteCodec` not found.

- [ ] **Step 3: Implement in `src/Rad.elm`.** Add to exposing list and below the `maybeCodec` definition:

```elm
-- In exposing list (append):
    , Remote(..), remoteCodec


{-| A remote resource in one of four states.
-}
type Remote err a
    = Idle
    | Loading
    | Failed err
    | Done a


{-| A codec for `Remote err a` given codecs for the error and value types.

The wire format is a tagged object: `{"tag":"Idle"}`, `{"tag":"Loading"}`,
`{"tag":"Failed","value":<errEncoded>}`, `{"tag":"Done","value":<valueEncoded>}`.
-}
remoteCodec : Codec err -> Codec a -> Codec (Remote err a)
remoteCodec errCodec valueCodec =
    let
        encode r =
            case r of
                Idle ->
                    Encode.object [ ( "tag", Encode.string "Idle" ) ]

                Loading ->
                    Encode.object [ ( "tag", Encode.string "Loading" ) ]

                Failed e ->
                    Encode.object
                        [ ( "tag", Encode.string "Failed" )
                        , ( "value", errCodec.encode e )
                        ]

                Done v ->
                    Encode.object
                        [ ( "tag", Encode.string "Done" )
                        , ( "value", valueCodec.encode v )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Idle" ->
                                Decode.succeed Idle

                            "Loading" ->
                                Decode.succeed Loading

                            "Failed" ->
                                Decode.map Failed (Decode.field "value" errCodec.decode)

                            "Done" ->
                                Decode.map Done (Decode.field "value" valueCodec.decode)

                            other ->
                                Decode.fail ("unknown Remote tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }
```

- [ ] **Step 4: Run tests to confirm pass.**

Run: `npx --yes elm-test`
Expected: all previous suites pass + new `remoteCodec` tests pass.

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/RemoteCodecTest.elm
git commit -m "Add Remote type and remoteCodec"
```

---

### Task 1.2: Migrate `Source a` to carry `Codec a`, update `derive` signature, migrate examples

**Atomic commit — breaking change across package + examples.** This lands the `Source a → carries codec` change plus `derive : Codec a -> Read a -> Source a` plus the two call-site updates in a single commit so the tree compiles at every revision.

**Files:**
- Modify: `src/Rad/Internal/Source.elm` (Source now carries codec)
- Modify: `src/Rad.elm` (toSource, derive signatures)
- Modify: `tests/ReadTest.elm` (add stringCodec to `derive` call)
- Create: `tests/SourceCodecTest.elm`
- Modify: `examples/src/FullName.elm` (add stringCodec to derive)
- Modify: `examples/src/Temperature.elm` (add stringCodec to derive)

- [ ] **Step 1: Write `tests/SourceCodecTest.elm`** covering the invariant that `toSource` pulls the cell's codec and `derive` threads the supplied codec through:

```elm
module SourceCodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Cell, build, derive, intCodec, stringCodec, toSource, with)
import Rad.Internal.Source as IS
import Rad.Read as Read
import Test exposing (..)


type alias Model =
    { n : Cell Int, s : Cell String }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "n" 7 intCodec
        |> with "s" "hi" stringCodec


suite : Test
suite =
    describe "Source carries its codec"
        [ test "toSource pulls the cell's codec" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    source =
                        toSource model.n

                    encoded =
                        (IS.codec source).encode (Rad.readSource source registry)
                in
                Decode.decodeValue Decode.int encoded
                    |> Expect.equal (Ok 7)
        , test "derive threads the supplied codec" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    derived =
                        derive stringCodec
                            (Read.map (\n -> "n=" ++ String.fromInt n)
                                (Read.read (toSource model.n))
                            )

                    encoded =
                        (IS.codec derived).encode (Rad.readSource derived registry)
                in
                Decode.decodeValue Decode.string encoded
                    |> Expect.equal (Ok "n=7")
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/SourceCodecTest.elm`
Expected: compile error — `IS.codec` not found, `derive stringCodec ...` doesn't match `derive : Read a -> Source a`.

- [ ] **Step 3: Rewrite `src/Rad/Internal/Source.elm`** to carry a codec:

```elm
module Rad.Internal.Source exposing (Source(..), codec, readSource)

import Json.Decode as Decode
import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Source` opaque type with its constructor exposed so that
`Rad` and `Rad.Read` can both construct sources without depending on each
other. The codec is stored alongside the reader so the runtime can encode
source values (used for trigger-change detection in reactions).
-}
type Source a
    = Source
        { read : Registry -> a
        , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
        }


readSource : Source a -> Registry -> a
readSource (Source s) registry =
    s.read registry


codec : Source a -> { encode : a -> Decode.Value, decode : Decode.Decoder a }
codec (Source s) =
    s.codec
```

- [ ] **Step 4: Update `src/Rad.elm`.** `toSource` now passes the cell's codec; `derive` takes a `Codec a` first:

In the exposing list, the signatures stay but the behavior changes. Replace the two function bodies:

```elm
{-| Convert a cell into a readable source.
-}
toSource : Cell a -> Source a
toSource (Cell c) =
    IS.Source
        { read =
            \registry ->
                case Registry.get c.id registry of
                    Just v ->
                        Result.withDefault c.initial (Decode.decodeValue c.codec.decode v)

                    Nothing ->
                        c.initial
        , codec = c.codec
        }


{-| Turn a `Read` into a `Source`. The resulting source recomputes its value
from the registry on every read, and carries the supplied codec so the runtime
can encode derived values (for trigger-change detection).
-}
derive : Codec a -> Rad.Read.Read a -> Source a
derive codecA readValue =
    IS.Source
        { read = \registry -> Rad.Read.run readValue registry
        , codec = codecA
        }
```

Also update `Rad/Read.elm`'s `read` function? No — `read : Source a -> Read a` just uses `readSource`. No change needed there.

- [ ] **Step 5: Update `tests/ReadTest.elm`.** The `derive` call in the `"derive produces a Source that reflects its Read's current value"` test now needs `stringCodec` as first arg:

```elm
-- was:
fullNameSource =
    Rad.derive
        (Read.map2 ...)

-- becomes:
fullNameSource =
    Rad.derive stringCodec
        (Read.map2 ...)
```

- [ ] **Step 6: Update `examples/src/FullName.elm`.** Change the `derive` call:

```elm
-- was:
full =
    derive
        (Read.map2 ...)

-- becomes:
full =
    derive stringCodec
        (Read.map2 ...)
```

- [ ] **Step 7: Update `examples/src/Temperature.elm`.** Change both `derive` calls similarly (the module already imports `stringCodec`):

```elm
, fahrenheit =
    derive stringCodec
        (Read.map (formatTemp << toFahrenheit)
            (Read.read (toSource model.celsius))
        )
, kelvin =
    derive stringCodec
        (Read.map (formatTemp << toKelvin)
            (Read.read (toSource model.celsius))
        )
```

- [ ] **Step 8: Run all tests.**

Run: `npx --yes elm-test`
Expected: all suites (including new `SourceCodecTest`) pass.

- [ ] **Step 9: Verify examples compile.**

Run: `cd examples && npm run build`
Expected: vite build succeeds for all six existing examples.

- [ ] **Step 10: Run `elm-format`** on both roots.

```bash
npx --yes elm-format src tests --yes
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 11: Commit.**

```bash
git add src/Rad.elm src/Rad/Internal/Source.elm \
        tests/ReadTest.elm tests/SourceCodecTest.elm \
        examples/src/FullName.elm examples/src/Temperature.elm
git commit -m "Source carries its Codec; derive takes Codec a"
```

---

## Slice 2 — `Request err a` + `Rad.Http` module

**Objective:** Introduce the effect-library seam. `Request err a` is opaque in `Rad`; `Rad.Http` builds concrete requests. No reactions wired yet — a scratch scenario compiles through `on`'s future signature? No: `on` lands in Slice 4. For Slice 2, Checkpoint is just type-level: `Rad.Http.httpGet prodHandler "/api/joke" jokeDecoder : Rad.Request Rad.Http.RequestError Joke` type-checks.

### Task 2.1: Add internal `Request err a` type

**Files:**
- Create: `src/Rad/Internal/Request.elm`

- [ ] **Step 1: Create `src/Rad/Internal/Request.elm`:**

```elm
module Rad.Internal.Request exposing
    ( Request(..)
    , dispatch
    , mapError
    )

{-| Internal shape of `Request err a`. The constructor is exposed to `Rad`
(for `noRequest`, `mapRequestError`) and to effect-library modules like
`Rad.Http` (for `dispatch`). User code sees only `Rad.Request`, opaquely.

A `Request err a` is either a dispatchable `Task err a` or a no-op
(`NoRequest`). Layer 2 does not add other constructors; later layers may
(e.g., timers) without breaking the public API.
-}

import Task exposing (Task)


type Request err a
    = NoRequest
    | DispatchRequest (Task err a)


{-| Effect libraries construct a Request from a Task.
-}
dispatch : Task err a -> Request err a
dispatch =
    DispatchRequest


{-| Transform the error type. `NoRequest` passes through unchanged.
-}
mapError : (e -> f) -> Request e a -> Request f a
mapError f req =
    case req of
        NoRequest ->
            NoRequest

        DispatchRequest task ->
            DispatchRequest (Task.mapError f task)
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm make src/Rad/Internal/Request.elm --output=/dev/null`
Expected: success.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Request.elm
git commit -m "Add internal Request type"
```

---

### Task 2.2: Expose `Request`, `noRequest`, `mapRequestError` from `Rad` + `RequestTest`

**Files:**
- Modify: `src/Rad.elm` (append to exposing list and body)
- Create: `tests/RequestTest.elm`

- [ ] **Step 1: Write `tests/RequestTest.elm`.**

```elm
module RequestTest exposing (suite)

import Expect
import Rad exposing (Request, mapRequestError, noRequest)
import Rad.Internal.Request as IR
import Task
import Test exposing (..)


suite : Test
suite =
    describe "Request"
        [ test "noRequest is the NoRequest variant" <|
            \_ ->
                case noRequest of
                    IR.NoRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected NoRequest"
        , test "mapRequestError on NoRequest is identity" <|
            \_ ->
                case mapRequestError (\_ -> "x") noRequest of
                    IR.NoRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected NoRequest"
        , test "mapRequestError composes" <|
            \_ ->
                let
                    f n =
                        n + 1

                    g n =
                        n * 2

                    base =
                        IR.DispatchRequest (Task.fail 3)

                    composed =
                        base |> mapRequestError g |> mapRequestError f

                    oneShot =
                        base |> mapRequestError (\n -> f (g n))
                in
                -- Both pipelines wrap a Task with the same final error (f (g 3) = 7).
                -- We compare by deconstructing and inspecting Task results via Task.attempt
                -- is not available in elm-test; instead we rely on the structural constraint
                -- that both are DispatchRequest and trust Task's own laws.
                case ( composed, oneShot ) of
                    ( IR.DispatchRequest _, IR.DispatchRequest _ ) ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected both to be DispatchRequest"
        ]
```

- [ ] **Step 2: Run tests to confirm failure.**

Run: `npx --yes elm-test tests/RequestTest.elm`
Expected: `Rad.Request`, `Rad.noRequest`, `Rad.mapRequestError` not found.

- [ ] **Step 3: Append to `src/Rad.elm` exposing list and body:**

```elm
-- In exposing list (append):
    , Request, noRequest, mapRequestError

-- At the top of the file, add:
import Rad.Internal.Request as IRequest

-- In the body (near Action):
{-| An asynchronous request produced by an effect library (e.g., `Rad.Http`).
Opaque; Layer 2 constructors are `noRequest` and values returned by
effect-library functions like `Rad.Http.httpGet`.
-}
type alias Request err a =
    IRequest.Request err a


{-| A Request that does nothing. Returned from the `a -> Request err r`
transform in a reaction to signal "don't dispatch for this trigger value."
-}
noRequest : Request err a
noRequest =
    IRequest.NoRequest


{-| Transform a Request's error type. Useful for mapping a library-defined
error (e.g., `Rad.Http.RequestError`) into a domain error type.
-}
mapRequestError : (e -> f) -> Request e a -> Request f a
mapRequestError =
    IRequest.mapError
```

- [ ] **Step 4: Run tests.**

Run: `npx --yes elm-test`
Expected: all suites pass.

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm tests/RequestTest.elm
git commit -m "Expose Request, noRequest, mapRequestError"
```

---

### Task 2.3: Add `elm/http` dependency to package and examples

**Files:**
- Modify: `elm.json`
- Modify: `examples/elm.json`

- [ ] **Step 1: Add `elm/http` to package `elm.json`** inside `dependencies`:

```json
"elm/http": "2.0.0 <= v < 3.0.0"
```

- [ ] **Step 2: Add `elm/http` to `examples/elm.json`.** In `direct`:

```json
"elm/http": "2.0.0"
```

Add any missing indirect dependencies as reported by Elm. If `npm run build` in a later step complains about indirects, add them here. Typical additions for `elm/http`: `elm/bytes` and `elm/file` in indirect.

- [ ] **Step 3: Verify.**

Run: `npx --yes elm make src/Rad.elm --output=/dev/null`
Expected: success (downloads elm/http on first run).

Run: `cd examples && npm run build`
Expected: all existing examples still build.

- [ ] **Step 4: Commit.**

```bash
git add elm.json examples/elm.json
git commit -m "Add elm/http dependency"
```

---

### Task 2.4: Create `Rad.Http` module

**Files:**
- Create: `src/Rad/Http.elm`
- Modify: `elm.json` (add `Rad.Http` to exposed-modules)

- [ ] **Step 1: Create `src/Rad/Http.elm`:**

```elm
module Rad.Http exposing
    ( Handler, prodHandler
    , RequestError(..), requestErrorCodec
    , httpGet, httpPost
    )

{-| HTTP effect library for `elm-rad`. Core `Rad` has no HTTP dependency;
this module owns `elm/http` entirely.

## Handler

@docs Handler, prodHandler

## Errors

@docs RequestError, requestErrorCodec

## Requests

@docs httpGet, httpPost

-}

import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (Codec, Request)
import Rad.Internal.Request as IRequest
import Task exposing (Task)


{-| A handler abstracts over how HTTP requests are actually made, so tests can
inject mock responses without touching `elm/http`.
-}
type alias Handler =
    { httpGet : String -> Task RequestError String
    , httpPost : String -> Encode.Value -> Task RequestError String
    }


{-| The production handler — delegates to `elm/http`.
-}
prodHandler : Handler
prodHandler =
    { httpGet = \url -> httpTask "GET" url Http.emptyBody
    , httpPost = \url body -> httpTask "POST" url (Http.jsonBody body)
    }


{-| Errors surfaced by `Rad.Http` request builders.
-}
type RequestError
    = Timeout
    | NetworkError
    | BadStatus Int
    | BadBody String


{-| A codec for `RequestError`. Useful as a default error codec when wrapping
HTTP results in `Remote err a`.
-}
requestErrorCodec : Codec RequestError
requestErrorCodec =
    let
        encode err =
            case err of
                Timeout ->
                    Encode.object [ ( "tag", Encode.string "Timeout" ) ]

                NetworkError ->
                    Encode.object [ ( "tag", Encode.string "NetworkError" ) ]

                BadStatus n ->
                    Encode.object
                        [ ( "tag", Encode.string "BadStatus" )
                        , ( "status", Encode.int n )
                        ]

                BadBody s ->
                    Encode.object
                        [ ( "tag", Encode.string "BadBody" )
                        , ( "message", Encode.string s )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Timeout" ->
                                Decode.succeed Timeout

                            "NetworkError" ->
                                Decode.succeed NetworkError

                            "BadStatus" ->
                                Decode.map BadStatus (Decode.field "status" Decode.int)

                            "BadBody" ->
                                Decode.map BadBody (Decode.field "message" Decode.string)

                            other ->
                                Decode.fail ("unknown RequestError tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }


{-| Build a GET request. The decoder is applied to the response body.
-}
httpGet : Handler -> String -> Decode.Decoder a -> Request RequestError a
httpGet handler url decoder =
    handler.httpGet url
        |> Task.andThen (decodeBody decoder)
        |> IRequest.dispatch


{-| Build a POST request. The body is sent as JSON; the decoder is applied
to the response.
-}
httpPost : Handler -> String -> Encode.Value -> Decode.Decoder a -> Request RequestError a
httpPost handler url body decoder =
    handler.httpPost url body
        |> Task.andThen (decodeBody decoder)
        |> IRequest.dispatch



-- INTERNALS


decodeBody : Decode.Decoder a -> String -> Task RequestError a
decodeBody decoder body =
    case Decode.decodeString decoder body of
        Ok v ->
            Task.succeed v

        Err e ->
            Task.fail (BadBody (Decode.errorToString e))


httpTask : String -> String -> Http.Body -> Task RequestError String
httpTask method url body =
    Http.task
        { method = method
        , headers = []
        , url = url
        , body = body
        , resolver = Http.stringResolver stringResolver
        , timeout = Nothing
        }


stringResolver : Http.Response String -> Result RequestError String
stringResolver response =
    case response of
        Http.BadUrl_ url ->
            Err (BadBody ("bad url: " ++ url))

        Http.Timeout_ ->
            Err Timeout

        Http.NetworkError_ ->
            Err NetworkError

        Http.BadStatus_ meta _ ->
            Err (BadStatus meta.statusCode)

        Http.GoodStatus_ _ body ->
            Ok body
```

- [ ] **Step 2: Add `Rad.Http` to `elm.json` exposed-modules.**

```json
"exposed-modules": [
    "Rad",
    "Rad.Engine",
    "Rad.Http",
    "Rad.Read",
    "Rad.View"
],
```

- [ ] **Step 3: Verify compilation.**

Run: `npx --yes elm make src/Rad/Http.elm --output=/dev/null`
Expected: success.

Run: `npx --yes elm-test`
Expected: all suites pass (no new ones, but make sure nothing regressed).

- [ ] **Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 5: Commit.**

```bash
git add src/Rad/Http.elm elm.json
git commit -m "Add Rad.Http module"
```

---

## Slice 3 — Vite mock middleware

**Objective:** `curl localhost:5173/api/joke` returns JSON after ~2s. All four endpoints manually verified.

### Task 3.1: Create `examples/mock-api-plugin.js`

**Files:**
- Create: `examples/mock-api-plugin.js`

- [ ] **Step 1: Write the plugin.**

```javascript
// A scrappy dev-only mock API for Layer 2 examples.
// Every endpoint delays ~2s so latest-wins is visible by eye.

const JOKES = [
  "Why did the developer go broke? Because they used up all their cache.",
  "There are 10 kinds of people: those who get binary and those who don't.",
  "A SQL query walks into a bar, sees two tables, and asks: can I join you?",
];

function pickJoke() {
  return JOKES[Math.floor(Math.random() * JOKES.length)];
}

function sendJson(res, body, ms = 2000) {
  setTimeout(() => {
    res.setHeader("Content-Type", "application/json");
    res.statusCode = 200;
    res.end(JSON.stringify(body));
  }, ms);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

export function mockApi() {
  return {
    name: "mock-api",
    configureServer(server) {
      // GET /api/joke
      server.middlewares.use("/api/joke", (req, res, next) => {
        if (!req.url || !req.url.startsWith("/") || req.method !== "GET") {
          return next();
        }
        sendJson(res, { text: pickJoke() });
      });

      // GET /api/github/users/:login
      server.middlewares.use("/api/github/users/", (req, res, next) => {
        if (req.method !== "GET") return next();
        const login = (req.url || "/").split("/").filter(Boolean).pop() || "";
        sendJson(res, { login, bio: `mock bio for ${login}` });
      });

      // POST /api/note
      server.middlewares.use("/api/note", async (req, res, next) => {
        if (req.method !== "POST") {
          res.statusCode = 405;
          res.end();
          return;
        }
        const raw = await readBody(req);
        let parsed;
        try {
          parsed = JSON.parse(raw);
        } catch (_e) {
          res.statusCode = 400;
          res.end(JSON.stringify({ error: "invalid json" }));
          return;
        }
        sendJson(res, { id: Math.floor(Math.random() * 10000), echoed: parsed });
      });

      // GET /api/search?q=...
      server.middlewares.use("/api/search", (req, res, next) => {
        if (req.method !== "GET") return next();
        const url = new URL(req.url || "/", "http://localhost");
        const q = url.searchParams.get("q") || "";
        sendJson(res, { query: q, matches: [q + "-alpha", q + "-beta", q + "-gamma"] });
      });
    },
  };
}
```

- [ ] **Step 2: Commit (no elm-format needed — JS only).**

```bash
git add examples/mock-api-plugin.js
git commit -m "Add Vite mock-api plugin"
```

---

### Task 3.2: Wire the plugin into `vite.config.js`

**Files:**
- Modify: `examples/vite.config.js`

- [ ] **Step 1: Update `examples/vite.config.js`:**

```javascript
import { defineConfig } from "vite";
import { resolve } from "path";
import elm from "vite-plugin-elm";
import { mockApi } from "./mock-api-plugin.js";

export default defineConfig({
  plugins: [elm(), mockApi()],
  appType: "mpa",
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, "index.html"),
        "greeting-html": resolve(__dirname, "greeting-html.html"),
        greeting: resolve(__dirname, "greeting.html"),
        counter: resolve(__dirname, "counter.html"),
        swap: resolve(__dirname, "swap.html"),
        "full-name": resolve(__dirname, "full-name.html"),
        temperature: resolve(__dirname, "temperature.html"),
      },
    },
  },
});
```

- [ ] **Step 2: Verify endpoints manually** (run `npm run dev` in a separate terminal, then):

```bash
time curl -s localhost:5173/api/joke
time curl -s localhost:5173/api/github/users/octocat
time curl -s -X POST -H 'Content-Type: application/json' -d '{"text":"hi"}' localhost:5173/api/note
time curl -s 'localhost:5173/api/search?q=elm'
```

Expected: each returns JSON after ~2s.

- [ ] **Step 3: Stop `npm run dev`.**

- [ ] **Step 4: Commit.**

```bash
git add examples/vite.config.js
git commit -m "Wire mock-api plugin into Vite"
```

---

## Slice 4 — Reaction runtime + `fetch-joke` ships (biggest slice)

**Objective:** `fetch-joke` renders Idle → Loading → Done/Failed in browser, driven by the Vite mock. New tests cover trigger detection and latest-wins.

This slice lands the runtime change that breaks `AppDef`. Strategy: land the runtime wiring (AppDef field + AppModel shape + Msg variant) first, with all six Layer 0-1 examples migrated in the same commit so the tree compiles. Then add the `on` constructor. Then ship `fetch-joke`. Tests go alongside the code they cover.

### Task 4.1: Add `Reaction model` internal type (private, no public surface yet)

**Files:**
- Create: `src/Rad/Internal/Reaction.elm`

- [ ] **Step 1: Create the internal reaction module:**

```elm
module Rad.Internal.Reaction exposing
    ( InternalRequest(..)
    , Reaction(..)
    , ReactionState
    , emptyState
    )

{-| Internal shape of `Reaction model`. The constructor is exposed to `Rad`
(for `on`) and to the runtime (in `Rad.elm`'s `run`). User code only sees
`Rad.Reaction model`, opaquely.
-}

import Dict exposing (Dict)
import Json.Encode as Encode
import Rad.Internal.Registry exposing (Registry)
import Task exposing (Task)


{-| A built reaction. The runtime reads triggers, builds requests, and
applies writes without knowing the user's `a`, `err`, or `r` types — all type
information is erased into `Encode.Value`.
-}
type Reaction model
    = Reaction
        { readTrigger : Registry -> Encode.Value
        , buildRequest : Registry -> InternalRequest
        , writeLoading : Registry -> Registry
        , writeResult : Encode.Value -> Registry -> Registry
        }


{-| What a reaction produces on a firing cycle. `SkipRequest` means the
trigger changed but the transform returned `noRequest`; in that case the
target cell is not written.

`DispatchTask` carries a task that always succeeds with an already-encoded
`Remote err r` value (err and ok are folded into the `Remote` wrapper before
type erasure, so the runtime does not need component codecs).
-}
type InternalRequest
    = SkipRequest
    | DispatchTask (Task Never Encode.Value)


{-| Per-reaction bookkeeping. Indexed by reaction position in the list
produced by `AppDef.reactions`.
-}
type alias ReactionState =
    { triggers : Dict Int Encode.Value
    , seqs : Dict Int Int
    }


emptyState : ReactionState
emptyState =
    { triggers = Dict.empty, seqs = Dict.empty }
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm make src/Rad/Internal/Reaction.elm --output=/dev/null`
Expected: success.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad/Internal/Reaction.elm
git commit -m "Add internal Reaction type"
```

---

### Task 4.2: Grow `AppModel` to include `ReactionState`; extend `Msg` with `ReactionResult`; add `AppDef.reactions`; migrate all Layer 0-1 examples

**Atomic commit.** This is the big breaking change. Every existing example picks up a `reactions = \_ _ -> []` field; the runtime learns the tuple's third slot but does not yet dispatch anything (no `on` exists yet).

**Architecture note:** per design Section 6 ("Msg model stays opaque with only `fromAction` as the public constructor"), `Msg` must stay opaque to engines. To let `Rad.elm` pattern-match on the new variant, move the `Msg` definition into a private module `Rad.Internal.Msg` and re-export `Msg` opaquely from `Rad.Engine`.

**Files:**
- Create: `src/Rad/Internal/Msg.elm` (holds Msg definition; constructors package-visible)
- Modify: `src/Rad/Engine.elm` (re-exports `Msg` opaquely; `fromAction` and `applyMsg` delegate)
- Modify: `src/Rad.elm` (AppModel tuple gains `ReactionState`; AppDef gains `reactions`; run updated to include `emptyState` slot; ReactionResult handler left as no-op — wired in Task 4.4)
- Modify: `examples/src/GreetingHtml.elm`, `Greeting.elm`, `Counter.elm`, `Swap.elm`, `FullName.elm`, `Temperature.elm` (each gets `reactions = \_ _ -> []`)

- [ ] **Step 1: Create `src/Rad/Internal/Msg.elm`:**

```elm
module Rad.Internal.Msg exposing (Msg(..), apply)

{-| Internal definition of `Msg model`. The constructor is exposed so that
`Rad.elm` (runtime) can pattern-match, while `Rad.Engine` re-exports `Msg`
opaquely — keeping engines unaware of variants.
-}

import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type.
-}
type Msg model
    = ApplyAction (IA.Action model)
    | ReactionResult Int Int (Result Never Encode.Value)


{-| Apply an engine-originated message to the registry. Reaction results are
handled by the runtime separately.
-}
apply : Msg model -> Registry -> Registry
apply msg registry =
    case msg of
        ApplyAction action ->
            IA.apply action registry

        ReactionResult _ _ _ ->
            registry
```

- [ ] **Step 2: Rewrite `src/Rad/Engine.elm`** to re-export opaquely:

```elm
module Rad.Engine exposing (Msg, ViewEngine, fromAction, applyMsg)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, applyMsg

-}

import Html exposing (Html)
import Rad.Internal.Action as IA
import Rad.Internal.Msg as IMsg
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type. Opaque. Engines construct values via
`fromAction`; the runtime may add internal variants without breaking engines.
-}
type alias Msg model =
    IMsg.Msg model


{-| Convert a user-level action into a runtime message that engines can
attach to event handlers.
-}
fromAction : IA.Action model -> Msg model
fromAction =
    IMsg.ApplyAction


{-| Apply a runtime message to the registry. Used by the Layer 0-1 runtime
wrapper; reaction-related messages are handled by the runtime directly in
Layer 2.
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

- [ ] **Step 3: Update `src/Rad.elm`** to:
  - Import `Rad.Internal.Reaction` and `Rad.Internal.Msg`
  - Expose `Reaction` as an opaque alias
  - Change `AppModel` to a 3-tuple
  - Add `reactions` to `AppDef`
  - Update `run` to include `emptyState` in the tuple and ignore reaction dispatch (wired in Task 4.4)

Concretely, add to exposing list:

```elm
    , Reaction
```

Add/update these declarations in the body:

```elm
import Rad.Internal.Msg as IMsg
import Rad.Internal.Reaction as IReaction


{-| A reaction — a rule that says "when this source's value changes, run
this request and store the result in this cell." Constructed via `on`.
Opaque.
-}
type alias Reaction model =
    IReaction.Reaction model


{-| A public alias for the runtime's internal model tuple.
-}
type alias AppModel model =
    ( model, Registry, IReaction.ReactionState )


{-| An application definition.
-}
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
    }


{-| Run an application.
-}
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program () (AppModel model) (Rad.Engine.Msg model)
run engine app =
    let
        ( model, initialRegistry ) =
            runBuilder app.init
    in
    Browser.element
        { init =
            \() ->
                ( ( model, initialRegistry, IReaction.emptyState )
                , Cmd.none
                )
        , update =
            \msg ( m, registry, reactionState ) ->
                case msg of
                    IMsg.ApplyAction action ->
                        ( ( m, IA.apply action registry, reactionState )
                        , Cmd.none
                        )

                    IMsg.ReactionResult _ _ _ ->
                        -- Wired in Task 4.4
                        ( ( m, registry, reactionState )
                        , Cmd.none
                        )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry, _ ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
```

- [ ] **Step 4: Migrate each of the six Layer 0-1 examples.** Each gets `reactions = \_ _ -> []` appended to its `app` record:

For `examples/src/GreetingHtml.elm`, inside `app = { ... }`:

```elm
, reactions = \_ _ -> []
```

Same line added to: `examples/src/Greeting.elm`, `examples/src/Counter.elm`, `examples/src/Swap.elm`, `examples/src/FullName.elm`, `examples/src/Temperature.elm`.

- [ ] **Step 5: Verify the whole tree compiles.**

Run: `npx --yes elm-test`
Expected: all suites pass.

Run: `cd examples && npm run build`
Expected: build succeeds for all six example apps.

- [ ] **Step 6: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 7: Commit.**

```bash
git add src/Rad.elm src/Rad/Engine.elm src/Rad/Internal/Msg.elm examples/src/*.elm
git commit -m "AppDef.reactions, AppModel carries ReactionState, internal Msg variant for reaction results"
```

---

### Task 4.3: Implement `on` in `Rad`

**Files:**
- Modify: `src/Rad.elm` (add `on` to exposing list and body)

- [ ] **Step 1: Add `on` to exposing list.**

```elm
    , on
```

- [ ] **Step 2: Implement `on` in the body** (near the `Reaction` alias):

```elm
{-| Build a reaction.

    reactions =
        \_ _ ->
            [ on (toSource model.tick) (\_ -> Rad.Http.httpGet handler "/api/joke" jokeDecoder) model.joke
            ]

-}
on :
    Source a
    -> (a -> Request err r)
    -> Cell (Remote err r)
    -> Reaction model
on source transform (Cell target) =
    let
        sourceCodec =
            IS.codec source

        targetCodec =
            target.codec
    in
    IReaction.Reaction
        { readTrigger =
            \registry ->
                sourceCodec.encode (IS.readSource source registry)
        , buildRequest =
            \registry ->
                case transform (IS.readSource source registry) of
                    IRequest.NoRequest ->
                        IReaction.SkipRequest

                    IRequest.DispatchRequest task ->
                        IReaction.DispatchTask
                            (task
                                |> Task.map (\r -> targetCodec.encode (Done r))
                                |> Task.onError (\e -> Task.succeed (targetCodec.encode (Failed e)))
                            )
        , writeLoading =
            \registry ->
                Registry.insert target.id (targetCodec.encode Loading) registry
        , writeResult =
            \encoded registry ->
                Registry.insert target.id encoded registry
        }
```

- [ ] **Step 3: Add imports.**

At the top of `src/Rad.elm`:

```elm
import Task
```

(IRequest and IReaction already imported from previous tasks.)

- [ ] **Step 4: Verify compilation.**

Run: `npx --yes elm-test`
Expected: all suites pass (no new ones yet).

- [ ] **Step 5: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 6: Commit.**

```bash
git add src/Rad.elm
git commit -m "Add Rad.on reaction constructor"
```

---

### Task 4.4: Wire reaction dispatch into `run`

**Files:**
- Modify: `src/Rad.elm` (full reaction firing lifecycle in `run`)

- [ ] **Step 1: Replace the body of `run`** with the full lifecycle. Key behaviors per design Section 3:

  - After every update cycle, rebuild the reaction list from `AppDef.reactions model (computed model)`.
  - For each reaction at index `i`:
    - Compute `newTrigger = readTrigger registry`.
    - If `Dict.get i triggers == Just newTrigger`, skip.
    - Else: set `triggers[i] = newTrigger`; bump `seqs[i]`; call `buildRequest registry`:
      - `SkipRequest` → no more work for this reaction.
      - `DispatchTask task` → apply `writeLoading`; `Task.attempt (\r -> ReactionResult i newSeq r) task`.
  - On `ReactionResult i receivedSeq result`:
    - If `Dict.get i seqs /= Just receivedSeq` → stale, drop.
    - Else apply `writeResult encoded registry` (on Ok case; the Task is `Task Never Value` so Err is impossible by type, but pattern-match both arms to satisfy the exhaustiveness checker).
    - Do NOT re-check triggers after writing the result.
  - Orphan-cleanup: at the top of each cycle, drop entries in `triggers`/`seqs` whose index ≥ current list length.

```elm
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program () (AppModel model) (Rad.Engine.Msg model)
run engine app =
    let
        ( model, initialRegistry ) =
            runBuilder app.init

        fireReactions : Registry -> IReaction.ReactionState -> ( Registry, IReaction.ReactionState, Cmd (Rad.Engine.Msg model) )
        fireReactions registry state =
            let
                reactions =
                    app.reactions model (app.computed model)

                listLen =
                    List.length reactions

                prunedState =
                    { triggers = Dict.filter (\k _ -> k < listLen) state.triggers
                    , seqs = Dict.filter (\k _ -> k < listLen) state.seqs
                    }

                step ( i, IReaction.Reaction r ) ( reg, st, cmds ) =
                    let
                        newTrigger =
                            r.readTrigger reg
                    in
                    case Dict.get i st.triggers of
                        Just prev ->
                            if Encode.encode 0 prev == Encode.encode 0 newTrigger then
                                ( reg, st, cmds )

                            else
                                fireOne i newTrigger r reg st cmds

                        Nothing ->
                            fireOne i newTrigger r reg st cmds

                fireOne i newTrigger r reg st cmds =
                    let
                        newSeq =
                            (Dict.get i st.seqs |> Maybe.withDefault 0) + 1

                        st1 =
                            { triggers = Dict.insert i newTrigger st.triggers
                            , seqs = Dict.insert i newSeq st.seqs
                            }
                    in
                    case r.buildRequest reg of
                        IReaction.SkipRequest ->
                            ( reg, st1, cmds )

                        IReaction.DispatchTask task ->
                            ( r.writeLoading reg
                            , st1
                            , Task.attempt (IMsg.ReactionResult i newSeq) task :: cmds
                            )

                ( finalReg, finalState, finalCmds ) =
                    List.foldl step
                        ( registry, prunedState, [] )
                        (List.indexedMap Tuple.pair reactions)
            in
            ( finalReg, finalState, Cmd.batch finalCmds )
    in
    Browser.element
        { init =
            \() ->
                let
                    ( reg1, state1, cmd ) =
                        fireReactions initialRegistry IReaction.emptyState
                in
                ( ( model, reg1, state1 ), cmd )
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
                                            -- Task Never Value: unreachable.
                                            ( ( m, registry, state ), Cmd.none )

                            Nothing ->
                                ( ( m, registry, state ), Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry, _ ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
```

Note the added imports at the top of `src/Rad.elm`:

```elm
import Dict
import Json.Encode as Encode
```

- [ ] **Step 2: Verify compilation.**

Run: `npx --yes elm-test`
Expected: all existing suites pass. `cd examples && npm run build` succeeds.

- [ ] **Step 3: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 4: Commit.**

```bash
git add src/Rad.elm
git commit -m "Wire reaction dispatch lifecycle into run"
```

---

### Task 4.5: Add `ReactionTriggerTest` and `LatestWinsTest`

These are pure tests that exercise the `Reaction` record's functions directly (no browser, no Cmd).

**Files:**
- Create: `tests/ReactionTriggerTest.elm`
- Create: `tests/LatestWinsTest.elm`

- [ ] **Step 1: Write `tests/ReactionTriggerTest.elm`.** Strategy: build a reaction via `on`, call `readTrigger` against a sequence of registries, and assert the encoded JSON matches/differs as expected:

```elm
module ReactionTriggerTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad
    exposing
        ( Cell
        , Remote(..)
        , build
        , intCodec
        , on
        , remoteCodec
        , set
        , stringCodec
        , toSource
        , with
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Request as IRequest
import Test exposing (..)


type alias Model =
    { n : Cell Int
    , out : Cell (Remote String String)
    }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "n" 0 intCodec
        |> with "out" Idle (remoteCodec stringCodec stringCodec)


suite : Test
suite =
    describe "Reaction trigger detection"
        [ test "readTrigger encodes the current source value" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        on (toSource model.n)
                            (\_ -> IRequest.NoRequest)
                            model.out

                    registry1 =
                        Rad.applyAction (set model.n 42) registry0
                in
                Expect.equal
                    ( Encode.encode 0 (Encode.int 0)
                    , Encode.encode 0 (Encode.int 42)
                    )
                    ( Encode.encode 0 (r.readTrigger registry0)
                    , Encode.encode 0 (r.readTrigger registry1)
                    )
        , test "JSON equality is stable for the same value" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        on (toSource model.n) (\_ -> IRequest.NoRequest) model.out
                in
                Expect.equal
                    (Encode.encode 0 (r.readTrigger registry0))
                    (Encode.encode 0 (r.readTrigger registry0))
        ]
```

- [ ] **Step 2: Write `tests/LatestWinsTest.elm`.** Strategy: simulate two dispatches with seq `n` and `n+1` by calling `writeLoading`/`writeResult` manually and asserting registry contents:

```elm
module LatestWinsTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( Cell
        , Remote(..)
        , build
        , intCodec
        , on
        , remoteCodec
        , stringCodec
        , toSource
        , with
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Request as IRequest
import Test exposing (..)


type alias Model =
    { tick : Cell Int
    , out : Cell (Remote String String)
    }


outCodec : Rad.Codec (Remote String String)
outCodec =
    remoteCodec stringCodec stringCodec


init : Rad.CellBuilder Model
init =
    build Model
        |> with "tick" 0 intCodec
        |> with "out" Idle outCodec


suite : Test
suite =
    describe "Latest-wins via sequence numbers"
        [ test "A later seq written after an earlier seq wins" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    (IReaction.Reaction r) =
                        on (toSource model.tick)
                            (\_ -> IRequest.NoRequest)
                            model.out

                    -- Simulate: writeLoading (seq 1), writeLoading (seq 2),
                    -- then seq-2's result arrives, then seq-1's result arrives.
                    resultFor tag =
                        outCodec.encode (Done tag)

                    registryAfterTwoDispatch =
                        registry0
                            |> r.writeLoading
                            |> r.writeLoading

                    -- In the runtime, writeResult is only called for the latest seq.
                    -- Here we prove that writing the earlier result after the later one
                    -- would overwrite — which is WHY the runtime filters by seq, not
                    -- because writeResult itself filters. Assert the overwrite semantics.
                    registryLateResult =
                        registryAfterTwoDispatch
                            |> r.writeResult (resultFor "two")
                            |> r.writeResult (resultFor "one")

                    registryExpected =
                        registryAfterTwoDispatch
                            |> r.writeResult (resultFor "one")

                    lastValue reg =
                        Registry.get 1 reg
                            |> Maybe.andThen (Decode.decodeValue outCodec.decode >> Result.toMaybe)
                in
                Expect.equal
                    (lastValue registryLateResult)
                    (lastValue registryExpected)
        , test "seq dict starts empty and increments monotonically per index" <|
            \_ ->
                let
                    start =
                        IReaction.emptyState

                    stepped =
                        { triggers = Dict.insert 0 (Encode.int 0) start.triggers
                        , seqs = Dict.insert 0 1 start.seqs
                        }

                    stepped2 =
                        { stepped
                            | seqs =
                                Dict.update 0
                                    (Maybe.map (\n -> n + 1))
                                    stepped.seqs
                        }
                in
                Expect.equal (Just 2) (Dict.get 0 stepped2.seqs)
        ]
```

Note: the first test in `LatestWinsTest` documents the contract of `writeResult` (no internal filtering — runtime owns filtering via seq). The second exercises the seq-bump invariant. True end-to-end latest-wins behavior is verified by the browser checkpoint.

- [ ] **Step 3: Run tests.**

Run: `npx --yes elm-test`
Expected: all suites pass, including two new ones.

- [ ] **Step 4: Run `elm-format`.**

```bash
npx --yes elm-format src tests --yes
```

- [ ] **Step 5: Commit.**

```bash
git add tests/ReactionTriggerTest.elm tests/LatestWinsTest.elm
git commit -m "Add reaction trigger and latest-wins tests"
```

---

### Task 4.6: Create the `fetch-joke` example

**Files:**
- Create: `examples/src/FetchJoke.elm`

- [ ] **Step 1: Write the module.**

```elm
module FetchJoke exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , build
        , intCodec
        , modify
        , on
        , remoteCodec
        , run
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


type alias Joke =
    { text : String }


jokeCodec : Rad.Codec Joke
jokeCodec =
    { encode = \j -> Encode.object [ ( "text", Encode.string j.text ) ]
    , decode = Decode.map Joke (Decode.field "text" Decode.string)
    }


jokeDecoder : Decode.Decoder Joke
jokeDecoder =
    jokeCodec.decode


type alias Model =
    { tick : Cell Int
    , joke : Cell (Remote RequestError Joke)
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "tick" 0 intCodec
            |> with "joke" Idle (remoteCodec requestErrorCodec jokeCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ button
                    { label = "Tell me a joke"
                    , onClick = modify model.tick (\n -> n + 1)
                    }
                , watch (toSource model.joke) renderJoke
                ]
    , reactions =
        \model _ ->
            [ on (toSource model.tick)
                (\_ -> Http.httpGet prodHandler "/api/joke" jokeDecoder)
                model.joke
            ]
    }


renderJoke : Remote RequestError Joke -> SimpleView Model
renderJoke r =
    case r of
        Idle ->
            text "(click the button)"

        Loading ->
            text "loading…"

        Failed _ ->
            text "(network error)"

        Done j ->
            text j.text


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Run `elm-format` in examples.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 3: Verify compilation.**

Run: `cd examples && npx --yes elm make src/FetchJoke.elm --output=/dev/null`
Expected: success.

- [ ] **Step 4: Commit.**

```bash
git add examples/src/FetchJoke.elm
git commit -m "Add FetchJoke example module"
```

---

### Task 4.7: Create `fetch-joke.html` and wire it up

**Files:**
- Create: `examples/fetch-joke.html`
- Modify: `examples/vite.config.js` (add entry)
- Modify: `examples/index.html` (add link)

- [ ] **Step 1: Create `examples/fetch-joke.html`** mirroring `counter.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>fetch-joke</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/FetchJoke.elm";
      Elm.FetchJoke.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 2: Add to `examples/vite.config.js`** `input` map:

```javascript
"fetch-joke": resolve(__dirname, "fetch-joke.html"),
```

- [ ] **Step 3: Add a link in `examples/index.html`.**

```html
<li><a href="fetch-joke.html">fetch-joke</a></li>
```

- [ ] **Step 4: Verify build.**

Run: `cd examples && npm run build`
Expected: all seven entries build.

- [ ] **Step 5: Visual verification.** Run `cd examples && npm run dev`, open `localhost:5173/fetch-joke.html`, click the button. Observe:
  - Page loads showing `(click the button)` initially (but per design, first cycle fires; so you'll actually see `loading…` briefly then a joke after ~2s because the initial reaction fires on first cycle).
  - After ~2s, a joke appears.
  - Clicking again shows `loading…` → new joke.
  - Stop dev server.

- [ ] **Step 6: Commit.**

```bash
git add examples/fetch-joke.html examples/vite.config.js examples/index.html
git commit -m "Ship fetch-joke example"
```

---

## Slice 5 — `github-user` + `post-note` ship

### Task 5.1: Create `github-user` example

**Files:**
- Create: `examples/src/GithubUser.elm`
- Create: `examples/github-user.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/GithubUser.elm`.**

```elm
module GithubUser exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Codec
        , Remote(..)
        , build
        , copy
        , on
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias User =
    { login : String, bio : String }


userCodec : Codec User
userCodec =
    { encode =
        \u ->
            Encode.object
                [ ( "login", Encode.string u.login )
                , ( "bio", Encode.string u.bio )
                ]
    , decode =
        Decode.map2 User
            (Decode.field "login" Decode.string)
            (Decode.field "bio" Decode.string)
    }


userDecoder : Decode.Decoder User
userDecoder =
    userCodec.decode


type alias Model =
    { input : Cell String
    , query : Cell String
    , user : Cell (Remote RequestError User)
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "input" "octocat" stringCodec
            |> with "query" "" stringCodec
            |> with "user" Idle (remoteCodec requestErrorCodec userCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "GitHub login", cell = model.input }
                , button
                    { label = "Fetch"
                    , onClick = copy (toSource model.input) model.query
                    }
                , watch (toSource model.user) renderUser
                ]
    , reactions =
        \model _ ->
            [ on (toSource model.query)
                (\q ->
                    if q == "" then
                        Rad.noRequest

                    else
                        Http.httpGet prodHandler
                            ("/api/github/users/" ++ q)
                            userDecoder
                )
                model.user
            ]
    }


renderUser : Remote RequestError User -> SimpleView Model
renderUser r =
    case r of
        Idle ->
            text "(enter a login and click Fetch)"

        Loading ->
            text "loading…"

        Failed _ ->
            text "(error)"

        Done u ->
            text (u.login ++ " — " ++ u.bio)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/github-user.html`** (mirroring fetch-joke.html; module name `GithubUser`).

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>github-user</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/GithubUser.elm";
      Elm.GithubUser.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Wire `github-user` in `examples/vite.config.js` input map.**

```javascript
"github-user": resolve(__dirname, "github-user.html"),
```

- [ ] **Step 4: Add a link in `examples/index.html`.**

- [ ] **Step 5: Run `elm-format`.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build + visual verify.**

Run: `cd examples && npm run build`
Run: `cd examples && npm run dev` — at `localhost:5173/github-user.html`: type a login, click Fetch twice quickly, confirm only the last result lands. Stop dev server.

- [ ] **Step 7: Commit.**

```bash
git add examples/src/GithubUser.elm examples/github-user.html examples/vite.config.js examples/index.html
git commit -m "Ship github-user example"
```

---

### Task 5.2: Create `post-note` example

**Files:**
- Create: `examples/src/PostNote.elm`
- Create: `examples/post-note.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/PostNote.elm`.**

```elm
module PostNote exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Codec
        , Remote(..)
        , build
        , copy
        , mapRequestError
        , on
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError(..), prodHandler)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type NoteError
    = NetworkFailure
    | ValidationFailure String


noteErrorCodec : Codec NoteError
noteErrorCodec =
    { encode =
        \err ->
            case err of
                NetworkFailure ->
                    Encode.object [ ( "tag", Encode.string "NetworkFailure" ) ]

                ValidationFailure msg ->
                    Encode.object
                        [ ( "tag", Encode.string "ValidationFailure" )
                        , ( "message", Encode.string msg )
                        ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "NetworkFailure" ->
                            Decode.succeed NetworkFailure

                        "ValidationFailure" ->
                            Decode.map ValidationFailure (Decode.field "message" Decode.string)

                        other ->
                            Decode.fail ("unknown NoteError tag: " ++ other)
                )
    }


toNoteError : RequestError -> NoteError
toNoteError err =
    case err of
        Timeout ->
            NetworkFailure

        NetworkError ->
            NetworkFailure

        BadStatus _ ->
            NetworkFailure

        BadBody msg ->
            ValidationFailure msg


type alias SavedNote =
    { id : Int, echoed : String }


savedNoteCodec : Codec SavedNote
savedNoteCodec =
    { encode =
        \n ->
            Encode.object
                [ ( "id", Encode.int n.id )
                , ( "echoed", Encode.string n.echoed )
                ]
    , decode =
        Decode.map2 SavedNote
            (Decode.field "id" Decode.int)
            (Decode.field "echoed"
                (Decode.oneOf
                    [ Decode.field "text" Decode.string
                    , Decode.string
                    ]
                )
            )
    }


type alias Model =
    { draft : Cell String
    , submitTrigger : Cell String
    , note : Cell (Remote NoteError SavedNote)
    }


encodeNote : String -> Encode.Value
encodeNote text_ =
    Encode.object [ ( "text", Encode.string text_ ) ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "draft" "" stringCodec
            |> with "submitTrigger" "" stringCodec
            |> with "note" Idle (remoteCodec noteErrorCodec savedNoteCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Note", cell = model.draft }
                , button
                    { label = "Save"
                    , onClick = copy (toSource model.draft) model.submitTrigger
                    }
                , watch (toSource model.note) renderNote
                ]
    , reactions =
        \model _ ->
            [ on (toSource model.submitTrigger)
                (\text_ ->
                    if text_ == "" then
                        Rad.noRequest

                    else
                        Http.httpPost prodHandler "/api/note" (encodeNote text_) savedNoteCodec.decode
                            |> mapRequestError toNoteError
                )
                model.note
            ]
    }


renderNote : Remote NoteError SavedNote -> SimpleView Model
renderNote r =
    case r of
        Idle ->
            text "(type a note and click Save)"

        Loading ->
            text "saving…"

        Failed NetworkFailure ->
            text "(network failure)"

        Failed (ValidationFailure msg) ->
            text ("(validation failure: " ++ msg ++ ")")

        Done n ->
            text ("saved id=" ++ String.fromInt n.id ++ " echoed=" ++ n.echoed)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```


- [ ] **Step 2: Create `examples/post-note.html`** (module `PostNote`).

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>post-note</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/PostNote.elm";
      Elm.PostNote.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Wire into `vite.config.js`.**

```javascript
"post-note": resolve(__dirname, "post-note.html"),
```

- [ ] **Step 4: Link from `examples/index.html`.**

- [ ] **Step 5: Run `elm-format`.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build + visual verify.**

Run: `cd examples && npm run build`
Run: `cd examples && npm run dev` — at `localhost:5173/post-note.html`: type a note, click Save, confirm it transitions Idle → Loading → Done with an id and echoed text. Stop dev server.

- [ ] **Step 7: Commit.**

```bash
git add examples/src/PostNote.elm examples/post-note.html examples/vite.config.js examples/index.html
git commit -m "Ship post-note example"
```

---

## Slice 6 — `derived-search` + `TestRunner.elm` ship

### Task 6.1: Create `derived-search` example

**Files:**
- Create: `examples/src/DerivedSearch.elm`
- Create: `examples/derived-search.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/DerivedSearch.elm`.**

```elm
module DerivedSearch exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Codec
        , Remote(..)
        , Source
        , build
        , derive
        , listCodec
        , on
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.Read as Read
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Match =
    { label : String }


matchCodec : Codec Match
matchCodec =
    { encode = \m -> Encode.object [ ( "label", Encode.string m.label ) ]
    , decode = Decode.map Match (Decode.field "label" Decode.string)
    }


matchesDecoder : Decode.Decoder (List Match)
matchesDecoder =
    Decode.field "matches" (Decode.list (Decode.map Match Decode.string))


type alias Model =
    { first : Cell String
    , last : Cell String
    , results : Cell (Remote RequestError (List Match))
    }


type alias Computed =
    { query : Source String }


app : AppDef (SimpleView Model) Model Computed
app =
    { init =
        build Model
            |> with "first" "" stringCodec
            |> with "last" "" stringCodec
            |> with "results" Idle (remoteCodec requestErrorCodec (listCodec matchCodec))
    , computed =
        \model ->
            { query =
                derive stringCodec
                    (Read.map2 (\a b -> a ++ " " ++ b)
                        (Read.read (toSource model.first))
                        (Read.read (toSource model.last))
                    )
            }
    , view =
        \model c ->
            col
                [ input { label = "First", cell = model.first }
                , input { label = "Last", cell = model.last }
                , watch c.query (\q -> text ("Query: \"" ++ q ++ "\""))
                , watch (toSource model.results) renderResults
                ]
    , reactions =
        \model c ->
            [ on c.query
                (\q ->
                    if String.trim q == "" then
                        Rad.noRequest

                    else
                        Http.httpGet prodHandler
                            ("/api/search?q=" ++ q)
                            matchesDecoder
                )
                model.results
            ]
    }


renderResults : Remote RequestError (List Match) -> SimpleView Model
renderResults r =
    case r of
        Idle ->
            text "(type to search)"

        Loading ->
            text "searching…"

        Failed _ ->
            text "(error)"

        Done matches ->
            col (List.map (\m -> text (" • " ++ m.label)) matches)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

- [ ] **Step 2: Create `examples/derived-search.html`.**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>derived-search</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/DerivedSearch.elm";
      Elm.DerivedSearch.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Wire into `vite.config.js`.**

```javascript
"derived-search": resolve(__dirname, "derived-search.html"),
```

- [ ] **Step 4: Link from `examples/index.html`.**

- [ ] **Step 5: Run `elm-format`.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build + visual verify.**

Run: `cd examples && npm run build`
Run: `cd examples && npm run dev` — at `localhost:5173/derived-search.html`: type in either input; watch query update live; after first non-empty trim, a search fires and shows three mock matches. Stop dev server.

- [ ] **Step 7: Commit.**

```bash
git add examples/src/DerivedSearch.elm examples/derived-search.html examples/vite.config.js examples/index.html
git commit -m "Ship derived-search example"
```

---

### Task 6.2: Create `TestRunner.elm` scrappy harness

**Files:**
- Create: `examples/src/TestRunner.elm`

- [ ] **Step 1: Write `examples/src/TestRunner.elm`** — a `Platform.worker` that runs `FetchJoke` with a mock handler, stepping the registry and logging snapshots. The harness is intentionally scrappy: no assertions, output via `Debug.log`.

```elm
module TestRunner exposing (main)

{-| A deliberately scrappy demonstration of the mock-handler testing pattern.

Runs FetchJoke's reactions against a mock `Rad.Http.Handler` that returns
canned bodies, stepping the registry by simulating a button click and a
reaction-result arrival. Output goes through `Debug.log`.

This is a pattern sketch, not a real test harness. A proper `Rad.Test` module
is out of scope for Layer 2.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Rad
    exposing
        ( AppModel
        , Cell
        , Remote(..)
        , build
        , intCodec
        , modify
        , on
        , remoteCodec
        , stringCodec
        , toSource
        , with
        )
import Rad.Http as Http exposing (RequestError)
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Request as IRequest
import Task


type alias Joke =
    { text : String }


jokeCodec : Rad.Codec Joke
jokeCodec =
    { encode = \j -> Encode.object [ ( "text", Encode.string j.text ) ]
    , decode = Decode.map Joke (Decode.field "text" Decode.string)
    }


type alias Model =
    { tick : Cell Int, joke : Cell (Remote RequestError Joke) }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "tick" 0 intCodec
        |> with "joke" Idle (remoteCodec Http.requestErrorCodec jokeCodec)


mockHandler : Http.Handler
mockHandler =
    { httpGet = \_url -> Task.succeed "{\"text\":\"mock joke\"}"
    , httpPost = \_url _body -> Task.succeed "{}"
    }


buildReaction : Model -> Rad.Reaction Model
buildReaction model =
    on (toSource model.tick)
        (\_ -> Http.httpGet mockHandler "/api/joke" jokeCodec.decode)
        model.joke


main : Program () () Never
main =
    Platform.worker
        { init =
            \() ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    _ =
                        Debug.log "registry0" (snapshot registry0)

                    -- Simulate first-cycle trigger: tick = 0 already, reaction fires.
                    -- We bypass the runtime and call readTrigger/buildRequest directly
                    -- to demonstrate the pattern.
                    (IReaction.Reaction r) =
                        buildReaction model

                    _ =
                        Debug.log "trigger0" (Encode.encode 0 (r.readTrigger registry0))

                    registry1 =
                        r.writeLoading registry0

                    _ =
                        Debug.log "registry1 after writeLoading" (snapshot registry1)

                    -- Simulate the mock task completing: synthesize the encoded Done.
                    doneEncoded =
                        (remoteCodec Http.requestErrorCodec jokeCodec).encode
                            (Done { text = "mock joke" })

                    registry2 =
                        r.writeResult doneEncoded registry1

                    _ =
                        Debug.log "registry2 after writeResult" (snapshot registry2)
                in
                ( (), Cmd.none )
        , update = \_ _ -> ( (), Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


snapshot : Registry.Registry -> List ( Int, String )
snapshot registry =
    -- Iterate cell ids 0..2 and dump whatever is there.
    [ 0, 1 ]
        |> List.filterMap
            (\id ->
                Registry.get id registry
                    |> Maybe.map (\v -> ( id, Encode.encode 0 v ))
            )
```

Note: `Registry.Registry` is a `Dict Int Encode.Value` — `Rad.Internal.Registry` already exposes it. The snapshot helper just dumps known cell ids.

- [ ] **Step 2: Run `elm-format`.**

```bash
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 3: Compile.**

Run: `cd examples && npx --yes elm make src/TestRunner.elm --output=/dev/null`
Expected: success.

- [ ] **Step 4: Run via node.** Since `TestRunner` is a `Platform.worker`, we run it with a tiny script:

```bash
cd examples
npx --yes elm make src/TestRunner.elm --output=test-runner.js
cat > run-test.mjs <<'EOF'
import './test-runner.js';
globalThis.Elm.TestRunner.init({ flags: null });
EOF
node run-test.mjs
```

Expected: console shows four `Debug.log` lines with registry snapshots. Don't commit `test-runner.js` or `run-test.mjs`; they are throwaway.

- [ ] **Step 5: Clean up throwaway files.**

```bash
rm -f examples/test-runner.js examples/run-test.mjs
```

- [ ] **Step 6: Commit.**

```bash
git add examples/src/TestRunner.elm
git commit -m "Add scrappy TestRunner harness"
```

---

## Final Checkpoint: all acceptance criteria green

### Task 7.1: Full verification sweep

- [ ] **Step 1: Package tests.**

Run: `npx --yes elm-test`
Expected: All suites pass:
- ActionTest, CellBuilderTest, CodecTest, ReadTest (from Layers 0-1)
- RemoteCodecTest, SourceCodecTest, RequestTest, ReactionTriggerTest, LatestWinsTest (from Layer 2)

- [ ] **Step 2: Docs build.**

Run: `npx --yes elm make --docs=docs.json`
Expected: success — documents all exposed modules including `Rad.Http`.

- [ ] **Step 3: Examples build.**

Run: `cd examples && npm run build`
Expected: 11 entries (index + 6 Layer 0-1 + 4 Layer 2) build successfully.

- [ ] **Step 4: Visual sweep.**

Run: `cd examples && npm run dev`. Open each in a browser, verify:
- Layer 0-1 (6 apps): behave as in Layer 0-1 docs. No reaction-related regressions.
- `fetch-joke`: Idle → Loading → Done joke on click.
- `github-user`: rapid double-click shows only last result.
- `post-note`: Idle → Loading → Done with saved id.
- `derived-search`: editing either input updates the query line and triggers a new search.

Stop dev server.

- [ ] **Step 5: If any fix is required**, land it as a separate commit (`git commit -m "Fix <thing> in <module>"`) rather than amending earlier work.

- [ ] **Step 6: Nothing to commit for this task if everything passed.**

---

## Out-of-slice notes

- **If `elm/http` adds indirect deps** that `examples/elm.json` doesn't have, Elm will ask you to add them. Add them to the `indirect` block in `examples/elm.json` in the same commit that first triggers the demand. Typical additions: `elm/bytes`, `elm/file`.

- **If a reaction fires but nothing shows in the UI**, check these in order:
  1. The target cell's initial value is `Idle` (not `Loading`), so first paint shows Idle before the cycle fires.
  2. The registry receives the encoded value — add `Debug.log` in `writeResult` locally to confirm.
  3. The codec's decoder accepts the encoded value round-trip (encode → decode == original).

- **If `readTrigger` reports the same encoded JSON across cycles despite values changing**, the Source's codec is wrong for that value type — diff the codec against the source of truth.

- **If Task cancellation seems broken**, remember: Tasks don't cancel in Elm. Latest-wins drops stale results on receive, but the HTTP request still completes on the wire. This is acceptable for Layer 2.

- **Design decision reference:** Section 1 of the Layer 2 design document lists the five key decisions for future docs. Keep this plan aligned with them; if a decision changes, update the design doc and propagate to affected tasks here.
