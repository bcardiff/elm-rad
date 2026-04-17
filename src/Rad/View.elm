module Rad.View exposing
    ( Attribute, HtmlView
    , bind, onClick
    , col, input, text, watch
    , htmlEngine
    )

{-| The HTML view engine and its primitives.

@docs Attribute, HtmlView
@docs bind, onClick
@docs col, input, text, watch
@docs htmlEngine

-}

import Html
import Html.Attributes
import Html.Events
import Rad exposing (Action, Cell, Source, readSource, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction)
import Rad.Internal.Registry exposing (Registry)


{-| An attribute applied to an HTML primitive. Encodes reactive intent (bind,
onClick) that `htmlEngine` wires into real `Html.Attribute`s at render time.
-}
type Attribute model
    = BindString (Cell String)
    | OnClick (Action model)


{-| Dispatch an action when an element is clicked.
-}
onClick : Action model -> Attribute model
onClick =
    OnClick


{-| The HTML view value produced by the primitives below. Internally a thunk
over the registry so each primitive can resolve reactive reads at render time.
-}
type HtmlView model
    = HtmlView (Registry -> Html.Html (Msg model))


{-| Two-way bind an input's value to a `Cell String`.
-}
bind : Cell String -> Attribute model
bind =
    BindString


{-| A vertical stack.
-}
col : List (Attribute model) -> List (HtmlView model) -> HtmlView model
col _ children =
    HtmlView
        (\r ->
            Html.div [] (List.map (\(HtmlView f) -> f r) children)
        )


{-| An HTML `<input>`. When a `bind` attribute is present, the input's value
is read from the registry and `onInput` dispatches a `set` action.
-}
input : List (Attribute model) -> List (HtmlView model) -> HtmlView model
input attrs _ =
    HtmlView
        (\registry ->
            let
                ( bindCell, evtAttrs ) =
                    List.foldl
                        (\a ( mc, evts ) ->
                            case a of
                                BindString cell ->
                                    ( Just cell
                                    , Html.Events.onInput (\v -> fromAction (set cell v)) :: evts
                                    )

                                OnClick _ ->
                                    ( mc, evts )
                        )
                        ( Nothing, [] )
                        attrs

                valueAttr =
                    case bindCell of
                        Just cell ->
                            [ Html.Attributes.value (readSource (toSource cell) registry) ]

                        Nothing ->
                            []
            in
            Html.input (valueAttr ++ evtAttrs) []
        )


{-| Plain text.
-}
text : String -> HtmlView model
text s =
    HtmlView (\_ -> Html.text s)


{-| Subscribe a view region to a source. Re-renders when the source's value
changes (achieved via whole-tree re-render on any registry change in Layer 0+1).
-}
watch : Source a -> (a -> HtmlView model) -> HtmlView model
watch source f =
    HtmlView
        (\registry ->
            let
                (HtmlView g) =
                    f (readSource source registry)
            in
            g registry
        )


{-| The shipped HTML engine.
-}
htmlEngine : ViewEngine (HtmlView model) model
htmlEngine =
    { toHtml = \registry (HtmlView f) -> f registry }
