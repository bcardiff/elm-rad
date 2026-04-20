module ValidatedLifecycleTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( ValidatedCell
        , Validation(..)
        , build
        , resetValidation
        , stringCodec
        , sync
        , validate
        , validationCodec
        , withValidated
        )
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : Rad.Validator String String
nameValidator =
    sync Ok


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec nameValidator


readSeq : Int -> Registry.Registry -> Maybe Int
readSeq id registry =
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)


readValidation : Int -> Registry.Registry -> Maybe (Validation String String)
readValidation id registry =
    let
        c =
            validationCodec stringCodec stringCodec
    in
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue c.decode >> Result.toMaybe)


suite : Test
suite =
    describe "ValidatedCell lifecycle actions"
        [ test "validate increments activationSeqId from 0 to 1" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.name) registry0

                    r =
                        IValidated.ref model.name
                in
                Expect.equal (Just 1) (readSeq r.activationSeqId registry1)
        , test "two consecutive validate calls produce seq 2" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry2 =
                        registry0
                            |> Rad.applyAction (validate model.name)
                            |> Rad.applyAction (validate model.name)

                    r =
                        IValidated.ref model.name
                in
                Expect.equal (Just 2) (readSeq r.activationSeqId registry2)
        , test "resetValidation writes Dormant and resets seq to 0" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.name) registry0

                    registry2 =
                        Rad.applyAction (resetValidation model.name) registry1

                    r =
                        IValidated.ref model.name
                in
                Expect.equal
                    { seq = Just 0, state = Just Dormant }
                    { seq = readSeq r.activationSeqId registry2
                    , state = readValidation r.validationId registry2
                    }
        ]
