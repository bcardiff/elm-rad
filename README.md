# elm-rad

A declarative DSL for building Elm applications as a reactive graph of **cells**, **sources**, and **reactions** — no hand-written `Msg` types, `update` branches, or `subscriptions`.

The runtime interprets your graph into a standard Elm `Program`. Cells hold state, sources are read-only views of state, and reactions turn cell changes into effects. Codecs travel with cells so persistence is structural.

> **Status:** all layers of the [design doc](docs/design-elm-rad.md) are shipped — cells, sources, actions, reactions, HTTP, debouncing, validation, forms, components, persistence. See the design doc's *Future Work* section for what's beyond the current scope (ListOf, routing, animation).

## A first taste — `L01E02_Greeting`

An input bound to a cell; a watch that re-renders whenever the cell changes. No `Msg`, no `update`.

```elm
module L01E02_Greeting exposing (main)

import Rad exposing (AppDef, AppModel, Cell, build, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { name : Cell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "name" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = model.name }
                , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

## Async with debounce — `L03E02_SearchDebounced`

A `DebouncedCell` exposes two sources: `raw` (every keystroke) and `settled` (after the debounce fires). A reaction watches `settled`, issues an HTTP request, and writes the `Remote` result into another cell. Latest-wins is enforced by the runtime.

```elm
module L03E02_SearchDebounced exposing (main)

import Json.Decode as Decode
import Rad
    exposing
        ( AppDef, AppModel, Cell, DebouncedCell, Remote(..)
        , build, listCodec, on, remoteCodec, run, stringCodec
        , with, withDebounced
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.View exposing (CommitTrigger(..))
import SimpleView exposing (SimpleView, col, debouncedInput, simpleViewEngine, text, watch)


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
                , watch (Rad.settled model.query) (\q -> text ("settled: \"" ++ q ++ "\""))
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
        Idle      -> text "(type to search)"
        Loading   -> text "searching…"
        Failed _  -> text "(error)"
        Done ms   -> col (List.map (\m -> text (" • " ++ m)) ms)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

## Running the examples

```sh
cd examples
npm install
npm run dev
```

See [`examples/`](examples/) for the full set: counter, swap, derived reads, custom triggers, validated inputs, username-available check, component instances, tag pickers, and more.

## Modules

- `Rad` — public API: `build`, `with`, `withDebounced`, `withValidated`, `on`, `run`, codecs, actions, components, `PersistConfig`/`persistNow`.
- `Rad.Form` — orthogonal form layer: snapshot/dirty/reset, submit gating with typed clean values, status helpers.
- `Rad.Engine` — `Msg`, `ViewEngine`, and the glue for custom view backends.
- `Rad.View` — an HTML view engine and reactive primitives.
- `Rad.Read` — the `Read` monad for computed values.
- `Rad.Http` — HTTP request builders that plug into reactions.

## Design

The full design rationale and layer-by-layer spec lives in [`docs/design-elm-rad.md`](docs/design-elm-rad.md). Implementation plans per layer are in [`docs/plans/`](docs/plans).

## License

MIT.
