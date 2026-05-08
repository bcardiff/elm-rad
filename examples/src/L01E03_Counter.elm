module L01E03_Counter exposing (main)

import Json.Decode
import Rad exposing (AppDef, AppModel, Cell, build, intCodec, modify, run, set, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


type alias Model =
    { n : Cell Int }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "n" 0 intCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ watch (toSource model.n) (\n -> text ("Count: " ++ String.fromInt n))
                , button { label = "−", onClick = modify model.n (\n -> n - 1) }
                , button { label = "+", onClick = modify model.n (\n -> n + 1) }
                , button { label = "reset", onClick = set model.n 0 }
                ]
    , reactions = \_ _ -> []
    , persist = Nothing
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
