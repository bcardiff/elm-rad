module FormDirtyTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Fields =
    { n : Rad.Cell Int }


type alias Model =
    { n : Rad.Cell Int
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.with "n" 0 Rad.intCodec
        |> Form.withState "form"


buildForm : Model -> Form.Form Fields
buildForm m =
    Form.over m.formState { n = m.n } [ Form.field m.n ]


readDirty f registry =
    Rad.readSource (Form.dirty f) registry


suite : Test
suite =
    describe "Form.dirty"
        [ test "false initially (snapshot null, members at initial)" <|
            \_ ->
                let
                    ( m, registry ) =
                        Rad.runBuilder init
                in
                Expect.equal False (readDirty (buildForm m) registry)
        , test "true after a member's value diverges from initial" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        Rad.applyAction (Rad.set m.n 42) registry0
                in
                Expect.equal True (readDirty (buildForm m) registry1)
        , test "false again when value returns to initial" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    registry1 =
                        registry0
                            |> Rad.applyAction (Rad.set m.n 42)
                            |> Rad.applyAction (Rad.set m.n 0)
                in
                Expect.equal False (readDirty (buildForm m) registry1)
        , test "with non-null snapshot, dirty compares against snapshot value" <|
            \_ ->
                let
                    ( m, registry0 ) =
                        Rad.runBuilder init

                    snapshot =
                        Encode.object [ ( String.fromInt (Rad.cellId m.n), Encode.int 99 ) ]

                    newState =
                        { snapshot = snapshot, submitSeq = 0, lastResolvedSubmitSeq = 0 }

                    registry1 =
                        Registry.insert (Rad.cellId m.formState)
                            (Form.stateCodec.encode newState)
                            registry0

                    dirtyAtInitial =
                        readDirty (buildForm m) registry1

                    registry2 =
                        Rad.applyAction (Rad.set m.n 99) registry1

                    dirtyAtSnapshot =
                        readDirty (buildForm m) registry2
                in
                Expect.equal ( True, False ) ( dirtyAtInitial, dirtyAtSnapshot )
        ]
