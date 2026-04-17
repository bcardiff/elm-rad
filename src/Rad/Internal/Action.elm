module Rad.Internal.Action exposing (Action(..), apply)

import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Action` opaque type with its constructor exposed so that
`Rad` and `Rad.Engine` can both manipulate actions without depending on each
other. User code only sees `Rad.Action`, which is re-exported opaquely.
-}
type Action model
    = Action (Registry -> Registry)


apply : Action model -> Registry -> Registry
apply (Action f) registry =
    f registry
