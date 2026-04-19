module Rad.Internal.Source exposing (Source(..), codec, readSource)

import Json.Decode as Decode
import Rad.Internal.Registry exposing (Registry)


{-| Internal: the `Source` opaque type with its constructor exposed so that
`Rad` and `Rad.Read` can both construct sources without depending on each
other. The codec is stored alongside the reader so the runtime can encode
source values (used for trigger-change detection in reactions).
-}
type Source a
    = Source
        { read : Registry -> a
        , codec : { encode : a -> Decode.Value, decode : Decode.Decoder a }
        }


readSource : Source a -> Registry -> a
readSource (Source s) registry =
    s.read registry


codec : Source a -> { encode : a -> Decode.Value, decode : Decode.Decoder a }
codec (Source s) =
    s.codec
