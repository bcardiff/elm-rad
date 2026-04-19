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
