module Rad exposing
    ( Cell
    , CellBuilder, build, with, runBuilder
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    , Source, toSource, readSource
    )

{-| elm-rad — reactive cell DSL.

@docs Cell
@docs CellBuilder, build, with, runBuilder
@docs Codec
@docs boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
@docs Source, toSource, readSource

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry as Registry exposing (Registry)
import Rad.Internal.Source as IS


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


{-| -}
listCodec : Codec a -> Codec (List a)
listCodec inner =
    { encode = Encode.list inner.encode
    , decode = Decode.list inner.decode
    }


{-| -}
maybeCodec : Codec a -> Codec (Maybe a)
maybeCodec inner =
    { encode =
        \m ->
            case m of
                Just v ->
                    inner.encode v

                Nothing ->
                    Encode.null
    , decode = Decode.nullable inner.decode
    }


{-| A reactive state cell holding a value of type `a`.
-}
type Cell a
    = Cell
        { id : Int
        , key : String
        , codec : Codec a
        }


{-| An applicative builder for constructing a model made of cells.
-}
type CellBuilder a
    = CellBuilder
        { nextId : Int
        , metas : List ( Int, Decode.Value )
        , ctor : a
        }


{-| Start a CellBuilder from a model constructor.
-}
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        { nextId = 0
        , metas = []
        , ctor = ctor
        }


{-| Add one cell to the builder, consuming one argument of the constructor.
-}
with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder b) =
    let
        cell =
            Cell { id = b.nextId, key = key, codec = codec }
    in
    CellBuilder
        { nextId = b.nextId + 1
        , metas = ( b.nextId, codec.encode initial ) :: b.metas
        , ctor = b.ctor cell
        }


{-| Extract the finished model and the initial registry.
-}
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder b) =
    ( b.ctor
    , b.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty
    )


{-| Anything readable. Cells, derived values, and later debounced/validated
accessors all convert to `Source`. The constructor is not re-exported from
`Rad`, keeping the type opaque to user code.
-}
type alias Source a =
    IS.Source a


{-| Convert a cell into a readable source.
-}
toSource : Cell a -> Source a
toSource (Cell c) =
    IS.Source
        (\registry ->
            case Registry.get c.id registry of
                Just v ->
                    case Decode.decodeValue c.codec.decode v of
                        Ok a ->
                            a

                        Err _ ->
                            -- Invariant: the registry was written by this cell's
                            -- codec, so decode must succeed.
                            Debug.todo "registry codec mismatch"

                Nothing ->
                    Debug.todo "registry missing cell"
        )


{-| Read a source against a registry. Exposed for tests and for the runtime.
-}
readSource : Source a -> Registry -> a
readSource =
    IS.readSource
