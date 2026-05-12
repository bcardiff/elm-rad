module L06E01_CounterComponent exposing (main)

import Json.Decode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ComponentDef
        , build
        , defineComponent
        , embed
        , include
        , intCodec
        , modify
        , run
        , toSource
        , with
        , withInstance
        )
import Rad.Internal.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, simpleViewEngine, text, watch)


type alias CounterCells =
    { n : Cell Int }


counterComponent : { label : String, step : Int } -> ComponentDef model (SimpleView model) CounterCells {}
counterComponent config =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view =
            \c _ ->
                col
                    [ watch (toSource c.n) (\n -> text (config.label ++ ": " ++ String.fromInt n))
                    , button { label = "+ (" ++ String.fromInt config.step ++ ")", onClick = modify c.n (\v -> v + config.step) }
                    , button { label = "- (" ++ String.fromInt config.step ++ ")", onClick = modify c.n (\v -> v - config.step) }
                    ]
        , reactions = \_ _ -> []
        }


downloadsCounter : ComponentDef Model (SimpleView Model) CounterCells {}
downloadsCounter =
    counterComponent { label = "Downloads", step = 1 }


scaleCounter : ComponentDef Model (SimpleView Model) CounterCells {}
scaleCounter =
    counterComponent { label = "Scale", step = 10 }


type alias Model =
    { downloads : CounterCells
    , scale : CounterCells
    }


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withInstance "downloads" downloadsCounter
            |> withInstance "scale" scaleCounter
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ embed downloadsCounter model.downloads
                , embed scaleCounter model.scale
                ]
    , reactions =
        \model _ ->
            include downloadsCounter model.downloads
                ++ include scaleCounter model.scale
    , persist = Nothing
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
