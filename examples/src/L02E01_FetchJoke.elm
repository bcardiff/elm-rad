module L02E01_FetchJoke exposing (main)

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
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.Internal.Engine exposing (Msg)
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
    , persist = Nothing
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


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
