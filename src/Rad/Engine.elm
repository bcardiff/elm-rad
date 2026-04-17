module Rad.Engine exposing (Msg, ViewEngine, fromAction, applyMsg)

{-| Engine-author API. App authors never import this module.

@docs Msg, ViewEngine, fromAction, applyMsg

-}

import Html exposing (Html)
import Rad exposing (Action)
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type. Opaque. Engines construct values via `fromAction`.
Later layers add internal variants without breaking engines.
-}
type Msg model
    = ApplyAction (Action model)


{-| Convert a user-level action into a runtime message that engines can attach
to event handlers.
-}
fromAction : Action model -> Msg model
fromAction =
    ApplyAction


{-| Apply a runtime message to the registry. Used by `run`; not part of the
user-facing DSL.
-}
applyMsg : Msg model -> Registry -> Registry
applyMsg (ApplyAction action) registry =
    Rad.applyAction action registry


{-| A view engine transforms the engine's view type into `Html (Msg model)`
for the Elm runtime to render. The engine is given access to the current
registry so it can realize reactive reads.
-}
type alias ViewEngine view model =
    { toHtml : Registry -> view -> Html (Msg model)
    }
