module Rad.Internal.Reaction exposing
    ( Guts
    , InternalRequest(..)
    , Reaction(..)
    , ReactionState
    , emptyState
    , fromGuts
    )

{-| Internal shape of `Reaction model`. The constructor is exposed to `Rad`
(for `on`) and to the runtime (in `Rad.elm`'s `run`). User code only sees
`Rad.Reaction model`, opaquely.
-}

import Dict exposing (Dict)
import Json.Encode as Encode
import Rad.Internal.Registry exposing (Registry)
import Task exposing (Task)


{-| A built reaction. The runtime reads triggers, builds requests, and
applies writes without knowing the user's `a`, `err`, or `r` types — all type
information is erased into `Encode.Value`.
-}
type Reaction model
    = Reaction
        { readTrigger : Registry -> Encode.Value
        , buildRequest : Registry -> InternalRequest
        , writeLoading : Registry -> Registry
        , writeResult : Encode.Value -> Registry -> Registry
        , inFlight : Registry -> Bool
        }


{-| What a reaction produces on a firing cycle. `SkipRequest` means the
trigger changed but the transform returned `noRequest`; in that case the
target cell is not written.

`DispatchTask` carries a task that always succeeds with an already-encoded
`Remote err r` value (err and ok are folded into the `Remote` wrapper before
type erasure, so the runtime does not need component codecs).

-}
type InternalRequest
    = SkipRequest
    | DispatchTask (Task Never Encode.Value)


{-| Per-reaction bookkeeping. Indexed by reaction position in the list
produced by `AppDef.reactions`.
-}
type alias ReactionState =
    { triggers : Dict Int Encode.Value
    , seqs : Dict Int Int
    }


emptyState : ReactionState
emptyState =
    { triggers = Dict.empty, seqs = Dict.empty }


{-| The fields of a `Reaction` as a separate, non-parameterized record.
Used by `Rad.Form` to store partially-built reactions in `Member` without
threading a `model` type variable through Form/Member.
-}
type alias Guts =
    { readTrigger : Registry -> Encode.Value
    , buildRequest : Registry -> InternalRequest
    , writeLoading : Registry -> Registry
    , writeResult : Encode.Value -> Registry -> Registry
    , inFlight : Registry -> Bool
    }


fromGuts : Guts -> Reaction model
fromGuts g =
    Reaction g
