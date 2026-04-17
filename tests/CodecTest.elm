module CodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (boolCodec, floatCodec, intCodec, stringCodec)
import Test exposing (..)


suite : Test
suite =
    describe "Primitive codec round-trips"
        [ test "stringCodec" <|
            \_ -> roundTrip stringCodec "hello" |> Expect.equal (Ok "hello")
        , test "intCodec" <|
            \_ -> roundTrip intCodec 42 |> Expect.equal (Ok 42)
        , test "floatCodec" <|
            \_ -> roundTrip floatCodec 3.14 |> Expect.equal (Ok 3.14)
        , test "boolCodec" <|
            \_ -> roundTrip boolCodec True |> Expect.equal (Ok True)
        ]


roundTrip : { encode : a -> Decode.Value, decode : Decode.Decoder a } -> a -> Result Decode.Error a
roundTrip codec value =
    codec.encode value |> Decode.decodeValue codec.decode
