module Rad exposing
    ( Codec
    , boolCodec, floatCodec, intCodec, stringCodec
    )

{-| elm-rad — reactive cell DSL.

@docs Codec
@docs boolCodec, floatCodec, intCodec, stringCodec

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| A pair of encoder and decoder for serializing cell values.
-}
type alias Codec a =
    { encode : a -> Decode.Value
    , decode : Decode.Decoder a
    }


{-| -}
stringCodec : Codec String
stringCodec =
    { encode = Encode.string, decode = Decode.string }


{-| -}
intCodec : Codec Int
intCodec =
    { encode = Encode.int, decode = Decode.int }


{-| -}
floatCodec : Codec Float
floatCodec =
    { encode = Encode.float, decode = Decode.float }


{-| -}
boolCodec : Codec Bool
boolCodec =
    { encode = Encode.bool, decode = Decode.bool }
