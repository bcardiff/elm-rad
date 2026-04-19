module SourceCodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Cell, build, derive, intCodec, stringCodec, toSource, with)
import Rad.Internal.Source as IS
import Rad.Read as Read
import Test exposing (..)


type alias Model =
    { n : Cell Int, s : Cell String }


init : Rad.CellBuilder Model
init =
    build Model
        |> with "n" 7 intCodec
        |> with "s" "hi" stringCodec


suite : Test
suite =
    describe "Source carries its codec"
        [ test "toSource pulls the cell's codec" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    source =
                        toSource model.n

                    encoded =
                        (IS.codec source).encode (Rad.readSource source registry)
                in
                Decode.decodeValue Decode.int encoded
                    |> Expect.equal (Ok 7)
        , test "derive threads the supplied codec" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    derived =
                        derive stringCodec
                            (Read.map (\n -> "n=" ++ String.fromInt n)
                                (Read.read (toSource model.n))
                            )

                    encoded =
                        (IS.codec derived).encode (Rad.readSource derived registry)
                in
                Decode.decodeValue Decode.string encoded
                    |> Expect.equal (Ok "n=7")
        ]
