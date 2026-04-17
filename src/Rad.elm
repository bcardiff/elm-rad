module Rad exposing
    ( Cell
    , CellBuilder, build, with, runBuilder
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    , Source, toSource, readSource
    , Action, set, modify, copy, batch, applyAction
    , AppDef, AppModel, run
    )

{-| elm-rad — reactive cell DSL.

@docs Cell
@docs CellBuilder, build, with, runBuilder
@docs Codec
@docs boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
@docs Source, toSource, readSource
@docs Action, set, modify, copy, batch, applyAction
@docs AppDef, AppModel, run

-}

import Browser
import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Engine
import Rad.Internal.Action as IA
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
        , initial : a
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
            Cell { id = b.nextId, key = key, codec = codec, initial = initial }
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
                    Result.withDefault c.initial (Decode.decodeValue c.codec.decode v)

                Nothing ->
                    c.initial
        )


{-| Read a source against a registry. Exposed for tests and for the runtime.
-}
readSource : Source a -> Registry -> a
readSource =
    IS.readSource


{-| A synchronous action against the cell registry. Phantom `model` parameter
reserves type-level differentiation for later layers.
-}
type alias Action model =
    IA.Action model


{-| Set a cell to a given value.
-}
set : Cell a -> a -> Action model
set (Cell c) value =
    IA.Action (Registry.insert c.id (c.codec.encode value))


{-| Apply a function to the current value of a cell.
-}
modify : Cell a -> (a -> a) -> Action model
modify ((Cell c) as cell) f =
    IA.Action
        (\registry ->
            let
                current =
                    readSource (toSource cell) registry
            in
            Registry.insert c.id (c.codec.encode (f current)) registry
        )


{-| Copy the current value of a source into a cell.

If the source and target have different codecs for the same value type, the
target's codec is used for encoding.

-}
copy : Source a -> Cell a -> Action model
copy source (Cell c) =
    IA.Action
        (\registry ->
            Registry.insert c.id (c.codec.encode (readSource source registry)) registry
        )


{-| Combine a sequence of actions, applied in list order.
-}
batch : List (Action model) -> Action model
batch actions =
    IA.Action
        (\registry ->
            List.foldl (\action r -> IA.apply action r) registry actions
        )


{-| Apply an action to a registry. Exposed for tests and the runtime.
-}
applyAction : Action model -> Registry -> Registry
applyAction =
    IA.apply


{-| A public alias for the runtime's internal model tuple. Used as the model
type of a `Program` so user code does not have to name `Rad.Internal.Registry`.
-}
type alias AppModel model =
    ( model, Registry )


{-| An application definition. Grows additional fields in later layers
(`reactions`, `persist`).
-}
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    }


{-| Run an application. Wraps `Browser.element` so later layers can add
effects without changing the harness.
-}
run :
    Rad.Engine.ViewEngine view model
    -> AppDef view model computed
    -> Program () (AppModel model) (Rad.Engine.Msg model)
run engine app =
    let
        ( model, initialRegistry ) =
            runBuilder app.init
    in
    Browser.element
        { init = \() -> ( ( model, initialRegistry ), Cmd.none )
        , update =
            \msg ( m, registry ) ->
                ( ( m, Rad.Engine.applyMsg msg registry ), Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
