module ActionTest exposing (suite)

import Expect
import Rad exposing (Cell, build, set, stringCodec, with)
import Test exposing (..)


type alias Model =
    { name : Cell String }


init : Rad.CellBuilder Model
init =
    build Model |> with "name" "alice" stringCodec


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
        ]
