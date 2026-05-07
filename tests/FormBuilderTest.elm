module FormBuilderTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { profileForm : Rad.Cell Form.State }


init : Rad.CellBuilder Model
init =
    build Model |> Form.withState "profile-form"


suite : Test
suite =
    describe "Form.withState"
        [ test "allocates one Registry slot with the right initial state" <|
            \_ ->
                let
                    ( model, registry ) =
                        Rad.runBuilder init

                    decoded =
                        Registry.get (Rad.cellId model.profileForm) registry
                            |> Maybe.andThen (Decode.decodeValue Form.stateCodec.decode >> Result.toMaybe)
                in
                Expect.equal
                    (Just
                        { snapshot = Encode.null
                        , submitSeq = 0
                        , lastResolvedSubmitSeq = 0
                        }
                    )
                    decoded
        , test "the state cell's key carries the user-supplied namespace" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal "profile-form" (Rad.cellKey model.profileForm)
        ]
