module Rad exposing
    ( Cell
    , cellKey, cellId, cellEncodedInitial, cellCodec, cellFromInternal
    , DebouncedCell, withDebounced
    , raw, settled, synced, commit, revert
    , ValidatedCell, withValidated, Validator, sync, async, compose, input, validation, validate, resetValidation, Validation(..), validationCodec, runSyncOnly, validationReactions
    , internalValidationReactionGuts
    , CellBuilder, build, with, runBuilder
    , Codec
    , boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
    , Remote(..), remoteCodec
    , Source, toSource, readSource, derive
    , Action, set, modify, copy, batch, applyAction
    , Request, noRequest, mapRequestError, andThenRequest
    , AppDef, AppModel, run
    , ComponentDef, defineComponent, withInstance, embed, include
    , Reaction, on
    )

{-| elm-rad — reactive cell DSL.

@docs Cell
@docs cellKey, cellId, cellEncodedInitial, cellCodec, cellFromInternal
@docs DebouncedCell, withDebounced
@docs raw, settled, synced, commit, revert
@docs ValidatedCell, withValidated, Validator, sync, async, compose, input, validation, validate, resetValidation, Validation, validationCodec, runSyncOnly, validationReactions
@docs internalValidationReactionGuts
@docs CellBuilder, build, with, runBuilder
@docs Codec
@docs boolCodec, floatCodec, intCodec, listCodec, maybeCodec, stringCodec
@docs Remote, remoteCodec
@docs Source, toSource, readSource, derive
@docs Action, set, modify, copy, batch, applyAction
@docs Request, noRequest, mapRequestError, andThenRequest
@docs AppDef, AppModel, run
@docs ComponentDef, defineComponent, withInstance, embed, include
@docs Reaction, on

-}

import Browser
import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Rad.Engine
import Rad.Internal.Action as IA
import Rad.Internal.CellBuilder as ICellBuilder exposing (CellBuilder(..))
import Rad.Internal.Debounced as IDebounced
import Rad.Internal.Msg as IMsg
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry exposing (Registry)
import Rad.Internal.Request as IRequest
import Rad.Internal.Source as IS
import Rad.Internal.Validated as IValidated
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


{-| Inspect a cell's persistence key. The key is the user-supplied string,
prefixed with any namespace segments introduced by `withInstance`. Useful for
Layer 7 persistence integration and testing.
-}
cellKey : Cell a -> String
cellKey (Cell c) =
    c.key


{-| Inspect a cell's runtime ID. Useful for low-level integration (Form
membership, persistence keying). Most users won't need this.
-}
cellId : Cell a -> Int
cellId (Cell c) =
    c.id


{-| Inspect a cell's initial value, already encoded via its codec. Used by
`Rad.Form` to capture pristine snapshot values without exposing the codec.
-}
cellEncodedInitial : Cell a -> Decode.Value
cellEncodedInitial (Cell c) =
    c.codec.encode c.initial


{-| Inspect a cell's codec. For low-level integration; most users won't need it.
-}
cellCodec : Cell a -> Codec a
cellCodec (Cell c) =
    c.codec


{-| Internal helper for builder modules outside `Rad.elm` (`Rad.Form`'s
`withState`). Constructs a `Cell` from an already-resolved id, key, codec,
and initial. Most users have no reason to call this — use `with`,
`withDebounced`, `withValidated`, or `Form.withState` instead.
-}
cellFromInternal :
    { id : Int
    , key : String
    , codec : Codec a
    , initial : a
    }
    -> Cell a
cellFromInternal r =
    Cell r


{-| An applicative builder for constructing a model made of cells.
-}
type alias CellBuilder ctor =
    ICellBuilder.CellBuilder ctor


{-| Start a CellBuilder from a model constructor.
-}
build : ctor -> CellBuilder ctor
build ctor =
    CellBuilder
        (\state ->
            { nextId = state.nextId
            , metas = []
            , ctor = ctor
            }
        )


{-| Add one cell to the builder, consuming one argument of the constructor.
-}
with : String -> a -> Codec a -> CellBuilder (Cell a -> rest) -> CellBuilder rest
with key initial codec (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                id =
                    parent.nextId

                cell =
                    Cell { id = id, key = state.prefix ++ key, codec = codec, initial = initial }
            in
            { nextId = id + 1
            , metas = ( id, codec.encode initial ) :: parent.metas
            , ctor = parent.ctor cell
            }
        )


{-| Extract the finished model and the initial registry.
-}
runBuilder : CellBuilder model -> ( model, Registry )
runBuilder (CellBuilder f) =
    let
        result =
            f { nextId = 0, prefix = "" }
    in
    ( result.ctor
    , result.metas
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
withDebounced _ delayMs initial codec (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                rawId =
                    parent.nextId

                settledId =
                    parent.nextId + 1

                timerSeqId =
                    parent.nextId + 2

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
            { nextId = parent.nextId + 3
            , metas =
                ( timerSeqId, Encode.int 0 )
                    :: ( settledId, encodedInitial )
                    :: ( rawId, encodedInitial )
                    :: parent.metas
            , ctor = parent.ctor cell
            }
        )


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


{-| A cell with a reactive validation lifecycle. Holds a writable input value
and a derived `Validation err a` state. Constructed via `withValidated`.
Opaque.
-}
type alias ValidatedCell err a =
    IValidated.ValidatedCell err a


{-| The validation lifecycle state.
-}
type Validation err a
    = Dormant
    | Checking
    | Valid a
    | Invalid (List err)


{-| A codec for `Validation err a` given codecs for the error and value types.

The wire format is a tagged object: `{"tag":"Dormant"}`, `{"tag":"Checking"}`,
`{"tag":"Valid","value":<valueEncoded>}`,
`{"tag":"Invalid","errors":[<errEncoded>, ...]}`.

-}
validationCodec : Codec err -> Codec a -> Codec (Validation err a)
validationCodec errCodec valueCodec =
    let
        encode v =
            case v of
                Dormant ->
                    Encode.object [ ( "tag", Encode.string "Dormant" ) ]

                Checking ->
                    Encode.object [ ( "tag", Encode.string "Checking" ) ]

                Valid a ->
                    Encode.object
                        [ ( "tag", Encode.string "Valid" )
                        , ( "value", valueCodec.encode a )
                        ]

                Invalid errs ->
                    Encode.object
                        [ ( "tag", Encode.string "Invalid" )
                        , ( "errors", Encode.list errCodec.encode errs )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Dormant" ->
                                Decode.succeed Dormant

                            "Checking" ->
                                Decode.succeed Checking

                            "Valid" ->
                                Decode.map Valid
                                    (Decode.field "value" valueCodec.decode)

                            "Invalid" ->
                                Decode.map Invalid
                                    (Decode.field "errors" (Decode.list errCodec.decode))

                            other ->
                                Decode.fail ("unknown Validation tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }


{-| Add a validated cell to the builder. Allocates three Registry slots
(input, validation state, activation sequence counter) seeded from `initial`
and Dormant.
-}
withValidated :
    String
    -> a
    -> Codec a
    -> Codec err
    -> IValidated.Validator err a
    -> CellBuilder (ValidatedCell err a -> rest)
    -> CellBuilder rest
withValidated _ initial codec errCodec validator (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                inputId =
                    parent.nextId

                validationId =
                    parent.nextId + 1

                activationSeqId =
                    parent.nextId + 2

                valCodec =
                    validationCodec errCodec codec

                cell =
                    IValidated.ValidatedCell
                        { inputId = inputId
                        , validationId = validationId
                        , activationSeqId = activationSeqId
                        , codec = codec
                        , errCodec = errCodec
                        , validator = validator
                        , initial = initial
                        }

                encodedInitial =
                    codec.encode initial

                encodedDormant =
                    valCodec.encode Dormant
            in
            { nextId = parent.nextId + 3
            , metas =
                ( activationSeqId, Encode.int 0 )
                    :: ( validationId, encodedDormant )
                    :: ( inputId, encodedInitial )
                    :: parent.metas
            , ctor = parent.ctor cell
            }
        )


{-| Opaque validator. Build via `sync`, `async`, or `compose`.
-}
type alias Validator err a =
    IValidated.Validator err a


{-| A synchronous validator. Returns `Ok a` if valid; `Err errs` with a list
of errors otherwise.
-}
sync : (a -> Result (List err) a) -> Validator err a
sync =
    IValidated.Sync


{-| An asynchronous validator. Builds a `Request` whose success value is the
valid `a`; failure is a list of errors. HTTP-backed validators typically
build via `Rad.Http.httpGet` + `mapRequestError`.
-}
async : (a -> Request (List err) a) -> Validator err a
async =
    IValidated.Async


{-| A composed validator. Runs the validators left-to-right; if any one
returns `Invalid`, subsequent validators are skipped. `Valid` propagates the
(possibly transformed) value to the next validator.
-}
compose : List (Validator err a) -> Validator err a
compose =
    IValidated.Compose


{-| The writable input cell of a validated cell. Use with `set`, `modify`,
`copy`, or view bindings (`bind (input vcell)`).
-}
input : ValidatedCell err a -> Cell a
input vcell =
    let
        c =
            IValidated.core vcell
    in
    Cell { id = c.inputId, key = "", codec = c.codec, initial = c.initial }


{-| A `Source` for the validation state of a validated cell.
-}
validation : ValidatedCell err a -> Source (Validation err a)
validation vcell =
    let
        c =
            IValidated.core vcell

        valCodec =
            validationCodec c.errCodec c.codec
    in
    IS.Source
        { read =
            \registry ->
                case Registry.get c.validationId registry of
                    Just v ->
                        Result.withDefault Dormant
                            (Decode.decodeValue valCodec.decode v)

                    Nothing ->
                        Dormant
        , codec = valCodec
        }


{-| Activate validation. Bumps the activation sequence counter; the
validation reaction re-fires with the current input, transitioning from
`Dormant` through `Checking` to `Valid` / `Invalid`. Repeated calls bump
the counter again, forcing re-validation even if the input is unchanged.
-}
validate : ValidatedCell err a -> Action model
validate vcell =
    let
        c =
            IValidated.core vcell
    in
    IA.Action
        (\registry ->
            let
                currentSeq =
                    Registry.get c.activationSeqId registry
                        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                        |> Maybe.withDefault 0
            in
            Registry.insert c.activationSeqId (Encode.int (currentSeq + 1)) registry
        )


{-| Reset validation to `Dormant`. Writes `Dormant` to the validation state
and resets the activation sequence to 0. Any in-flight async validator's
result is discarded by the validation reaction (it sees `SkipRequest`).
-}
resetValidation : ValidatedCell err a -> Action model
resetValidation vcell =
    let
        c =
            IValidated.core vcell

        valCodec =
            validationCodec c.errCodec c.codec
    in
    IA.Action
        (\registry ->
            registry
                |> Registry.insert c.validationId (valCodec.encode Dormant)
                |> Registry.insert c.activationSeqId (Encode.int 0)
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


{-| Transform a Request's success value via a function that may itself
short-circuit to the error channel.

Useful for chaining a sync check after an async request. Example: an HTTP
response whose body indicates whether the action succeeded at the domain
level:

    Http.httpGet handler url decoder
        |> mapRequestError (\netErr -> [ NetworkError netErr ])
        |> andThenRequest
            (\resp ->
                if resp.ok then
                    Ok resp.value

                else
                    Err [ DomainFailure ]
            )

-}
andThenRequest : (a -> Result err b) -> Request err a -> Request err b
andThenRequest f req =
    case req of
        IRequest.NoRequest ->
            IRequest.NoRequest

        IRequest.DispatchRequest task ->
            IRequest.DispatchRequest
                (task
                    |> Task.andThen
                        (\a ->
                            case f a of
                                Ok b ->
                                    Task.succeed b

                                Err errs ->
                                    Task.fail errs
                        )
                )


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


{-| Run the sync portions of a validator without dispatching any async work.
Returns `Just settled` if a final state is reachable (all Sync, with or
without short-circuiting Compose), or `Nothing` if an Async must run.

This is exposed primarily for tests and for a potential future sync fast-path
in the runtime.

-}
runSyncOnly : Validator err a -> a -> Maybe (Validation err a)
runSyncOnly validator value =
    case validator of
        IValidated.Sync f ->
            case f value of
                Ok a ->
                    Just (Valid a)

                Err errs ->
                    Just (Invalid errs)

        IValidated.Async _ ->
            Nothing

        IValidated.Compose validators ->
            runSyncCompose validators value


runSyncCompose : List (Validator err a) -> a -> Maybe (Validation err a)
runSyncCompose validators value =
    case validators of
        [] ->
            Just (Valid value)

        v :: rest ->
            case runSyncOnly v value of
                Nothing ->
                    Nothing

                Just (Valid currentValue) ->
                    runSyncCompose rest currentValue

                Just other ->
                    Just other


applyValidator : Validator err a -> a -> Task.Task Never (Validation err a)
applyValidator validator value =
    case validator of
        IValidated.Sync f ->
            case f value of
                Ok a ->
                    Task.succeed (Valid a)

                Err errs ->
                    Task.succeed (Invalid errs)

        IValidated.Async buildReq ->
            case buildReq value of
                IRequest.NoRequest ->
                    Task.succeed (Valid value)

                IRequest.DispatchRequest task ->
                    task
                        |> Task.map Valid
                        |> Task.onError (\errs -> Task.succeed (Invalid errs))

        IValidated.Compose validators ->
            applyCompose validators value


applyCompose : List (Validator err a) -> a -> Task.Task Never (Validation err a)
applyCompose validators value =
    case validators of
        [] ->
            Task.succeed (Valid value)

        v :: rest ->
            applyValidator v value
                |> Task.andThen
                    (\vState ->
                        case vState of
                            Valid currentValue ->
                                applyCompose rest currentValue

                            _ ->
                                Task.succeed vState
                    )


{-| The reaction(s) powering a validated cell's lifecycle. Returns a
single-element list so users can concatenate multiple validated cells'
reactions with their own:

    reactions =
        \model _ ->
            validationReactions model.name
                ++ validationReactions model.email
                ++ [ myOtherReaction ]

-}
validationReactions : ValidatedCell err a -> List (Reaction model)
validationReactions vcell =
    [ validationReaction vcell ]


{-| Internal: produces the raw fields of a validated cell's reaction. Used by
`Rad.Form` to compose `Form.reactions`. Not part of the supported public API.
-}
internalValidationReactionGuts : ValidatedCell err a -> IReaction.Guts
internalValidationReactionGuts vcell =
    let
        c =
            IValidated.core vcell

        valCodec =
            validationCodec c.errCodec c.codec

        readInput registry =
            case Registry.get c.inputId registry of
                Just v ->
                    Result.withDefault c.initial
                        (Decode.decodeValue c.codec.decode v)

                Nothing ->
                    c.initial

        readActivationSeq registry =
            Registry.get c.activationSeqId registry
                |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                |> Maybe.withDefault 0
    in
    { readTrigger =
        \registry ->
            Encode.list identity
                [ c.codec.encode (readInput registry)
                , Encode.int (readActivationSeq registry)
                ]
    , buildRequest =
        \registry ->
            let
                activationSeq =
                    readActivationSeq registry
            in
            if activationSeq == 0 then
                IReaction.SkipRequest

            else
                IReaction.DispatchTask
                    (applyValidator c.validator (readInput registry)
                        |> Task.map valCodec.encode
                    )
    , writeLoading =
        \registry ->
            Registry.insert c.validationId
                (valCodec.encode Checking)
                registry
    , writeResult =
        \encoded registry ->
            Registry.insert c.validationId encoded registry
    }


validationReaction : ValidatedCell err a -> Reaction model
validationReaction vcell =
    IReaction.fromGuts (internalValidationReactionGuts vcell)


{-| A reusable bundle of cells, computed values, a view, and reactions. Build
via `defineComponent`, mount via `withInstance`, render via `embed`, and
compose reactions via `include`. Opaque.

The `model` type parameter carries through to the `Reaction model` values the
component produces. At use sites, `model` unifies with the outer app's model
type.

-}
type ComponentDef model view cells computed
    = ComponentDef
        { init : CellBuilder cells
        , computed : cells -> computed
        , view : cells -> computed -> view
        , reactions : cells -> computed -> List (Reaction model)
        }


{-| Build a `ComponentDef` from its parts.

    tagPicker : { endpoint : String } -> ComponentDef model (SimpleView model) TagPickerCells {}
    tagPicker config =
        defineComponent
            { init = build TagPickerCells |> with "query" "" stringCodec |> ...
            , computed = \_ -> {}
            , view = \c _ -> ...
            , reactions = \c _ -> [ ... ]
            }

Recommended pattern: bind parameterized `ComponentDef` values at module level
and reference them by name to avoid reconstructing at every use site
(`withInstance`, `embed`, `include`).

-}
defineComponent :
    { init : CellBuilder cells
    , computed : cells -> computed
    , view : cells -> computed -> view
    , reactions : cells -> computed -> List (Reaction model)
    }
    -> ComponentDef model view cells computed
defineComponent def =
    ComponentDef def


{-| Mount a component instance under the given namespace. Inside the
parent's `init` pipeline:

    build Model
        |> withInstance "primary" tagPicker
        |> withInstance "secondary" tagPicker

Each call extends the persistence-key prefix for the component's cells
(`"primary.selected"`, `"secondary.selected"`) and advances the parent's ID
counter past the component's cells.

Works inside another component's `init` too — nested components compose the
prefix (`"outer.inner.field"`).

-}
withInstance :
    String
    -> ComponentDef model view cells computed
    -> CellBuilder (cells -> rest)
    -> CellBuilder rest
withInstance name (ComponentDef def) (CellBuilder f) =
    CellBuilder
        (\state ->
            let
                parent =
                    f state

                childPrefix =
                    state.prefix ++ name ++ "."

                (CellBuilder g) =
                    def.init

                child =
                    g { nextId = parent.nextId, prefix = childPrefix }
            in
            { nextId = child.nextId
            , metas = child.metas ++ parent.metas
            , ctor = parent.ctor child.ctor
            }
        )


{-| Render a component instance's view. Reads the component's cells via
`def.view cells (def.computed cells)`.
-}
embed : ComponentDef model view cells computed -> cells -> view
embed (ComponentDef def) cells =
    def.view cells (def.computed cells)


{-| Collect a component instance's reactions. Returns the list produced by
`def.reactions cells (def.computed cells)`. Concatenate with other reactions
in the parent's `reactions` function.
-}
include : ComponentDef model view cells computed -> cells -> List (Reaction model)
include (ComponentDef def) cells =
    def.reactions cells (def.computed cells)
