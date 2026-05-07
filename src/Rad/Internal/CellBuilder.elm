module Rad.Internal.CellBuilder exposing
    ( BuildResult
    , BuildState
    , CellBuilder(..)
    )

import Json.Decode as Decode


type CellBuilder ctor
    = CellBuilder (BuildState -> BuildResult ctor)


type alias BuildState =
    { nextId : Int
    , prefix : String
    }


type alias BuildResult ctor =
    { nextId : Int
    , metas : List ( Int, Decode.Value )
    , ctor : ctor
    }
