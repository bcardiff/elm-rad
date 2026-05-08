module Rad.Internal.Persist exposing (PersistEntry)

{-| Internal: per-cell persistence schema entry. Each cell-building primitive
(`with`, `withDebounced`, `withValidated`, `Form.withState`) appends one entry
to `BuildResult.persist`. The runtime walks this list to save and restore.

User code never references `PersistEntry` directly; it's an internal
collaboration between builders and the runtime.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry exposing (Registry)


type alias PersistEntry =
    { key : String
    , typeTag : String
    , encode : Registry -> Maybe Encode.Value
    , decode : Encode.Value -> Registry -> Result String Registry
    }
