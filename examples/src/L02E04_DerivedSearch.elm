module L02E04_DerivedSearch exposing (main)

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
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.Internal.Engine exposing (Msg)
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
    , persist = Nothing
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


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
