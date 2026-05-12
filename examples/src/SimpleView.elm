module SimpleView exposing
    ( SimpleView
    , button
    , col
    , debouncedInput
    , input
    , simpleViewEngine
    , text
    , watch
    )

import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Rad
    exposing
        ( Action
        , Cell
        , DebouncedCell
        , Source
        , commit
        , readSource
        , set
        , toSource
        )
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput)
import Rad.Internal.Registry exposing (Registry)
import Rad.View exposing (CommitTrigger(..))


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


debouncedInput :
    { label : String, cell : DebouncedCell String, triggers : List CommitTrigger }
    -> SimpleView model
debouncedInput { label, cell, triggers } =
    SimpleView
        (\registry ->
            let
                inputHandler =
                    if List.member OnTimeout triggers then
                        \v -> fromDebouncedInput cell v

                    else
                        \v -> fromAction (IDebounced.rawSetAction cell v)

                commitMsg =
                    fromAction (commit cell)

                triggerAttrs =
                    List.filterMap
                        (\t ->
                            case t of
                                OnEnter ->
                                    Just
                                        (Html.Events.on "keydown"
                                            (Decode.field "key" Decode.string
                                                |> Decode.andThen
                                                    (\k ->
                                                        if k == "Enter" then
                                                            Decode.succeed commitMsg

                                                        else
                                                            Decode.fail "non-Enter key"
                                                    )
                                            )
                                        )

                                OnBlur ->
                                    Just (Html.Events.onBlur commitMsg)

                                OnTimeout ->
                                    Nothing
                        )
                        triggers
            in
            Html.label []
                [ Html.text (label ++ ": ")
                , Html.input
                    ([ Html.Attributes.value (readSource (Rad.raw cell) registry)
                     , Html.Events.onInput inputHandler
                     ]
                        ++ triggerAttrs
                    )
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


button : { label : String, onClick : Action model } -> SimpleView model
button { label, onClick } =
    SimpleView
        (\_ ->
            Html.button
                [ Html.Events.onClick (fromAction onClick) ]
                [ Html.text label ]
        )


simpleViewEngine : ViewEngine (SimpleView model) model
simpleViewEngine =
    { toHtml = \registry (SimpleView f) -> f registry }
