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
