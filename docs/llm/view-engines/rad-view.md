---
name: rad-view
description: The HTML view engine bundled with the elm-rad package (`Rad.View`).
---

## Type

```elm
type HtmlView model     -- opaque; the view type
type Attribute model    -- opaque; HTML attribute (analogous to elm/html's Attribute)
```

## Engine value

```elm
htmlEngine : Rad.Internal.Engine.ViewEngine (HtmlView model) model
```

Pass `htmlEngine` to `Rad.run`. The `main` signature becomes:

```elm
import Rad.View exposing (HtmlView, htmlEngine)

main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run htmlEngine app
```

## Combinators

### Constructors

| Function | Type | Notes |
|---|---|---|
| `text` | `String -> HtmlView model` | Static text node. |
| `col`  | `List (Attribute model) -> List (HtmlView model) -> HtmlView model` | Vertical layout (analogous to a `<div>` flex column). |
| `button` | `List (Attribute model) -> List (HtmlView model) -> HtmlView model` | A clickable button; pair with `onClick`. |
| `input`  | `List (Attribute model) -> List (HtmlView model) -> HtmlView model` | A text input; pair with `bind` or `bindDebounced`. |

### Reactive watch

```elm
watch : Source a -> (a -> HtmlView model) -> HtmlView model
```

Re-renders the inner subtree whenever the source's value changes. Cheap when the source updates rarely.

### Attribute combinators

```elm
onClick           : Action model -> Attribute model
bind              : Cell String -> Attribute model
bindDebounced     : DebouncedCell String -> Attribute model
bindDebouncedWith : List CommitTrigger -> DebouncedCell String -> Attribute model
```

- `bind` two-way binds a plain string cell to the input value (updates on every keystroke).
- `bindDebounced` binds a debounced cell using its default commit triggers.
- `bindDebouncedWith` lets you specify the trigger set explicitly (e.g., `[ OnEnter, OnBlur ]`).

## Imports

```elm
import Rad.View exposing
    ( HtmlView
    , bind
    , bindDebounced
    , bindDebouncedWith
    , button
    , col
    , htmlEngine
    , input
    , onClick
    , text
    , watch
    )
import Rad.View as RV exposing (CommitTrigger(..))
```

(`CommitTrigger` is re-exported from `Rad.View`.)

## Complete idiomatic example

```elm
view =
    \model _ ->
        col []
            [ -- A bound text input.
              input [ bind model.name ] []

              -- Reactive text.
            , watch (toSource model.name) (\n -> text ("Hello, " ++ n ++ "!"))

              -- A button that dispatches a sync Action.
            , button [ onClick (modify model.count (\n -> n + 1)) ] [ text "+1" ]

              -- A debounced search input + spinner driven by Remote state.
            , input [ bindDebouncedWith [ OnEnter, OnBlur, OnTimeout ] model.query ] []
            , watch (toSource model.results) renderResults
            ]


renderResults : Remote RequestError (List String) -> HtmlView model
renderResults r =
    case r of
        Idle ->
            text "(type to search)"

        Loading ->
            text "searching…"

        Failed _ ->
            text "(error)"

        Done items ->
            col [] (List.map (\s -> text s) items)
```

## Pitfalls

- `input` and `Rad.input` collide if both are imported unqualified — `Rad.input` extracts the underlying `Cell a` from a `ValidatedCell err a`; this module's `input` is a view constructor. Qualify one of them at use sites.
- For HTML attributes beyond the four listed above (class, id, style, etc.), the engine doesn't currently provide passthroughs. If you need them, write a wrapper or contribute a primitive.
