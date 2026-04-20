module DebouncedLatestWinsTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (DebouncedCell, build, stringCodec, withDebounced)
import Rad.Internal.Debounced as IDebounced
import Test exposing (..)


type alias Model =
    { text : DebouncedCell String }


init : Rad.CellBuilder Model
init =
    build Model |> withDebounced "text" 800 "hello" stringCodec


suite : Test
suite =
    describe "Debounced latest-wins"
        [ test "a stale timer fire (seq < current) is a no-op" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    -- Write "a" → seq 1, write "b" → seq 2.
                    ( registry1, seq1 ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, _ ) =
                        IDebounced.applyInput r (Encode.string "b") registry1

                    -- Stale fire for seq 1 — current is 2; should no-op.
                    registry3 =
                        IDebounced.applyTimerFire r seq1 registry2
                in
                Expect.equal
                    { raw = "b", settled = "hello" }
                    { raw = Rad.readSource (Rad.raw model.text) registry3
                    , settled = Rad.readSource (Rad.settled model.text) registry3
                    }
        , test "a current timer fire (seq == current) copies raw to settled" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    ( registry1, _ ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, seq2 ) =
                        IDebounced.applyInput r (Encode.string "b") registry1

                    registry3 =
                        IDebounced.applyTimerFire r seq2 registry2
                in
                Expect.equal
                    { raw = "b", settled = "b" }
                    { raw = Rad.readSource (Rad.raw model.text) registry3
                    , settled = Rad.readSource (Rad.settled model.text) registry3
                    }
        , test "applyInput bumps timerSeq monotonically" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    r =
                        IDebounced.ref model.text

                    ( _, seq1 ) =
                        IDebounced.applyInput r (Encode.string "a") registry0

                    ( registry2, seq2 ) =
                        IDebounced.applyInput r
                            (Encode.string "b")
                            (IDebounced.applyInput r (Encode.string "a") registry0 |> Tuple.first)

                    ( _, seq3 ) =
                        IDebounced.applyInput r (Encode.string "c") registry2
                in
                Expect.equal ( seq1, seq2, seq3 ) ( 1, 2, 3 )
        ]
