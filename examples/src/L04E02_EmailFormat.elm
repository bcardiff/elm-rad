module L04E02_EmailFormat exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Codec
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
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type EmailError
    = Empty
    | MissingAt
    | TooLong


emailErrorCodec : Codec EmailError
emailErrorCodec =
    { encode =
        \err ->
            case err of
                Empty ->
                    Encode.object [ ( "tag", Encode.string "Empty" ) ]

                MissingAt ->
                    Encode.object [ ( "tag", Encode.string "MissingAt" ) ]

                TooLong ->
                    Encode.object [ ( "tag", Encode.string "TooLong" ) ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "Empty" ->
                            Decode.succeed Empty

                        "MissingAt" ->
                            Decode.succeed MissingAt

                        "TooLong" ->
                            Decode.succeed TooLong

                        other ->
                            Decode.fail ("unknown EmailError tag: " ++ other)
                )
    }


emailValidator : Validator EmailError String
emailValidator =
    sync
        (\s ->
            let
                errs =
                    List.filterMap identity
                        [ if s == "" then
                            Just Empty

                          else
                            Nothing
                        , if not (String.contains "@" s) then
                            Just MissingAt

                          else
                            Nothing
                        , if String.length s > 100 then
                            Just TooLong

                          else
                            Nothing
                        ]
            in
            if List.isEmpty errs then
                Ok s

            else
                Err errs
        )


type alias Model =
    { email : ValidatedCell EmailError String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "email" "" stringCodec emailErrorCodec emailValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Email", cell = Rad.input model.email }
                , button { label = "Validate", onClick = validate model.email }
                , button { label = "Reset", onClick = resetValidation model.email }
                , watch (validation model.email) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.email
    , persist = Nothing
    }


renderValidation : Validation EmailError String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ looks good"

        Invalid errs ->
            text ("× " ++ String.join ", " (List.map humanize errs))


humanize : EmailError -> String
humanize err =
    case err of
        Empty ->
            "email is required"

        MissingAt ->
            "missing @"

        TooLong ->
            "too long"


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
