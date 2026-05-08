module FormSnapshotKeyTest exposing (suite)

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


buildForm m =
    Form.over m.formState { n = m.n } [ Form.field m.n ]


suite : Test
suite =
    describe "Form snapshot keyed by cell.key"
        [ test "Form.dirty reads snapshot keyed by Rad.cellKey not stringified id" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    snapshot =
                        Encode.object [ ( "n", Encode.int 99 ) ]

                    newState =
                        { snapshot = snapshot, submitSeq = 0, lastResolvedSubmitSeq = 0 }

                    r1 =
                        Registry.insert (Rad.cellId m.formState)
                            (Form.stateCodec.encode newState)
                            r0

                    dirty1 =
                        Rad.readSource (Form.dirty (buildForm m)) r1

                    r2 =
                        Rad.applyAction (Rad.set m.n 99) r1

                    dirty2 =
                        Rad.readSource (Form.dirty (buildForm m)) r2
                in
                Expect.equal ( True, False ) ( dirty1, dirty2 )
        ]
