module FormResetTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { n : Rad.Cell Int
    , v : Rad.ValidatedCell String String
    }


type alias Model =
    { n : Rad.Cell Int
    , v : Rad.ValidatedCell String String
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.with "n" 0 Rad.intCodec
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { n = m.n, v = m.v } [ Form.field m.n, Form.validatedField m.v ]


readState m registry =
    case Registry.get (Rad.cellId m.formState) registry of
        Just v ->
            Result.withDefault
                { snapshot = Encode.null, submitSeq = 0, lastResolvedSubmitSeq = 0 }
                (Decode.decodeValue Form.stateCodec.decode v)

        Nothing ->
            { snapshot = Encode.null, submitSeq = 0, lastResolvedSubmitSeq = 0 }


readActivationSeq vcell registry =
    Registry.get (.activationSeqId (IValidated.ref vcell)) registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
        |> Maybe.withDefault 0


suite : Test
suite =
    describe "Form.submit and Form.reset"
        [ test "submit bumps submitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0
                in
                Expect.equal 1 (.submitSeq (readState m r1))
        , test "submit bumps each ValidatedMember's activationSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0
                in
                Expect.equal 1 (readActivationSeq m.v r1)
        , test "reset restores members to initial when snapshot is null" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Rad.set m.n 42)
                            |> Rad.applyAction (Form.reset (buildForm m))
                in
                Expect.equal (Just (Encode.int 0)) (Registry.get (Rad.cellId m.n) r1)
        , test "reset zeros each ValidatedMember's activationSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Rad.validate m.v) r0

                    seqAfterValidate =
                        readActivationSeq m.v r1

                    r2 =
                        Rad.applyAction (Form.reset (buildForm m)) r1

                    seqAfterReset =
                        readActivationSeq m.v r2
                in
                Expect.equal ( 1, 0 ) ( seqAfterValidate, seqAfterReset )
        , test "reset does not modify submitSeq / lastResolvedSubmitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> Rad.applyAction (Form.reset (buildForm m))

                    s =
                        readState m r1
                in
                Expect.equal ( 1, 0 ) ( s.submitSeq, s.lastResolvedSubmitSeq )
        ]
