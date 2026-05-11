module L05E03_Signup exposing (main)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , ValidatedCell
        , andThenRequest
        , async
        , build
        , compose
        , remoteCodec
        , run
        , stringCodec
        , sync
        , toSource
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Model =
    { username : ValidatedCell String String
    , email : ValidatedCell String String
    , password : ValidatedCell String String
    , submitResult : Cell (Remote RequestError ())
    , formState : Cell Form.State
    }


type alias Fields =
    { username : ValidatedCell String String
    , email : ValidatedCell String String
    , password : ValidatedCell String String
    }


type alias SignupClean =
    { username : String
    , email : String
    , password : String
    }



-- Validators


atLeast : Int -> String -> String -> Result (List String) String
atLeast n msg s =
    if String.length s >= n then
        Ok s

    else
        Err [ msg ]


usernameValidator : Rad.Validator String String
usernameValidator =
    compose
        [ sync (atLeast 3 "Username must be at least 3 characters")
        , async checkUsernameAvailability
        ]


checkUsernameAvailability : String -> Rad.Request (List String) String
checkUsernameAvailability q =
    Http.httpGet prodHandler ("/api/username-check?q=" ++ q) availableDecoder
        |> Rad.mapRequestError (\_ -> [ "username check failed; try again" ])
        |> andThenRequest
            (\available ->
                if available then
                    Ok q

                else
                    Err [ "username unavailable" ]
            )


availableDecoder : Decoder Bool
availableDecoder =
    Decode.field "available" Decode.bool


emailValidator : Rad.Validator String String
emailValidator =
    sync
        (\s ->
            if String.contains "@" s && String.contains "." s then
                Ok s

            else
                Err [ "Must look like an email address" ]
        )


passwordValidator : Rad.Validator String String
passwordValidator =
    sync (atLeast 6 "Password must be at least 6 characters")



-- Codecs


unitCodec : Rad.Codec ()
unitCodec =
    { encode = \_ -> Encode.null
    , decode = Decode.null ()
    }


resultCodec : Rad.Codec (Remote RequestError ())
resultCodec =
    remoteCodec requestErrorCodec unitCodec



-- Form


fields : Model -> Fields
fields m =
    { username = m.username, email = m.email, password = m.password }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState
        (fields m)
        [ Form.validatedField m.username
        , Form.validatedField m.email
        , Form.validatedField m.password
        ]


signupGroup : Form.ValidatedGroup Fields SignupClean
signupGroup =
    Form.validators3 .username .email .password
        |> Form.mapValidated (\( u, e, p ) -> SignupClean u e p)



-- Submit request


submitRequest : SignupClean -> Rad.Request RequestError ()
submitRequest clean =
    Http.httpPost prodHandler
        "/api/signup"
        (Encode.object
            [ ( "username", Encode.string clean.username )
            , ( "email", Encode.string clean.email )
            , ( "password", Encode.string clean.password )
            ]
        )
        (Decode.succeed ())



-- App


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "username" "" stringCodec stringCodec usernameValidator
            |> withValidated "email" "" stringCodec stringCodec emailValidator
            |> withValidated "password" "" stringCodec stringCodec passwordValidator
            |> with "submit-result" Idle resultCodec
            |> Form.withState "signup-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Username", cell = Rad.input model.username }
                , watch (Rad.validation model.username) renderValidationHint
                , input { label = "Email", cell = Rad.input model.email }
                , watch (Rad.validation model.email) renderValidationHint
                , input { label = "Password", cell = Rad.input model.password }
                , watch (Rad.validation model.password) renderValidationHint
                , watch (Form.status (theForm model)) renderStatusHint
                , button { label = "Submit", onClick = Form.submit (theForm model) }
                , button { label = "Reset", onClick = Form.reset (theForm model) }
                , watch (toSource model.submitResult) renderResult
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onSubmit (theForm model)
                        signupGroup
                        submitRequest
                        model.submitResult
                   ]
    , persist = Nothing
    }



-- View helpers


renderValidationHint : Rad.Validation String String -> SimpleView Model
renderValidationHint v =
    case v of
        Rad.Dormant ->
            text ""

        Rad.Checking ->
            text "(checking...)"

        Rad.Valid _ ->
            text "✓"

        Rad.Invalid errs ->
            text (String.join "; " errs)


renderStatusHint : Status -> SimpleView Model
renderStatusHint status =
    case status of
        Pristine ->
            text ""

        Editable ->
            text "Ready to submit"

        HasErrors ->
            text "(fix errors before submitting)"

        Validating ->
            text "Checking..."

        Submitting ->
            text "Submitting..."


renderResult : Remote RequestError () -> SimpleView Model
renderResult r =
    case r of
        Idle ->
            text ""

        Loading ->
            text "Submitting..."

        Failed (Http.BadStatus 400) ->
            text "Sign-up failed: that username is reserved (try a different one)"

        Failed _ ->
            text "Sign-up failed (network/other error)"

        Done _ ->
            text "Welcome!"


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
