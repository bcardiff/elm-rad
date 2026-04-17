module ReadTest exposing (suite)

import Expect
import Rad exposing (Cell, build, stringCodec, with)
import Rad.Read as Read
import Test exposing (..)


type alias Model =
    { first : Cell String, last : Cell String }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "first" "ada" stringCodec
        |> with "last" "lovelace" stringCodec


suite : Test
suite =
    describe "Rad.Read"
        [ test "read returns the current value of a source" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "ada"
                    (Read.run (Read.read (Rad.toSource model.first)) registry)
        , test "map transforms the read value" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal "ADA"
                    (Read.run
                        (Read.map String.toUpper (Read.read (Rad.toSource model.first)))
                        registry
                    )
        , test "map2 combines two sources" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    combined =
                        Read.map2 (\f l -> f ++ " " ++ l)
                            (Read.read (Rad.toSource model.first))
                            (Read.read (Rad.toSource model.last))
                in
                Expect.equal "ada lovelace"
                    (Read.run combined registry)
        ]
