module Rad.Engine exposing (Msg, ViewEngine, fromAction, fromDebouncedInput, applyMsg)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, fromDebouncedInput, applyMsg

-}

import Html exposing (Html)
import Rad.Internal.Action as IA
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Msg as IMsg
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type. Opaque. Engines construct values via
`fromAction` or `fromDebouncedInput`; the runtime may add internal variants
without breaking engines.
-}
type alias Msg model =
    IMsg.Msg model


{-| Convert a user-level action into a runtime message that engines can
attach to event handlers.
-}
fromAction : IA.Action model -> Msg model
fromAction =
    IMsg.ApplyAction


{-| Construct a runtime message that writes `value` to a debounced cell's
raw slot and schedules a `Process.sleep` timer that commits raw → settled
after the cell's configured delay. Used by view engines on `onInput` for
debounced bindings.

Engines that want a raw write without scheduling a timer should use
`Rad.View.bindDebouncedWith` with a trigger list that excludes `OnTimeout`
(that binding dispatches a plain Action instead).

-}
fromDebouncedInput : IDebounced.DebouncedCell a -> a -> Msg model
fromDebouncedInput cell value =
    let
        c =
            IDebounced.core cell
    in
    IMsg.DebouncedInput (IDebounced.ref cell) (c.codec.encode value)


{-| Apply a runtime message to the registry. Used by the Layer 0-1 runtime
wrapper; reaction and debounced messages are handled by the runtime directly.
-}
applyMsg : Msg model -> Registry -> Registry
applyMsg =
    IMsg.apply


{-| A view engine transforms the engine's view type into `Html (Msg model)`.
-}
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
