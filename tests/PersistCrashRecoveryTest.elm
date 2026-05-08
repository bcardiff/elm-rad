module PersistCrashRecoveryTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (Remote(..), build)
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { v : Rad.ValidatedCell String String }


init =
    build Model
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)


suite : Test
suite =
    describe "Crash recovery — inFlight detection"
        [ test "validation reaction reports inFlight=True when validation slot is Checking" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            (Encode.object [ ( "tag", Encode.string "Checking" ) ])
                            r0

                    react =
                        case Rad.validationReactions m.v of
                            [ x ] ->
                                x

                            _ ->
                                Debug.todo "expected one reaction"
                in
                case react of
                    IReaction.Reaction g ->
                        Expect.equal True (g.inFlight r1)
        , test "validation reaction reports inFlight=False when validation slot is Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        Registry.insert
                            (.validationId (IValidated.ref m.v))
                            (Encode.object
                                [ ( "tag", Encode.string "Valid" )
                                , ( "value", Encode.string "x" )
                                ]
                            )
                            r0

                    react =
                        case Rad.validationReactions m.v of
                            [ x ] ->
                                x

                            _ ->
                                Debug.todo "expected one reaction"
                in
                case react of
                    IReaction.Reaction g ->
                        Expect.equal False (g.inFlight r1)
        , test "validation reaction reports inFlight=False when validation slot is Dormant" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    react =
                        case Rad.validationReactions m.v of
                            [ x ] ->
                                x

                            _ ->
                                Debug.todo "expected one reaction"
                in
                case react of
                    IReaction.Reaction g ->
                        Expect.equal False (g.inFlight r0)
        ]
