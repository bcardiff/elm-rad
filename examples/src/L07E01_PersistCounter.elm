port module L07E01_PersistCounter exposing (main)

import Json.Decode as Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , build
        , intCodec
        , modify
        , persistNow
        , run
        , toSource
        , with
        )
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


port persistSave : ( String, String ) -> Cmd msg


type alias Model =
    { n : Cell Int }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "n" 0 intCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.n) (\v -> text ("Counter: " ++ String.fromInt v))
                , button { label = "+1", onClick = modify model.n (\v -> v + 1) }
                , button { label = "-1", onClick = modify model.n (\v -> v - 1) }
                , button { label = "Save now", onClick = persistNow }
                ]
    , reactions = \_ _ -> []
    , persist = Just { key = "L07E01-persist-counter", version = 1, save = persistSave }
    }


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
