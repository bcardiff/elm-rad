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
    { httpGet = \_ -> Task.succeed "{\"text\":\"mock joke\"}"
    , httpPost = \_ _ -> Task.succeed "{}"
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
