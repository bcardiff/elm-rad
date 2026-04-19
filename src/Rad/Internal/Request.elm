module Rad.Internal.Request exposing
    ( Request(..)
    , dispatch
    , mapError
    )

{-| Internal shape of `Request err a`. The constructor is exposed to `Rad`
(for `noRequest`, `mapRequestError`) and to effect-library modules like
`Rad.Http` (for `dispatch`). User code sees only `Rad.Request`, opaquely.

A `Request err a` is either a dispatchable `Task err a` or a no-op
(`NoRequest`). Layer 2 does not add other constructors; later layers may
(e.g., timers) without breaking the public API.

-}

import Task exposing (Task)


type Request err a
    = NoRequest
    | DispatchRequest (Task err a)


{-| Effect libraries construct a Request from a Task.
-}
dispatch : Task err a -> Request err a
dispatch =
    DispatchRequest


{-| Transform the error type. `NoRequest` passes through unchanged.
-}
mapError : (e -> f) -> Request e a -> Request f a
mapError f req =
    case req of
        NoRequest ->
            NoRequest

        DispatchRequest task ->
            DispatchRequest (Task.mapError f task)
