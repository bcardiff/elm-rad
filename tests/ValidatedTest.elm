module ValidatedTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( ValidatedCell
        , Validation(..)
        , Validator
        , build
        , stringCodec
        , sync
        , validationCodec
        , withValidated
        )
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : Validator String String
nameValidator =
    sync Ok


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec nameValidator


suite : Test
suite =
    describe "withValidated"
        [ test "allocates three Registry slots with correct initial values" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    r =
                        IValidated.ref model.name

                    decodeString id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)

                    decodeInt id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)

                    decodeValidation id =
                        Registry.get id registry
                            |> Maybe.andThen
                                (Decode.decodeValue
                                    (validationCodec stringCodec stringCodec).decode
                                    >> Result.toMaybe
                                )
                in
                Expect.equal
                    { input = Just "hello"
                    , validation = Just Dormant
                    , activationSeq = Just 0
                    }
                    { input = decodeString r.inputId
                    , validation = decodeValidation r.validationId
                    , activationSeq = decodeInt r.activationSeqId
                    }
        , test "IDs are distinct and sequential" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init

                    r =
                        IValidated.ref model.name
                in
                Expect.equal
                    { raw = r.inputId, settled = r.validationId, seq = r.activationSeqId }
                    { raw = 0, settled = 1, seq = 2 }
        , test "validationCodec round-trips Dormant" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode Dormant
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok Dormant)
        , test "validationCodec round-trips Checking" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode Checking
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok Checking)
        , test "validationCodec round-trips Valid" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode (Valid "yes")
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok (Valid "yes"))
        , test "validationCodec round-trips Invalid with multiple errors" <|
            \_ ->
                let
                    c =
                        validationCodec stringCodec stringCodec
                in
                c.encode (Invalid [ "oops", "again" ])
                    |> Decode.decodeValue c.decode
                    |> Expect.equal (Ok (Invalid [ "oops", "again" ]))
        ]
