module ActionTest exposing (suite)

import Expect
import Rad exposing (Cell, build, set, stringCodec, with)
import Test exposing (..)


type alias Model =
    { name : Cell String }


init : Rad.CellBuilder Model
init =
    build Model |> with "name" "alice" stringCodec


type alias TwoModel =
    { a : Cell String, b : Cell String }


twoInit : Rad.CellBuilder TwoModel
twoInit =
    build TwoModel
        |> with "a" "X" stringCodec
        |> with "b" "Y" stringCodec


suite : Test
suite =
    describe "Actions"
        [ test "set replaces the cell's value" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (set model.name "bob") registry0

                    source =
                        Rad.toSource model.name
                in
                Expect.equal "bob" (Rad.readSource source registry1)
        , test "modify applies a function to the cell's value" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (Rad.set model.name "hi") registry0

                    registry2 =
                        Rad.applyAction (Rad.modify model.name (\s -> s ++ "!")) registry1
                in
                Expect.equal "hi!" (Rad.readSource (Rad.toSource model.name) registry2)
        , test "copy reads source then writes to target" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder twoInit

                    registry1 =
                        Rad.applyAction (Rad.copy (Rad.toSource model.a) model.b) registry0
                in
                Expect.equal "X"
                    (Rad.readSource (Rad.toSource model.b) registry1)
        ]
