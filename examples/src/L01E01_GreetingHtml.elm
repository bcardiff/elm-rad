module L01E01_GreetingHtml exposing (main)

import Json.Decode
import Rad exposing (AppDef, AppModel, Cell, build, run, stringCodec, toSource, with)
import Rad.Internal.Engine exposing (Msg)
import Rad.View exposing (HtmlView, bind, col, htmlEngine, input, text, watch)


type alias Model =
    { name : Cell String }


app : AppDef (HtmlView Model) Model {}
app =
    { init = build Model |> with "name" "" stringCodec
    , computed = \_ -> {}
    , view =
        \model _ ->
            col []
                [ input [ bind model.name ] []
                , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))
                ]
    , reactions = \_ _ -> []
    , persist = Nothing
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run htmlEngine app
