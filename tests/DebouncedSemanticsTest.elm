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
