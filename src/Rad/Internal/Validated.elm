module Rad.Internal.Validated exposing
    ( Core
    , Ref
    , ValidatedCell(..)
    , Validator(..)
    , core
    , ref
    )

{-| Internal shape of `ValidatedCell err a`. The constructor is exposed so
that `Rad` (for `input`, `validation`, `validate`, etc.) can pattern-match.
User code only sees `Rad.ValidatedCell err a`, opaquely.

`Validation err a` itself is defined in `Rad` (so `Rad` can expose its
constructors); `Core` stores `errCodec` so downstream code can rebuild
`validationCodec` on demand.

-}

import Json.Decode as Decode
import Rad.Internal.Request as IRequest


type Validator err a
    = Sync (a -> Result (List err) a)
    | Async (a -> IRequest.Request (List err) a)
    | Compose (List (Validator err a))


type ValidatedCell err a
    = ValidatedCell (Core err a)


type alias Core err a =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , errCodec : { encode : err -> Decode.Value, decode : Decode.Decoder err }
    , validator : Validator err a
    , initial : a
    }


core : ValidatedCell err a -> Core err a
core (ValidatedCell c) =
    c


{-| A type-erased slice used by reactions and tests. No `err`/`a` type
variables — values are already encoded by the time they flow through.
-}
type alias Ref =
    { inputId : Int
    , validationId : Int
    , activationSeqId : Int
    }


ref : ValidatedCell err a -> Ref
ref (ValidatedCell c) =
    { inputId = c.inputId
    , validationId = c.validationId
    , activationSeqId = c.activationSeqId
    }
