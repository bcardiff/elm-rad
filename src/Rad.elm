module Rad exposing
    ( Cell
    , DebouncedCell, withDebounced
    , raw, settled, synced, commit, revert
    , CellBuilder, build, with, runBuilder
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    , Remote(..), remoteCodec
    , Source, toSource, readSource, derive
    , Action, set, modify, copy, batch, applyAction
    , Request, noRequest, mapRequestError
    , AppDef, AppModel, run
    , Reaction, on
    )

{-| elm-rad — reactive cell DSL.

@docs Cell
@docs DebouncedCell, withDebounced
@docs raw, settled, synced, commit, revert
@docs CellBuilder, build, with, runBuilder
@docs Codec
@docs boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
@docs Remote, remoteCodec
@docs Source, toSource, readSource, derive
@docs Action, set, modify, copy, batch, applyAction
@docs Request, noRequest, mapRequestError
@docs AppDef, AppModel, run
@docs Reaction, on

-}

import Browser
import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Rad.Engine
import Rad.Internal.Action as IA
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Msg as IMsg
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry exposing (Registry)
import Rad.Internal.Request as IRequest
import Rad.Internal.Source as IS
import Rad.Read
import Task


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


{-| A remote resource in one of four states.
-}
type Remote err a
    = Idle
    | Loading
    | Failed err
    | Done a


{-| A codec for `Remote err a` given codecs for the error and value types.

The wire format is a tagged object: `{"tag":"Idle"}`, `{"tag":"Loading"}`,
`{"tag":"Failed","value":<errEncoded>}`, `{"tag":"Done","value":<valueEncoded>}`.

-}
remoteCodec : Codec err -> Codec a -> Codec (Remote err a)
remoteCodec errCodec valueCodec =
    let
        encode r =
            case r of
                Idle ->
                    Encode.object [ ( "tag", Encode.string "Idle" ) ]

                Loading ->
                    Encode.object [ ( "tag", Encode.string "Loading" ) ]

                Failed e ->
                    Encode.object
                        [ ( "tag", Encode.string "Failed" )
                        , ( "value", errCodec.encode e )
                        ]

                Done v ->
                    Encode.object
                        [ ( "tag", Encode.string "Done" )
                        , ( "value", valueCodec.encode v )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Idle" ->
                                Decode.succeed Idle

                            "Loading" ->
                                Decode.succeed Loading

                            "Failed" ->
                                Decode.map Failed (Decode.field "value" errCodec.decode)

                            "Done" ->
                                Decode.map Done (Decode.field "value" valueCodec.decode)

                            other ->
                                Decode.fail ("unknown Remote tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }


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


{-| A cell with settle semantics. Holds two observable values — `raw` (updates
on every keystroke or `fromDebouncedInput`) and `settled` (updates on commit,
revert, or after a timer). Constructed via `withDebounced`. Opaque.
-}
type alias DebouncedCell a =
    IDebounced.DebouncedCell a


{-| Add a debounced cell to the builder. Allocates three Registry slots
(raw, settled, and a per-cell timer sequence counter) seeded from `initial`.
-}
withDebounced : String -> Float -> a -> Codec a -> CellBuilder (DebouncedCell a -> rest) -> CellBuilder rest
withDebounced _ delayMs initial codec (CellBuilder b) =
    let
        rawId =
            b.nextId

        settledId =
            b.nextId + 1

        timerSeqId =
            b.nextId + 2

        cell =
            IDebounced.DebouncedCell
                { rawId = rawId
                , settledId = settledId
                , timerSeqId = timerSeqId
                , codec = codec
                , delayMs = delayMs
                , initial = initial
                }

        encodedInitial =
            codec.encode initial
    in
    CellBuilder
        { nextId = b.nextId + 3
        , metas =
            ( timerSeqId, Encode.int 0 )
                :: ( settledId, encodedInitial )
                :: ( rawId, encodedInitial )
                :: b.metas
        , ctor = b.ctor cell
        }


{-| A `Source` for the raw value of a debounced cell — updates on every
`fromDebouncedInput` (or keystroke via a view binding) and via `revert`.
-}
raw : DebouncedCell a -> Source a
raw (IDebounced.DebouncedCell d) =
    IS.Source
        { read =
            \registry ->
                case Registry.get d.rawId registry of
                    Just v ->
                        Result.withDefault d.initial (Decode.decodeValue d.codec.decode v)

                    Nothing ->
                        d.initial
        , codec = d.codec
        }


{-| A `Source` for the settled value of a debounced cell — updates on
`commit`, `revert`, or after the debounce timer fires.
-}
settled : DebouncedCell a -> Source a
settled (IDebounced.DebouncedCell d) =
    IS.Source
        { read =
            \registry ->
                case Registry.get d.settledId registry of
                    Just v ->
                        Result.withDefault d.initial (Decode.decodeValue d.codec.decode v)

                    Nothing ->
                        d.initial
        , codec = d.codec
        }


{-| A derived `Source Bool` reporting whether a debounced cell's raw and
settled values are equal. Uses JSON-encoded equality via the cell's codec,
consistent with Layer 2 trigger-change detection.
-}
synced : DebouncedCell a -> Source Bool
synced cell =
    let
        rawSource =
            raw cell

        settledSource =
            settled cell
    in
    derive boolCodec
        (Rad.Read.map2
            (\r s ->
                Encode.encode 0 ((IS.codec rawSource).encode r)
                    == Encode.encode 0 ((IS.codec settledSource).encode s)
            )
            (Rad.Read.read rawSource)
            (Rad.Read.read settledSource)
        )


{-| Commit a debounced cell's raw value to its settled value (copies raw →
settled). A pure `Action`; does not touch the timer sequence, so any in-flight
timer will fire harmlessly (raw and settled already match).
-}
commit : DebouncedCell a -> Action model
commit (IDebounced.DebouncedCell d) =
    IA.Action
        (\registry ->
            case Registry.get d.rawId registry of
                Just rawValue ->
                    Registry.insert d.settledId rawValue registry

                Nothing ->
                    registry
        )


{-| Revert a debounced cell's raw value to its settled value (copies settled
→ raw). Dual of `commit`. Does not touch the timer sequence.
-}
revert : DebouncedCell a -> Action model
revert (IDebounced.DebouncedCell d) =
    IA.Action
        (\registry ->
            case Registry.get d.settledId registry of
                Just settledValue ->
                    Registry.insert d.rawId settledValue registry

                Nothing ->
                    registry
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
        { read =
            \registry ->
                case Registry.get c.id registry of
                    Just v ->
                        Result.withDefault c.initial (Decode.decodeValue c.codec.decode v)

                    Nothing ->
                        c.initial
        , codec = c.codec
        }


{-| Read a source against a registry. Exposed for tests and for the runtime.
-}
readSource : Source a -> Registry -> a
readSource =
    IS.readSource


{-| Turn a `Read` into a `Source`. The resulting source recomputes its value
from the registry on every read, and carries the supplied codec so the runtime
can encode derived values (for trigger-change detection).
-}
derive : Codec a -> Rad.Read.Read a -> Source a
derive codecA readValue =
    IS.Source
        { read = \registry -> Rad.Read.run readValue registry
        , codec = codecA
        }


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


{-| An asynchronous request produced by an effect library (e.g., `Rad.Http`).
Opaque; Layer 2 constructors are `noRequest` and values returned by
effect-library functions like `Rad.Http.httpGet`.
-}
type alias Request err a =
    IRequest.Request err a


{-| A Request that does nothing. Returned from the `a -> Request err r`
transform in a reaction to signal "don't dispatch for this trigger value."
-}
noRequest : Request err a
noRequest =
    IRequest.NoRequest


{-| Transform a Request's error type. Useful for mapping a library-defined
error (e.g., `Rad.Http.RequestError`) into a domain error type.
-}
mapRequestError : (e -> f) -> Request e a -> Request f a
mapRequestError =
    IRequest.mapError


{-| A reaction — a rule that says "when this source's value changes, run
this request and store the result in this cell." Constructed via `on`.
Opaque.
-}
type alias Reaction model =
    IReaction.Reaction model


{-| Build a reaction.

    reactions =
        \_ _ ->
            [ on (toSource model.tick) (\_ -> Rad.Http.httpGet handler "/api/joke" jokeDecoder) model.joke
            ]

-}
on :
    Source a
    -> (a -> Request err r)
    -> Cell (Remote err r)
    -> Reaction model
on source transform (Cell target) =
    let
        sourceCodec =
            IS.codec source

        targetCodec =
            target.codec
    in
    IReaction.Reaction
        { readTrigger =
            \registry ->
                sourceCodec.encode (IS.readSource source registry)
        , buildRequest =
            \registry ->
                case transform (IS.readSource source registry) of
                    IRequest.NoRequest ->
                        IReaction.SkipRequest

                    IRequest.DispatchRequest task ->
                        IReaction.DispatchTask
                            (task
                                |> Task.map (\r -> targetCodec.encode (Done r))
                                |> Task.onError (\e -> Task.succeed (targetCodec.encode (Failed e)))
                            )
        , writeLoading =
            \registry ->
                Registry.insert target.id (targetCodec.encode Loading) registry
        , writeResult =
            \encoded registry ->
                Registry.insert target.id encoded registry
        }


{-| A public alias for the runtime's internal model tuple. Used as the model
type of a `Program` so user code does not have to name `Rad.Internal.Registry`.
-}
type alias AppModel model =
    ( model, Registry, IReaction.ReactionState )


{-| An application definition. Grows additional fields in later layers
(`persist`).
-}
type alias AppDef view model computed =
    { init : CellBuilder model
    , computed : model -> computed
    , view : model -> computed -> view
    , reactions : model -> computed -> List (Reaction model)
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

        fireReactions : Registry -> IReaction.ReactionState -> ( Registry, IReaction.ReactionState, Cmd (Rad.Engine.Msg model) )
        fireReactions registry state =
            let
                reactions =
                    app.reactions model (app.computed model)

                listLen =
                    List.length reactions

                prunedState =
                    { triggers = Dict.filter (\k _ -> k < listLen) state.triggers
                    , seqs = Dict.filter (\k _ -> k < listLen) state.seqs
                    }

                step ( i, IReaction.Reaction r ) ( reg, st, cmds ) =
                    let
                        newTrigger =
                            r.readTrigger reg
                    in
                    case Dict.get i st.triggers of
                        Just prev ->
                            if Encode.encode 0 prev == Encode.encode 0 newTrigger then
                                ( reg, st, cmds )

                            else
                                fireOne i newTrigger r reg st cmds

                        Nothing ->
                            fireOne i newTrigger r reg st cmds

                fireOne i newTrigger r reg st cmds =
                    let
                        newSeq =
                            (Dict.get i st.seqs |> Maybe.withDefault 0) + 1

                        st1 =
                            { triggers = Dict.insert i newTrigger st.triggers
                            , seqs = Dict.insert i newSeq st.seqs
                            }
                    in
                    case r.buildRequest reg of
                        IReaction.SkipRequest ->
                            ( reg, st1, cmds )

                        IReaction.DispatchTask task ->
                            ( r.writeLoading reg
                            , st1
                            , Task.attempt (IMsg.ReactionResult i newSeq) task :: cmds
                            )

                ( finalReg, finalState, finalCmds ) =
                    List.foldl step
                        ( registry, prunedState, [] )
                        (List.indexedMap Tuple.pair reactions)
            in
            ( finalReg, finalState, Cmd.batch finalCmds )
    in
    Browser.element
        { init =
            \() ->
                let
                    ( reg1, state1, cmd ) =
                        fireReactions initialRegistry IReaction.emptyState
                in
                ( ( model, reg1, state1 ), cmd )
        , update =
            \msg ( m, registry, state ) ->
                case msg of
                    IMsg.ApplyAction action ->
                        let
                            reg1 =
                                IA.apply action registry

                            ( reg2, state2, cmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), cmd )

                    IMsg.ReactionResult i receivedSeq result ->
                        case Dict.get i state.seqs of
                            Just expected ->
                                if expected /= receivedSeq then
                                    ( ( m, registry, state ), Cmd.none )

                                else
                                    case result of
                                        Ok encoded ->
                                            let
                                                reactions =
                                                    app.reactions m (app.computed m)

                                                maybeReaction =
                                                    reactions
                                                        |> List.drop i
                                                        |> List.head
                                            in
                                            case maybeReaction of
                                                Just (IReaction.Reaction r) ->
                                                    ( ( m, r.writeResult encoded registry, state )
                                                    , Cmd.none
                                                    )

                                                Nothing ->
                                                    ( ( m, registry, state ), Cmd.none )

                                        Err _ ->
                                            -- Task Never Value: unreachable.
                                            ( ( m, registry, state ), Cmd.none )

                            Nothing ->
                                ( ( m, registry, state ), Cmd.none )

                    IMsg.DebouncedInput dRef encodedValue ->
                        let
                            ( reg1, newSeq ) =
                                IDebounced.applyInput dRef encodedValue registry

                            timerCmd =
                                Process.sleep dRef.delayMs
                                    |> Task.perform
                                        (\_ -> IMsg.DebouncedTimerFire dRef newSeq)

                            ( reg2, state2, reactionCmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), Cmd.batch [ timerCmd, reactionCmd ] )

                    IMsg.DebouncedTimerFire dRef firedSeq ->
                        let
                            reg1 =
                                IDebounced.applyTimerFire dRef firedSeq registry

                            ( reg2, state2, reactionCmd ) =
                                fireReactions reg1 state
                        in
                        ( ( m, reg2, state2 ), reactionCmd )
        , subscriptions = \_ -> Sub.none
        , view =
            \( m, registry, _ ) ->
                engine.toHtml registry (app.view m (app.computed m))
        }
