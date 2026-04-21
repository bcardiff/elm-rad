module L04E03_UsernameAvailable exposing (main)

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
        , andThenRequest
        , async
        , build
        , compose
        , mapRequestError
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
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type UsernameError
    = EmptyName
    | AlreadyTaken
    | LookupFailed RequestError


usernameErrorCodec : Codec UsernameError
usernameErrorCodec =
    { encode =
        \err ->
            case err of
                EmptyName ->
                    Encode.object [ ( "tag", Encode.string "EmptyName" ) ]

                AlreadyTaken ->
                    Encode.object [ ( "tag", Encode.string "AlreadyTaken" ) ]

                LookupFailed reqErr ->
                    Encode.object
                        [ ( "tag", Encode.string "LookupFailed" )
                        , ( "cause", requestErrorCodec.encode reqErr )
                        ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "EmptyName" ->
                            Decode.succeed EmptyName

                        "AlreadyTaken" ->
                            Decode.succeed AlreadyTaken

                        "LookupFailed" ->
                            Decode.map LookupFailed
                                (Decode.field "cause" requestErrorCodec.decode)

                        other ->
                            Decode.fail ("unknown UsernameError tag: " ++ other)
                )
    }


availabilityDecoder : Decode.Decoder Bool
availabilityDecoder =
    Decode.field "available" Decode.bool


usernameValidator : Validator UsernameError String
usernameValidator =
    compose
        [ sync
            (\s ->
                if String.trim s == "" then
                    Err [ EmptyName ]

                else
                    Ok s
            )
        , async
            (\name ->
                Http.httpGet prodHandler
                    ("/api/username-check?q=" ++ name)
                    availabilityDecoder
                    |> mapRequestError (\netErr -> [ LookupFailed netErr ])
                    |> andThenRequest
                        (\available ->
                            if available then
                                Ok name

                            else
                                Err [ AlreadyTaken ]
                        )
            )
        ]


type alias Model =
    { username : ValidatedCell UsernameError String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "username" "" stringCodec usernameErrorCodec usernameValidator
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Username", cell = Rad.input model.username }
                , button { label = "Validate", onClick = validate model.username }
                , button { label = "Reset", onClick = resetValidation model.username }
                , watch (validation model.username) renderValidation
                ]
    , reactions =
        \model _ -> validationReactions model.username
    }


renderValidation : Validation UsernameError String -> SimpleView Model
renderValidation v =
    case v of
        Dormant ->
            text ""

        Checking ->
            text "checking…"

        Valid _ ->
            text "✓ available"

        Invalid errs ->
            text ("× " ++ String.join ", " (List.map humanize errs))


humanize : UsernameError -> String
humanize err =
    case err of
        EmptyName ->
            "username is required"

        AlreadyTaken ->
            "already taken"

        LookupFailed _ ->
            "lookup failed"


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
