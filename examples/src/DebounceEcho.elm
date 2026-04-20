module DebounceEcho exposing (main)

import Rad
    exposing
        ( AppDef
        , AppModel
        , DebouncedCell
        , build
        , commit
        , revert
        , run
        , stringCodec
        , withDebounced
        )
import Rad.Engine exposing (Msg)
import Rad.View exposing (CommitTrigger(..))
import SimpleView
    exposing
        ( SimpleView
        , button
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
        build Model |> withDebounced "text" 800 "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ debouncedInput
                    { label = "Type here"
                    , cell = model.text
                    , triggers = [ OnEnter, OnBlur, OnTimeout ]
                    }
                , watch (Rad.raw model.text) (\r -> text ("raw: " ++ r))
                , watch (Rad.settled model.text) (\s -> text ("settled: " ++ s))
                , watch (Rad.synced model.text)
                    (\s ->
                        if s then
                            text "✓ synced"

                        else
                            text "… pending"
                    )
                , button { label = "Commit", onClick = commit model.text }
                , button { label = "Revert", onClick = revert model.text }
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
