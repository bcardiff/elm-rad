module L03E03_CustomTriggers exposing (main)

import Json.Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , DebouncedCell
        , build
        , run
        , stringCodec
        , withDebounced
        )
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


type alias Model =
    { text : DebouncedCell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model |> withDebounced "text" 1500 "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ text "Top input commits on Enter only:"
                , debouncedInput
                    { label = "Enter-only"
                    , cell = model.text
                    , triggers = [ OnEnter ]
                    }
                , text "Bottom input commits on Blur or after 1.5s timeout:"
                , debouncedInput
                    { label = "Blur + Timeout"
                    , cell = model.text
                    , triggers = [ OnBlur, OnTimeout ]
                    }
                , watch (Rad.settled model.text) (\s -> text ("shared settled: \"" ++ s ++ "\""))
                ]
    , reactions = \_ _ -> []
    , persist = Nothing
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
