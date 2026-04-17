module SimpleView exposing
    ( SimpleView
    , col
    , input
    , simpleViewEngine
    , text
    , watch
    )

import Html
import Html.Attributes
import Html.Events
import Rad exposing (Cell, Source, readSource, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction)
import Rad.Internal.Registry exposing (Registry)


type SimpleView model
    = SimpleView (Registry -> Html.Html (Msg model))


col : List (SimpleView model) -> SimpleView model
col children =
    SimpleView
        (\r ->
            Html.div [] (List.map (\(SimpleView f) -> f r) children)
        )


input : { label : String, cell : Cell String } -> SimpleView model
input { label, cell } =
    SimpleView
        (\registry ->
            Html.label []
                [ Html.text (label ++ ": ")
                , Html.input
                    [ Html.Attributes.value (readSource (toSource cell) registry)
                    , Html.Events.onInput (\v -> fromAction (set cell v))
                    ]
                    []
                ]
        )


text : String -> SimpleView model
text s =
    SimpleView (\_ -> Html.text s)


watch : Source a -> (a -> SimpleView model) -> SimpleView model
watch source f =
    SimpleView
        (\registry ->
            let
                (SimpleView g) =
                    f (readSource source registry)
            in
            g registry
        )


simpleViewEngine : ViewEngine (SimpleView model) model
simpleViewEngine =
    { toHtml = \registry (SimpleView f) -> f registry }
