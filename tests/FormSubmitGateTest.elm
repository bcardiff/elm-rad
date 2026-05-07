module FormSubmitGateTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (Remote(..), build)
import Rad.Form as Form
import Rad.Http as Http
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Fields =
    { name : Rad.ValidatedCell String String }


type alias Model =
    { name : Rad.ValidatedCell String String
    , submitResult : Rad.Cell (Remote Http.RequestError ())
    , formState : Rad.Cell Form.State
    }


unitCodec : Rad.Codec ()
unitCodec =
    { encode = \_ -> Encode.null
    , decode = Decode.null ()
    }


resultCodec : Rad.Codec (Remote Http.RequestError ())
resultCodec =
    Rad.remoteCodec Http.requestErrorCodec unitCodec


init =
    build Model
        |> Rad.withValidated "name" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Rad.with "result" Idle resultCodec
        |> Form.withState "form"


buildForm m =
    Form.over m.formState { name = m.name } [ Form.validatedField m.name ]


setValid vcell encodedValue registry =
    Registry.insert
        (.validationId (IValidated.ref vcell))
        (Encode.object [ ( "tag", Encode.string "Valid" ), ( "value", encodedValue ) ])
        registry


suite : Test
suite =
    describe "Form.onSubmit"
        [ test "SkipRequest when submitSeq <= lastResolvedSubmitSeq" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        setValid m.name (Encode.string "alice") r0

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noRequest)
                            m.submitResult
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest"
        , test "SkipRequest when submit pending but validation not yet Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Rad.applyAction (Form.submit (buildForm m)) r0

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noRequest)
                            m.submitResult
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest"
        , test "SkipRequest when toRequest returns noRequest even with submit + Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> setValid m.name (Encode.string "alice")

                    react =
                        Form.onSubmit (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noRequest)
                            m.submitResult
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.SkipRequest ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected SkipRequest (toRequest returned noRequest)"
        , test "Form.onValid: SkipRequest when not all Valid; DispatchTask sentinel when all Valid + submit pending" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> Rad.applyAction (Form.submit (buildForm m))
                            |> setValid m.name (Encode.string "alice")

                    react =
                        Form.onValid (buildForm m)
                            (Form.validators1 .name)
                            (\_ -> Rad.noAction)
                in
                case react of
                    IReaction.Reaction g ->
                        case g.buildRequest r1 of
                            IReaction.DispatchTask _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "expected DispatchTask"
        ]
