module Rad.Internal.Debounced exposing
    ( DebouncedCell(..)
    , Ref
    , applyInput
    , applyTimerFire
    , core
    , getTimerSeq
    , rawSetAction
    , ref
    )

{-| Internal shape of `DebouncedCell a` plus the pure helpers the runtime,
`Rad.View`, and tests call. User code only sees `Rad.DebouncedCell a`.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Action as IA
import Rad.Internal.Registry as Registry exposing (Registry)


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


{-| Read the current timer sequence counter for a debounced cell. Defaults
to 0 if absent or non-integer.
-}
getTimerSeq : Int -> Registry -> Int
getTimerSeq timerSeqId registry =
    Registry.get timerSeqId registry
        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
        |> Maybe.withDefault 0


{-| Apply a DebouncedInput message's state change: write the encoded value
to the raw slot and bump the timer sequence. Returns the registry plus the
newly-assigned seq number (used by the caller to schedule the fire task).
-}
applyInput : Ref -> Encode.Value -> Registry -> ( Registry, Int )
applyInput r encodedValue registry =
    let
        newSeq =
            getTimerSeq r.timerSeqId registry + 1
    in
    ( registry
        |> Registry.insert r.rawId encodedValue
        |> Registry.insert r.timerSeqId (Encode.int newSeq)
    , newSeq
    )


{-| Apply a DebouncedTimerFire message's state change: if the fired seq is
stale (less than the current seq), no-op. Otherwise copy raw → settled.
-}
applyTimerFire : Ref -> Int -> Registry -> Registry
applyTimerFire r firedSeq registry =
    let
        currentSeq =
            getTimerSeq r.timerSeqId registry
    in
    if firedSeq < currentSeq then
        registry

    else
        case Registry.get r.rawId registry of
            Just rawValue ->
                Registry.insert r.settledId rawValue registry

            Nothing ->
                registry


{-| A plain `Action` that writes raw and bumps timerSeq without scheduling a
timer. Used by `Rad.View.bindDebouncedWith` for bindings whose trigger list
does not include `OnTimeout`, so keystrokes don't spawn timers that would
auto-commit.
-}
rawSetAction : DebouncedCell a -> a -> IA.Action model
rawSetAction (DebouncedCell c) value =
    IA.Action
        (\registry ->
            let
                newSeq =
                    getTimerSeq c.timerSeqId registry + 1
            in
            registry
                |> Registry.insert c.rawId (c.codec.encode value)
                |> Registry.insert c.timerSeqId (Encode.int newSeq)
        )
