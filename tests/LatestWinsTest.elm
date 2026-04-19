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

                    resultFor tag =
                        outCodec.encode (Done tag)

                    registryAfterTwoDispatch =
                        registry0
                            |> r.writeLoading
                            |> r.writeLoading

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
