module L03E02_SearchDebounced exposing (main)

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
        , with
        , withDebounced
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
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
