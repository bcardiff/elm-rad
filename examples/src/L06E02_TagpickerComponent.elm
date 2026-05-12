module L06E02_TagpickerComponent exposing (main)

import Json.Decode as Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ComponentDef
        , DebouncedCell
        , Remote(..)
        , build
        , defineComponent
        , embed
        , include
        , listCodec
        , on
        , remoteCodec
        , run
        , settled
        , stringCodec
        , toSource
        , with
        , withDebounced
        , withInstance
        )
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import Rad.Internal.Engine exposing (Msg)
import Rad.View exposing (CommitTrigger(..))
import SimpleView
    exposing
        ( SimpleView
        , col
        , debouncedInput
        , simpleViewEngine
        , text
        , watch
        )


type alias TagPickerCells =
    { query : DebouncedCell String
    , suggestions : Cell (Remote RequestError (List String))
    }


matchesDecoder : Decode.Decoder (List String)
matchesDecoder =
    Decode.field "matches" (Decode.list Decode.string)


tagPicker : { endpoint : String, placeholder : String } -> ComponentDef model (SimpleView model) TagPickerCells {}
tagPicker config =
    defineComponent
        { init =
            build TagPickerCells
                |> withDebounced "query" 500 "" stringCodec
                |> with "suggestions" Idle (remoteCodec requestErrorCodec (listCodec stringCodec))
        , computed = \_ -> {}
        , view =
            \c _ ->
                col
                    [ debouncedInput
                        { label = config.placeholder
                        , cell = c.query
                        , triggers = [ OnEnter, OnBlur, OnTimeout ]
                        }
                    , watch (toSource c.suggestions) renderSuggestions
                    ]
        , reactions =
            \c _ ->
                [ on (settled c.query)
                    (\q ->
                        if String.trim q == "" then
                            Rad.noRequest

                        else
                            Http.httpGet prodHandler (config.endpoint ++ "?q=" ++ q) matchesDecoder
                    )
                    c.suggestions
                ]
        }


renderSuggestions : Remote RequestError (List String) -> SimpleView model
renderSuggestions r =
    case r of
        Idle ->
            text "(type to search)"

        Loading ->
            text "searching…"

        Failed _ ->
            text "(error)"

        Done matches ->
            col (List.map (\m -> text (" • " ++ m)) matches)


categoryPicker : ComponentDef Model (SimpleView Model) TagPickerCells {}
categoryPicker =
    tagPicker { endpoint = "/api/search", placeholder = "Category…" }


tagPickerInstance : ComponentDef Model (SimpleView Model) TagPickerCells {}
tagPickerInstance =
    tagPicker { endpoint = "/api/search", placeholder = "Tag…" }


type alias Model =
    { category : TagPickerCells
    , tags : TagPickerCells
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withInstance "category" categoryPicker
            |> withInstance "tags" tagPickerInstance
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ embed categoryPicker model.category
                , embed tagPickerInstance model.tags
                ]
    , reactions =
        \model _ ->
            include categoryPicker model.category
                ++ include tagPickerInstance model.tags
    , persist = Nothing
    }


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
