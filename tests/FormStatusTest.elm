module FormStatusTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form exposing (Status(..))
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { v : Rad.ValidatedCell String String }


type alias Model =
    { v : Rad.ValidatedCell String String
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { v = m.v } [ Form.validatedField m.v ]


readStatus f registry =
    Rad.readSource (Form.status f) registry


readBool src registry =
    Rad.readSource src registry


suite : Test
suite =
    describe "Form status helpers"
        [ test "Pristine when not dirty + no submit pending + no validation issues" <|
            \_ ->
                let
                    ( m, r ) =
                        Rad.runBuilder init
                in
                Expect.equal Pristine (readStatus (buildForm m) r)
        , test "Editable when dirty and clean otherwise" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Rad.set (Rad.input m.v) "x") r0
                in
                Expect.equal Editable (readStatus (buildForm m) r1)
        , test "submitPending true after Form.submit" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    initialPending =
                        readBool (Form.submitPending (buildForm m)) r0

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0

                    afterPending =
                        readBool (Form.submitPending (buildForm m)) r1
                in
                Expect.equal ( False, True ) ( initialPending, afterPending )
        , test "canSubmit truth table" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    s0 =
                        readBool (Form.canSubmit (buildForm m)) r0

                    r1 =
                        Rad.applyAction (Rad.set (Rad.input m.v) "x") r0

                    s1 =
                        readBool (Form.canSubmit (buildForm m)) r1

                    r2 =
                        Rad.applyAction (Form.submit (buildForm m)) r1

                    s2 =
                        readBool (Form.canSubmit (buildForm m)) r2
                in
                Expect.equal ( False, True, False ) ( s0, s1, s2 )
        , test "HasErrors wins over Submitting when validation slot is Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    invalidEncoded =
                        Encode.object
                            [ ( "tag", Encode.string "Invalid" )
                            , ( "errors", Encode.list Encode.string [ "bad" ] )
                            ]

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            invalidEncoded
                            r0

                    state2 =
                        { snapshot = Encode.null, submitSeq = 1, lastResolvedSubmitSeq = 0 }

                    r2 =
                        Registry.insert (Rad.cellId m.formState) (Form.stateCodec.encode state2) r1
                in
                Expect.equal HasErrors (readStatus (buildForm m) r2)
        , test "Validating when submitPending and a validation slot is Checking" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    checkingEncoded =
                        Encode.object [ ( "tag", Encode.string "Checking" ) ]

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            checkingEncoded
                            r0

                    state2 =
                        { snapshot = Encode.null, submitSeq = 1, lastResolvedSubmitSeq = 0 }

                    r2 =
                        Registry.insert (Rad.cellId m.formState) (Form.stateCodec.encode state2) r1
                in
                Expect.equal Validating (readStatus (buildForm m) r2)
        ]
