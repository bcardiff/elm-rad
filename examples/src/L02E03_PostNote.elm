module L02E03_PostNote exposing (main)

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
        , mapRequestError
        , on
        , remoteCodec
        , run
        , stringCodec
        , toSource
        , with
        )
import Rad.Http as Http exposing (RequestError(..), prodHandler)
import Rad.Internal.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type NoteError
    = NetworkFailure
    | ValidationFailure String


noteErrorCodec : Codec NoteError
noteErrorCodec =
    { encode =
        \err ->
            case err of
                NetworkFailure ->
                    Encode.object [ ( "tag", Encode.string "NetworkFailure" ) ]

                ValidationFailure msg ->
                    Encode.object
                        [ ( "tag", Encode.string "ValidationFailure" )
                        , ( "message", Encode.string msg )
                        ]
    , decode =
        Decode.field "tag" Decode.string
            |> Decode.andThen
                (\tag ->
                    case tag of
                        "NetworkFailure" ->
                            Decode.succeed NetworkFailure

                        "ValidationFailure" ->
                            Decode.map ValidationFailure (Decode.field "message" Decode.string)

                        other ->
                            Decode.fail ("unknown NoteError tag: " ++ other)
                )
    }


toNoteError : RequestError -> NoteError
toNoteError err =
    case err of
        Timeout ->
            NetworkFailure

        NetworkError ->
            NetworkFailure

        BadStatus _ ->
            NetworkFailure

        BadBody msg ->
            ValidationFailure msg


type alias SavedNote =
    { id : Int, echoed : String }


savedNoteCodec : Codec SavedNote
savedNoteCodec =
    { encode =
        \n ->
            Encode.object
                [ ( "id", Encode.int n.id )
                , ( "echoed", Encode.string n.echoed )
                ]
    , decode =
        Decode.map2 SavedNote
            (Decode.field "id" Decode.int)
            (Decode.field "echoed"
                (Decode.oneOf
                    [ Decode.field "text" Decode.string
                    , Decode.string
                    ]
                )
            )
    }


type alias Model =
    { draft : Cell String
    , submitTrigger : Cell String
    , note : Cell (Remote NoteError SavedNote)
    }


encodeNote : String -> Encode.Value
encodeNote text_ =
    Encode.object [ ( "text", Encode.string text_ ) ]


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "draft" "" stringCodec
            |> with "submitTrigger" "" stringCodec
            |> with "note" Idle (remoteCodec noteErrorCodec savedNoteCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Note", cell = model.draft }
                , button
                    { label = "Save"
                    , onClick = copy (toSource model.draft) model.submitTrigger
                    }
                , watch (toSource model.note) renderNote
                ]
    , reactions =
        \model _ ->
            [ on (toSource model.submitTrigger)
                (\text_ ->
                    if text_ == "" then
                        Rad.noRequest

                    else
                        Http.httpPost prodHandler "/api/note" (encodeNote text_) savedNoteCodec.decode
                            |> mapRequestError toNoteError
                )
                model.note
            ]
    , persist = Nothing
    }


renderNote : Remote NoteError SavedNote -> SimpleView Model
renderNote r =
    case r of
        Idle ->
            text "(type a note and click Save)"

        Loading ->
            text "saving…"

        Failed NetworkFailure ->
            text "(network failure)"

        Failed (ValidationFailure msg) ->
            text ("(validation failure: " ++ msg ++ ")")

        Done n ->
            text ("saved id=" ++ String.fromInt n.id ++ " echoed=" ++ n.echoed)


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
