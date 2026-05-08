module ProfileForm exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , ValidatedCell
        , build
        , noRequest
        , remoteCodec
        , run
        , stringCodec
        , sync
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import Rad.Http exposing (RequestError, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Fields =
    { name : ValidatedCell String String
    , email : ValidatedCell String String
    , bio : Cell String
    }


type alias Model =
    { name : ValidatedCell String String
    , email : ValidatedCell String String
    , bio : Cell String
    , submitResult : Cell (Remote RequestError ())
    , formState : Cell Form.State
    }


nameValidator : Rad.Validator String String
nameValidator =
    sync
        (\s ->
            if String.trim s == "" then
                Err [ "Name is required" ]

            else
                Ok s
        )


emailValidator : Rad.Validator String String
emailValidator =
    sync
        (\s ->
            if String.contains "@" s then
                Ok s

            else
                Err [ "Invalid email" ]
        )


unitCodec : Rad.Codec ()
unitCodec =
    { encode = \_ -> Encode.null
    , decode = Decode.null ()
    }


resultCodec : Rad.Codec (Remote RequestError ())
resultCodec =
    remoteCodec requestErrorCodec unitCodec


fields : Model -> Fields
fields m =
    { name = m.name, email = m.email, bio = m.bio }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState
        (fields m)
        [ Form.validatedField m.name
        , Form.validatedField m.email
        , Form.field m.bio
        ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
            |> withValidated "email" "" stringCodec stringCodec emailValidator
            |> with "bio" "" stringCodec
            |> with "submit-result" Idle resultCodec
            |> Form.withState "profile-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = Rad.input model.name }
                , input { label = "Email", cell = Rad.input model.email }
                , input { label = "Bio", cell = model.bio }
                , watch (Form.status (theForm model)) renderStatusHint
                , watch (Form.dirty (theForm model))
                    (\d ->
                        text
                            (if d then
                                "* unsaved changes"

                             else
                                ""
                            )
                    )
                , button { label = "Submit", onClick = Form.submit (theForm model) }
                , button { label = "Reset", onClick = Form.reset (theForm model) }
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onSubmit (theForm model)
                        (Form.validators2 .name .email)
                        (\( _, _ ) -> noRequest)
                        model.submitResult
                   ]
    , persist = Nothing
    }


renderStatusHint : Status -> SimpleView Model
renderStatusHint status =
    case status of
        Pristine ->
            text "(Saved ✓)"

        Editable ->
            text "Click Submit when ready"

        HasErrors ->
            text "(Fix errors before submitting)"

        Validating ->
            text "Validating..."

        Submitting ->
            text "Submitting..."


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
