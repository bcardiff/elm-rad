module WizardStep exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ValidatedCell
        , build
        , intCodec
        , modify
        , run
        , stringCodec
        , sync
        , toSource
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Fields =
    { name : ValidatedCell String String }


type alias Model =
    { name : ValidatedCell String String
    , step : Cell Int
    , formState : Cell Form.State
    }


nameValidator : Rad.Validator String String
nameValidator =
    sync
        (\s ->
            if String.length s >= 3 then
                Ok s

            else
                Err [ "Name must be at least 3 characters" ]
        )


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState { name = m.name } [ Form.validatedField m.name ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
            |> with "step" 1 intCodec
            |> Form.withState "step-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.step) (\s -> text ("Step " ++ String.fromInt s))
                , input { label = "Your name", cell = Rad.input model.name }
                , button { label = "Next →", onClick = Form.submit (theForm model) }
                , watch (Form.status (theForm model)) renderHint
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onValid (theForm model)
                        (Form.validators1 .name)
                        (\_ -> modify model.step (\n -> n + 1))
                   ]
    }


renderHint : Status -> SimpleView Model
renderHint status =
    case status of
        HasErrors ->
            text "(Need at least 3 characters)"

        Validating ->
            text "(checking...)"

        Submitting ->
            text "(advancing...)"

        _ ->
            text ""


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
