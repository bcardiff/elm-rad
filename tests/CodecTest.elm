module CodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec)
import Test exposing (..)


suite : Test
suite =
    describe "Codec round-trips"
        [ test "stringCodec" <|
            \_ -> roundTrip stringCodec "hello" |> Expect.equal (Ok "hello")
        , test "intCodec" <|
            \_ -> roundTrip intCodec 42 |> Expect.equal (Ok 42)
        , test "floatCodec" <|
            \_ -> roundTrip floatCodec 3.14 |> Expect.equal (Ok 3.14)
        , test "boolCodec" <|
            \_ -> roundTrip boolCodec True |> Expect.equal (Ok True)
        , test "listCodec of strings" <|
            \_ -> roundTrip (listCodec stringCodec) [ "a", "b" ] |> Expect.equal (Ok [ "a", "b" ])
        , test "maybeCodec Just" <|
            \_ -> roundTrip (maybeCodec intCodec) (Just 7) |> Expect.equal (Ok (Just 7))
        , test "maybeCodec Nothing" <|
            \_ -> roundTrip (maybeCodec intCodec) Nothing |> Expect.equal (Ok Nothing)
        ]


roundTrip : { encode : a -> Decode.Value, decode : Decode.Decoder a } -> a -> Result Decode.Error a
roundTrip codec value =
    codec.encode value |> Decode.decodeValue codec.decode
