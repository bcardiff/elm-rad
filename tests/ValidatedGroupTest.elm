module ValidatedGroupTest exposing (suite)

import Expect
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Form as Form
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { a : Rad.ValidatedCell String String
    , b : Rad.ValidatedCell String Int
    , formState : Rad.Cell Form.State
    }


init =
    build Model
        |> Rad.withValidated "a" "alpha" Rad.stringCodec Rad.stringCodec (Rad.sync Ok)
        |> Rad.withValidated "b" 7 Rad.intCodec Rad.stringCodec (Rad.sync Ok)
        |> Form.withState "form"


setValid vcell encodedValue registry =
    let
        ref =
            IValidated.ref vcell

        validEncoded =
            Encode.object [ ( "tag", Encode.string "Valid" ), ( "value", encodedValue ) ]
    in
    Registry.insert ref.validationId validEncoded registry


setInvalid vcell registry =
    let
        ref =
            IValidated.ref vcell

        invalidEncoded =
            Encode.object
                [ ( "tag", Encode.string "Invalid" )
                , ( "errors", Encode.list Encode.string [ "bad" ] )
                ]
    in
    Registry.insert ref.validationId invalidEncoded registry


suite : Test
suite =
    describe "ValidatedGroup"
        [ test "validators1 returns Just a when Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        setValid m.a (Encode.string "hello") r0
                in
                Expect.equal (Just "hello")
                    (Form.readGroup (Form.validators1 .a) { a = m.a, b = m.b } r1)
        , test "validators1 returns Nothing when Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        setInvalid m.a r0
                in
                Expect.equal Nothing
                    (Form.readGroup (Form.validators1 .a) { a = m.a, b = m.b } r1)
        , test "validators2 returns Just (a, b) when both Valid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setValid m.b (Encode.int 99)
                in
                Expect.equal (Just ( "alpha", 99 ))
                    (Form.readGroup (Form.validators2 .a .b) { a = m.a, b = m.b } r1)
        , test "validators2 returns Nothing when one Invalid" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setInvalid m.b
                in
                Expect.equal Nothing
                    (Form.readGroup (Form.validators2 .a .b) { a = m.a, b = m.b } r1)
        , test "mapValidated transforms the clean tuple" <|
            \_ ->
                let
                    ( m, r0 ) =
                        Rad.runBuilder init

                    r1 =
                        r0
                            |> setValid m.a (Encode.string "alpha")
                            |> setValid m.b (Encode.int 5)

                    group =
                        Form.validators2 .a .b
                            |> Form.mapValidated (\( a, b ) -> { name = a, count = b })
                in
                Expect.equal (Just { name = "alpha", count = 5 })
                    (Form.readGroup group { a = m.a, b = m.b } r1)
        ]
