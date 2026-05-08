module Rad.Internal.CellBuilder exposing
    ( BuildResult
    , BuildState
    , CellBuilder(..)
    )

{-| Internal: the `CellBuilder` opaque type and its build-state helpers.
The constructor is exposed so that `Rad` (for `build`, `with`, `runBuilder`,
`withDebounced`, `withValidated`, `withInstance`) and `Rad.Form` (for
`Form.withState`, in Layer 5) can both construct and pattern-match builders
without depending on each other.

User code only sees `Rad.CellBuilder ctor`, opaquely.

-}

import Json.Decode as Decode
import Rad.Internal.Persist as IPersist


type CellBuilder ctor
    = CellBuilder (BuildState -> BuildResult ctor)


type alias BuildState =
    { nextId : Int
    , prefix : String
    }


type alias BuildResult ctor =
    { nextId : Int
    , metas : List ( Int, Decode.Value )
    , persist : List IPersist.PersistEntry
    , ctor : ctor
    }
