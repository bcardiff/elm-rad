module Rad.Engine exposing (Msg, ViewEngine, fromAction, applyMsg)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, applyMsg

-}

import Html exposing (Html)
import Rad.Internal.Action as IA
import Rad.Internal.Msg as IMsg
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type. Opaque. Engines construct values via
`fromAction`; the runtime may add internal variants without breaking engines.
-}
type alias Msg model =
    IMsg.Msg model


{-| Convert a user-level action into a runtime message that engines can
attach to event handlers.
-}
fromAction : IA.Action model -> Msg model
fromAction =
    IMsg.ApplyAction


{-| Apply a runtime message to the registry. Used by the Layer 0-1 runtime
wrapper; reaction-related messages are handled by the runtime directly in
Layer 2.
-}
applyMsg : Msg model -> Registry -> Registry
applyMsg =
    IMsg.apply


{-| A view engine transforms the engine's view type into `Html (Msg model)`.
-}
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
