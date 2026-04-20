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
import Rad.Internal.Reaction as IReaction
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
        , test "validationReactions returns exactly one Reaction" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 1 (List.length (Rad.validationReactions model.name))
        , test "readTrigger is stable when input and seq don't change" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        Expect.equal
                            (Encode.encode 0 (r.readTrigger registry))
                            (Encode.encode 0 (r.readTrigger registry))

                    Nothing ->
                        Expect.fail "no reaction"
        , test "readTrigger changes when input changes" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head

                    registry1 =
                        Rad.applyAction
                            (Rad.set (Rad.input model.name) "world")
                            registry0
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        Expect.notEqual
                            (Encode.encode 0 (r.readTrigger registry0))
                            (Encode.encode 0 (r.readTrigger registry1))

                    Nothing ->
                        Expect.fail "no reaction"
        , test "readTrigger changes when activationSeq changes" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head

                    registry1 =
                        Rad.applyAction (Rad.validate model.name) registry0
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        Expect.notEqual
                            (Encode.encode 0 (r.readTrigger registry0))
                            (Encode.encode 0 (r.readTrigger registry1))

                    Nothing ->
                        Expect.fail "no reaction"
        , test "buildRequest returns SkipRequest when activationSeq is 0" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        case r.buildRequest registry of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest when activationSeq is 0"

                    Nothing ->
                        Expect.fail "no reaction"
        , test "buildRequest returns DispatchTask after validate" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head

                    registry1 =
                        Rad.applyAction (Rad.validate model.name) registry0
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        case r.buildRequest registry1 of
                            IReaction.DispatchTask _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected DispatchTask after validate"

                    Nothing ->
                        Expect.fail "no reaction"
        , test "writeLoading writes encoded Checking to validationId" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    reaction =
                        Rad.validationReactions model.name |> List.head
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        let
                            registry1 =
                                r.writeLoading registry0
                        in
                        Expect.equal (Just Checking)
                            (readValidation (IValidated.ref model.name).validationId registry1)

                    Nothing ->
                        Expect.fail "no reaction"
        ]
