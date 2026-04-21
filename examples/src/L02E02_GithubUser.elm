module L02E02_GithubUser exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Codec
        , Remote(..)
        , build
        , copy
        , on
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias User =
    { login : String, bio : String }


userCodec : Codec User
userCodec =
    { encode =
        \u ->
            Encode.object
                [ ( "login", Encode.string u.login )
                , ( "bio", Encode.string u.bio )
                ]
    , decode =
        Decode.map2 User
            (Decode.field "login" Decode.string)
            (Decode.field "bio" Decode.string)
    }


userDecoder : Decode.Decoder User
userDecoder =
    userCodec.decode


type alias Model =
    { input : Cell String
    , query : Cell String
    , user : Cell (Remote RequestError User)
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "input" "octocat" stringCodec
            |> with "query" "" stringCodec
            |> with "user" Idle (remoteCodec requestErrorCodec userCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "GitHub login", cell = model.input }
                , button
                    { label = "Fetch"
                    , onClick = copy (toSource model.input) model.query
                    }
                , watch (toSource model.user) renderUser
                ]
    , reactions =
        \model _ ->
            [ on (toSource model.query)
                (\q ->
                    if q == "" then
                        Rad.noRequest

                    else
                        Http.httpGet prodHandler
                            ("/api/github/users/" ++ q)
                            userDecoder
                )
                model.user
            ]
    }


renderUser : Remote RequestError User -> SimpleView Model
renderUser r =
    case r of
        Idle ->
            text "(enter a login and click Fetch)"

        Loading ->
            text "loading…"

        Failed _ ->
            text "(error)"

        Done u ->
            text (u.login ++ " — " ++ u.bio)


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
