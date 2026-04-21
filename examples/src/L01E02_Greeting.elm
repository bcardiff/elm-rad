module L01E02_Greeting exposing (main)

import Rad exposing (AppDef, AppModel, Cell, build, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { name : Cell String }


app : AppDef (SimpleView Model) Model {}
app =
    { init = build Model |> with "name" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Name", cell = model.name }
                , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
