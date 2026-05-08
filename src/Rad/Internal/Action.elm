module Rad.Internal.Action exposing (Action(..), apply, isPersistNow)

import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Action` opaque type with its constructor exposed so that
`Rad` and `Rad.Engine` can both manipulate actions without depending on each
other. User code only sees `Rad.Action`, which is re-exported opaquely.
-}
type Action model
    = Action (Registry -> Registry)
    | PersistNow


apply : Action model -> Registry -> Registry
apply action registry =
    case action of
        Action f ->
            f registry

        PersistNow ->
            registry


isPersistNow : Action model -> Bool
isPersistNow action =
    case action of
        PersistNow ->
            True

        Action _ ->
            False
