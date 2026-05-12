module Rad.Internal.Msg exposing (Msg(..), apply)

{-| Internal definition of `Msg model`. The constructor is exposed so that
`Rad.elm` (runtime) can pattern-match, while `Rad.Internal.Engine` re-exports `Msg`
opaquely — keeping engines unaware of variants.
-}

import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type.
-}
type Msg model
    = ApplyAction (IA.Action model)
    | ReactionResult Int Int (Result Never Encode.Value)
    | DebouncedInput IDebounced.Ref Encode.Value
    | DebouncedTimerFire IDebounced.Ref Int
    | PersistTimerFired Int


{-| Apply an engine-originated message to the registry. Reaction results and
debounced dispatches are handled by the runtime separately.
-}
apply : Msg model -> Registry -> Registry
apply msg registry =
    case msg of
        ApplyAction action ->
            IA.apply action registry

        ReactionResult _ _ _ ->
            registry

        DebouncedInput _ _ ->
            registry

        DebouncedTimerFire _ _ ->
            registry

        PersistTimerFired _ ->
            registry
