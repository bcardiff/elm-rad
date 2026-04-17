module Rad.Internal.Source exposing (Source(..), readSource)

import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Source` opaque type with its constructor exposed so that
`Rad` and `Rad.Read` can both construct sources without depending on each
other. User code only sees `Rad.Source`, which is re-exported opaquely.
-}
type Source a
    = Source (Registry -> a)


readSource : Source a -> Registry -> a
readSource (Source f) registry =
    f registry
