module Rad.Internal.Registry exposing (Registry, empty, get, insert)

import Dict exposing (Dict)
import Json.Decode as Decode


type alias Registry =
    Dict Int Decode.Value


empty : Registry
empty =
    Dict.empty


insert : Int -> Decode.Value -> Registry -> Registry
insert =
    Dict.insert


get : Int -> Registry -> Maybe Decode.Value
get =
    Dict.get
