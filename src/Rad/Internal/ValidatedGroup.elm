module Rad.Internal.ValidatedGroup exposing
    ( ValidatedGroup(..)
    , readGroup
    , validationIds
    )

{-| Internal: typed bundle of validators in a form. The constructor is
exposed so `Rad.Form` can build values via `validators1`..`validators8` and
read them via `readGroup` / `validationIds`.
-}

import Rad.Internal.Registry exposing (Registry)


type ValidatedGroup fields clean
    = ValidatedGroup
        { ids : fields -> List Int
        , read : fields -> Registry -> Maybe clean
        }


readGroup : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
readGroup (ValidatedGroup g) =
    g.read


validationIds : ValidatedGroup fields clean -> fields -> List Int
validationIds (ValidatedGroup g) =
    g.ids
