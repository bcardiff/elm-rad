module L04E01_RequiredName exposing (main)

import Json.Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , ValidatedCell
        , Validation(..)
        , Validator
        , build
        , resetValidation
        , run
        , stringCodec
        , sync
        , validate
        , validation
        , validationReactions
        , withValidated
        )
import Rad.Internal.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Model =
    { name : ValidatedCell String String }


nameValidator : Validator String String
nameValidator =
    sync
        (\s ->
            if String.trim s == "" then
                Err [ "name required" ]

            else
                Ok s
        )


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "name" "" stringCodec stringCodec nameValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = Rad.input model.name }
                , button { label = "Validate", onClick = validate model.name }
                , button { label = "Reset", onClick = resetValidation model.name }
                , watch (validation model.name) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.name
    , persist = Nothing
    }


renderValidation : Validation String String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ looks good"

        Invalid errs ->
            text ("× " ++ String.join ", " errs)


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
