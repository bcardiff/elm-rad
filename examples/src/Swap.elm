module Swap exposing (main)

import Rad exposing (AppDef, AppModel, Cell, batch, build, copy, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine)


type alias Model =
    { a : Cell String
    , b : Cell String
    , tmp : Cell String
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> with "a" "one" stringCodec
            |> with "b" "two" stringCodec
            |> with "tmp" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "A", cell = model.a }
                , input { label = "B", cell = model.b }
                , button
                    { label = "swap"
                    , onClick =
                        batch
                            [ copy (toSource model.a) model.tmp
                            , copy (toSource model.b) model.a
                            , copy (toSource model.tmp) model.b
                            ]
                    }
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
