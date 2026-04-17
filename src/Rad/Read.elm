module Rad.Read exposing (Read, read, map, map2, run)

{-| A read-only view into the cell registry. Values in `Read` are evaluated
at render time by the runtime and by `Rad.derive`.

@docs Read, read, map, map2, run

-}

import Rad.Internal.Registry exposing (Registry)
import Rad.Internal.Source exposing (Source, readSource)


{-| A deferred read against a registry.
-}
type Read a
    = Read (Registry -> a)


{-| Lift a source into a `Read`.
-}
read : Source a -> Read a
read source =
    Read (readSource source)


{-| Map a pure function over a `Read`.
-}
map : (a -> b) -> Read a -> Read b
map f (Read g) =
    Read (\r -> f (g r))


{-| Combine two `Read`s with a pure function.
-}
map2 : (a -> b -> c) -> Read a -> Read b -> Read c
map2 f (Read g) (Read h) =
    Read (\r -> f (g r) (h r))


{-| Evaluate a `Read` against a registry. Used by the runtime, tests, and
`Rad.derive`.
-}
run : Read a -> Registry -> a
run (Read f) registry =
    f registry
