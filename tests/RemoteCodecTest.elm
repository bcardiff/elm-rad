module RemoteCodecTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad exposing (Remote(..), intCodec, remoteCodec, stringCodec)
import Test exposing (..)


type alias Codec a =
    { encode : a -> Decode.Value, decode : Decode.Decoder a }


roundTrip : Codec a -> a -> Result Decode.Error a
roundTrip codec v =
    codec.encode v |> Decode.decodeValue codec.decode


suite : Test
suite =
    let
        c =
            remoteCodec stringCodec intCodec
    in
    describe "remoteCodec"
        [ test "round-trips Idle" <|
            \_ -> roundTrip c Idle |> Expect.equal (Ok Idle)
        , test "round-trips Loading" <|
            \_ -> roundTrip c Loading |> Expect.equal (Ok Loading)
        , test "round-trips Failed" <|
            \_ -> roundTrip c (Failed "nope") |> Expect.equal (Ok (Failed "nope"))
        , test "round-trips Done" <|
            \_ -> roundTrip c (Done 42) |> Expect.equal (Ok (Done 42))
        , test "nested remoteCodec round-trips" <|
            \_ ->
                let
                    nested =
                        remoteCodec stringCodec (remoteCodec stringCodec intCodec)
                in
                roundTrip nested (Done (Done 7))
                    |> Expect.equal (Ok (Done (Done 7)))
        ]
