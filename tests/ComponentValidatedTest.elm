module ComponentValidatedTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( ComponentDef
        , ValidatedCell
        , Validation(..)
        , Validator
        , build
        , defineComponent
        , include
        , stringCodec
        , sync
        , validate
        , validationCodec
        , validationReactions
        , withInstance
        , withValidated
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias LoginCells =
    { username : ValidatedCell String String }


loginComponent : ComponentDef model () LoginCells {}
loginComponent =
    defineComponent
        { init =
            build LoginCells
                |> withValidated "username" "" stringCodec stringCodec (sync Ok)
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \cells _ -> validationReactions cells.username
        }


type alias Model =
    { login : LoginCells }


init : Rad.CellBuilder Model
init =
    build Model |> withInstance "login" loginComponent


suite : Test
suite =
    describe "Validated cells inside components"
        [ test "validated cell inside component is allocated at expected IDs" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init

                    ref =
                        IValidated.ref model.login.username
                in
                Expect.equal
                    { input = 0, validation = 1, activationSeq = 2 }
                    { input = ref.inputId
                    , validation = ref.validationId
                    , activationSeq = ref.activationSeqId
                    }
        , test "validated cell's initial values are registered correctly" <|
            \_ ->
                let
                    ( _, registry ) =
                        Rad.runBuilder init

                    decodeString id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.string >> Result.toMaybe)

                    decodeInt id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)

                    vc =
                        validationCodec stringCodec stringCodec

                    decodeValidation id =
                        Registry.get id registry
                            |> Maybe.andThen (Decode.decodeValue vc.decode >> Result.toMaybe)
                in
                Expect.equal
                    { input = Just "", validation = Just Dormant, activationSeq = Just 0 }
                    { input = decodeString 0
                    , validation = decodeValidation 1
                    , activationSeq = decodeInt 2
                    }
        , test "include returns the component's validationReactions" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 1 (List.length (include loginComponent model.login))
        , test "validate action dispatched at parent mutates the component's activationSeq slot" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.login.username) registry0

                    ref =
                        IValidated.ref model.login.username

                    seqAfter =
                        Registry.get ref.activationSeqId registry1
                            |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                in
                Expect.equal (Just 1) seqAfter
        , test "after validate, the component's reaction reports DispatchTask" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (validate model.login.username) registry0

                    reaction =
                        include loginComponent model.login |> List.head
                in
                case reaction of
                    Just (IReaction.Reaction r) ->
                        case r.buildRequest registry1 of
                            IReaction.DispatchTask _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected DispatchTask after validate"

                    Nothing ->
                        Expect.fail "component produced no reaction"
        ]
