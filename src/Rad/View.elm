module Rad.View exposing
    ( Attribute, HtmlView
    , CommitTrigger(..)
    , bind, bindDebounced, bindDebouncedWith, onClick
    , button, col, input, text, watch
    , htmlEngine
    )

{-| The HTML view engine and its primitives.

@docs Attribute, HtmlView
@docs CommitTrigger
@docs bind, bindDebounced, bindDebouncedWith, onClick
@docs button, col, input, text, watch
@docs htmlEngine

-}

import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Rad exposing (Action, Cell, DebouncedCell, Source, commit, readSource, set, toSource)
import Rad.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput)
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry exposing (Registry)


{-| A commit trigger for debounced bindings.
-}
type CommitTrigger
    = OnEnter
    | OnBlur
    | OnTimeout


{-| An attribute applied to an HTML primitive. Encodes reactive intent (bind,
bindDebounced, onClick) that `htmlEngine` wires into real `Html.Attribute`s
at render time.
-}
type Attribute model
    = BindString (Cell String)
    | BindDebouncedString (DebouncedCell String) (List CommitTrigger)
    | OnClick (Action model)


{-| Dispatch an action when an element is clicked.
-}
onClick : Action model -> Attribute model
onClick =
    OnClick


{-| The HTML view value.
-}
type HtmlView model
    = HtmlView (Registry -> Html.Html (Msg model))


{-| Two-way bind an input's value to a `Cell String`.
-}
bind : Cell String -> Attribute model
bind =
    BindString


{-| Bind an input to a `DebouncedCell String` with all commit triggers
enabled (`OnEnter`, `OnBlur`, `OnTimeout`) — the common debounce case.
-}
bindDebounced : DebouncedCell String -> Attribute model
bindDebounced cell =
    BindDebouncedString cell [ OnEnter, OnBlur, OnTimeout ]


{-| Bind an input to a `DebouncedCell String` with a custom set of commit
triggers. The empty list is a valid escape hatch: no view trigger commits;
the only paths to settled are explicit `commit` / `revert` actions.
-}
bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> Attribute model
bindDebouncedWith triggers cell =
    BindDebouncedString cell triggers


{-| A vertical stack.
-}
col : List (Attribute model) -> List (HtmlView model) -> HtmlView model
col _ children =
    HtmlView
        (\r ->
            Html.div [] (List.map (\(HtmlView f) -> f r) children)
        )


{-| An HTML `<input>`.
-}
input : List (Attribute model) -> List (HtmlView model) -> HtmlView model
input attrs _ =
    HtmlView
        (\registry ->
            let
                ( valueAttr, evtAttrs ) =
                    List.foldl
                        (\a ( vs, evts ) ->
                            case a of
                                BindString cell ->
                                    ( Html.Attributes.value (readSource (toSource cell) registry) :: vs
                                    , Html.Events.onInput (\v -> fromAction (set cell v)) :: evts
                                    )

                                BindDebouncedString cell triggers ->
                                    let
                                        inputHandler =
                                            if List.member OnTimeout triggers then
                                                \v -> fromDebouncedInput cell v

                                            else
                                                \v -> fromAction (IDebounced.rawSetAction cell v)

                                        triggerEvents =
                                            debouncedTriggerEvents triggers cell
                                    in
                                    ( Html.Attributes.value
                                        (readSource (Rad.raw cell) registry)
                                        :: vs
                                    , Html.Events.onInput inputHandler
                                        :: (triggerEvents ++ evts)
                                    )

                                OnClick _ ->
                                    ( vs, evts )
                        )
                        ( [], [] )
                        attrs
            in
            Html.input (valueAttr ++ evtAttrs) []
        )


{-| Plain text.
-}
text : String -> HtmlView model
text s =
    HtmlView (\_ -> Html.text s)


{-| An HTML `<button>`.
-}
button : List (Attribute model) -> List (HtmlView model) -> HtmlView model
button attrs children =
    HtmlView
        (\registry ->
            let
                clickAttrs =
                    List.concatMap
                        (\a ->
                            case a of
                                OnClick action ->
                                    [ Html.Events.onClick (fromAction action) ]

                                _ ->
                                    []
                        )
                        attrs
            in
            Html.button clickAttrs
                (List.map (\(HtmlView f) -> f registry) children)
        )


{-| Subscribe a view region to a source.
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



-- INTERNALS


debouncedTriggerEvents :
    List CommitTrigger
    -> DebouncedCell String
    -> List (Html.Attribute (Msg model))
debouncedTriggerEvents triggers cell =
    let
        commitMsg =
            fromAction (commit cell)
    in
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
