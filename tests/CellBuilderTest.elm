module CellBuilderTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Cell, build, intCodec, stringCodec, with)
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { name : Cell String
    , age : Cell Int
    }


suite : Test
suite =
    describe "CellBuilder"
        [ test "registry has one entry per cell at their declared initial value" <|
            \_ ->
                let
                    ( _, registry ) =
                        Rad.runBuilder init

                    decoded =
                        ( Registry.get 0 registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)
                        , Registry.get 1 registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                        )
                in
                Expect.equal ( Just "alice", Just 30 ) decoded
        , test "toSource reads the current value of a cell from the registry" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    source =
                        Rad.toSource model.name
                in
                Expect.equal "alice" (Rad.readSource source registry)
        ]


init : Rad.CellBuilder Model
init =
    build Model
        |> with "name" "alice" stringCodec
        |> with "age" 30 intCodec
