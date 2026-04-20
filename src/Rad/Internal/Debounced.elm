module Rad.Internal.Debounced exposing
    ( DebouncedCell(..)
    , Ref
    , core
    , ref
    )

{-| Internal shape of `DebouncedCell a`. The constructor is exposed to `Rad`
(for `withDebounced`, `raw`, `settled`, `commit`, `revert`), to `Rad.Engine`
(for `fromDebouncedInput`), and to `Rad.View` (for `bindDebouncedWith`).
User code only sees `Rad.DebouncedCell a`, opaquely.
-}

import Json.Decode as Decode


{-| Full internal record. Holds the three Registry slot IDs, the codec,
delay, and initial value (used for decode fallback in source readers).
-}
type DebouncedCell a
    = DebouncedCell (Core a)


type alias Core a =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
    , delayMs : Float
    , initial : a
    }


core : DebouncedCell a -> Core a
core (DebouncedCell c) =
    c


{-| A type-erased slice used by `Msg` variants. Carries everything `update`
needs to dispatch debounced-input and timer-fire messages (the three slot IDs
and the delay), but not the codec — values are already encoded by the time
they reach the Msg, and the timer-fire handler just copies bytes raw→settled.
-}
type alias Ref =
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , delayMs : Float
    }


ref : DebouncedCell a -> Ref
ref (DebouncedCell c) =
    { rawId = c.rawId
    , settledId = c.settledId
    , timerSeqId = c.timerSeqId
    , delayMs = c.delayMs
    }
