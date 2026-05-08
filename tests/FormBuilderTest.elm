module FormBuilderTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.CellBuilder as ICellBuilder
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias BigModel =
    { n : Rad.Cell Int
    , v : Rad.ValidatedCell String String
    , st : Rad.Cell Form.State
    }


initBig : Rad.CellBuilder BigModel
initBig =
    build (\n v st -> { n = n, v = v, st = st })
        |> Rad.with "n" 7 Rad.intCodec
        |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


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
        , test "Form.over captures fields and members" <|
            \_ ->
                let
                    ( m, _ ) =
                        Rad.runBuilder initBig

                    f =
                        Form.over m.st { n = m.n, v = m.v } [ Form.field m.n, Form.validatedField m.v ]
                in
                Expect.equal 2 (Form.memberCount f)
        , test "Form.reactions returns one Reaction per ValidatedMember (none for PlainMember)" <|
            \_ ->
                let
                    initR =
                        build (\n v st -> { n = n, v = v, st = st })
                            |> Rad.with "n" 0 Rad.intCodec
                            |> Rad.withValidated "v" "" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
                            |> Form.withState "form"

                    ( model_, _ ) =
                        Rad.runBuilder initR

                    f =
                        Form.over model_.st
                            { v = model_.v }
                            [ Form.field model_.n, Form.validatedField model_.v ]
                in
                Expect.equal 1 (List.length (Form.reactions f))
        , test "Form.withState appends a persist schema entry with the form's key" <|
            \_ ->
                let
                    initF =
                        build Model |> Form.withState "profile-form"

                    (ICellBuilder.CellBuilder f) =
                        initF

                    result =
                        f { nextId = 0, prefix = "" }
                in
                case result.persist of
                    [ entry ] ->
                        Expect.equal ( "profile-form", "cell" ) ( entry.key, entry.typeTag )

                    _ ->
                        Expect.fail "expected exactly one persist entry"
        , test "Form.stateCodec.decode tolerates null and produces initialState" <|
            \_ ->
                let
                    decoded =
                        Decode.decodeValue Form.stateCodec.decode Encode.null
                in
                Expect.equal
                    (Ok
                        { snapshot = Encode.null
                        , submitSeq = 0
                        , lastResolvedSubmitSeq = 0
                        }
                    )
                    decoded
        ]
