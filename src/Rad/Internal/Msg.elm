module Rad.Internal.Msg exposing (Msg(..), apply)

{-| Internal definition of `Msg model`. The constructor is exposed so that
`Rad.elm` (runtime) can pattern-match, while `Rad.Engine` re-exports `Msg`
opaquely — keeping engines unaware of variants.
-}

import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Registry exposing (Registry)


{-| The runtime message type.
-}
type Msg model
    = ApplyAction (IA.Action model)
    | ReactionResult Int Int (Result Never Encode.Value)


{-| Apply an engine-originated message to the registry. Reaction results are
handled by the runtime separately.
-}
apply : Msg model -> Registry -> Registry
apply msg registry =
    case msg of
        ApplyAction action ->
            IA.apply action registry

        ReactionResult _ _ _ ->
            registry
