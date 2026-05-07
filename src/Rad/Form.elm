module Rad.Form exposing
    ( Form, Member, State, stateCodec
    , withState
    , over, field, validatedField
    , dirty, submit, reset
    , Status(..), status, canSubmit, submitPending, invalid, checking
    , memberCount
    , ValidatedGroup, validators1, validators2, validators3, validators4
    , validators5, validators6, validators7, validators8, mapValidated, readGroup
    )

{-| Layer 5 — Forms. Designed for `import Rad.Form as Form`.


# Types

@docs Form, Member, State, stateCodec


# Builder

@docs withState


# Use-site construction

@docs over, field, validatedField


# Behaviors

@docs dirty, submit, reset


# Status

@docs Status, status, canSubmit, submitPending, invalid, checking


# Inspection

@docs memberCount


# ValidatedGroup

@docs ValidatedGroup, validators1, validators2, validators3, validators4
@docs validators5, validators6, validators7, validators8, mapValidated, readGroup

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (Cell, CellBuilder, Codec)
import Rad.Internal.Action as IAction exposing (Action(..))
import Rad.Internal.CellBuilder exposing (CellBuilder(..))
import Rad.Internal.Form as IForm
import Rad.Internal.Registry as Registry exposing (Registry)
import Rad.Internal.Source as ISource
import Rad.Internal.Validated as IValidated
import Rad.Internal.ValidatedGroup as IGroup


{-| Opaque transaction boundary over a cells record.
-}
type alias Form fields =
    IForm.Form fields


{-| Opaque membership record. Constructed by `field` / `validatedField`.
-}
type alias Member =
    IForm.Member


{-| The persisted state of a form: snapshot blob + submit-lifecycle counters.
-}
type alias State =
    IForm.State


{-| Codec for `State`, useful at persistence boundaries and in tests.
-}
stateCodec : Codec State
stateCodec =
    { encode = IForm.stateCodec.encode, decode = IForm.stateCodec.decode }


{-| Allocate a Form's persisted state cell. Initial value
`{ snapshot = null, submitSeq = 0, lastResolvedSubmitSeq = 0 }`.

    init =
        build Model
            |> with "name" "" stringCodec
            |> Form.withState "profile-form"

-}
withState : String -> CellBuilder (Cell State -> rest) -> CellBuilder rest
withState key (CellBuilder f) =
    CellBuilder
        (\bs ->
            let
                parent =
                    f bs

                id =
                    parent.nextId

                cell =
                    Rad.cellFromInternal
                        { id = id
                        , key = bs.prefix ++ key
                        , codec = stateCodec
                        , initial = IForm.initialState
                        }
            in
            { nextId = id + 1
            , metas = ( id, stateCodec.encode IForm.initialState ) :: parent.metas
            , ctor = parent.ctor cell
            }
        )


{-| Construct a `Form fields` value bundling state cell, fields, and members.
Pure — call per render.
-}
over : Cell State -> fields -> List Member -> Form fields
over stateCell fieldsRec members =
    IForm.Form
        { stateId = Rad.cellId stateCell
        , fields = fieldsRec
        , members = members
        }


{-| Mark a plain `Cell` as a form field.
-}
field : Cell a -> Member
field cell =
    IForm.PlainMember
        { inputId = Rad.cellId cell
        , initial = Rad.cellEncodedInitial cell
        }


{-| Mark a `ValidatedCell` as a form field. Captures input/validation/
activation-seq ids and the member's validation reaction.
-}
validatedField : Rad.ValidatedCell err a -> Member
validatedField vcell =
    let
        c =
            IValidated.core vcell
    in
    IForm.ValidatedMember
        { inputId = c.inputId
        , validationId = c.validationId
        , activationSeqId = c.activationSeqId
        , initial = c.codec.encode c.initial
        , reactionGuts = Rad.internalValidationReactionGuts vcell
        }


{-| `True` iff any member's current registry value differs from the form's
pristine reference (snapshot when non-null, otherwise each member's initial).
-}
dirty : Form fields -> Rad.Source Bool
dirty (IForm.Form f) =
    ISource.Source
        { read =
            \registry ->
                let
                    state =
                        IForm.readState f.stateId registry

                    snapshotIsNull =
                        Decode.decodeValue (Decode.null ()) state.snapshot == Ok ()

                    pristineFor : Member -> Decode.Value
                    pristineFor member =
                        if snapshotIsNull then
                            memberInitial member

                        else
                            case
                                Decode.decodeValue
                                    (Decode.field
                                        (String.fromInt (memberInputId member))
                                        Decode.value
                                    )
                                    state.snapshot
                            of
                                Ok v ->
                                    v

                                Err _ ->
                                    memberInitial member

                    isMemberDirty member =
                        case Registry.get (memberInputId member) registry of
                            Just current ->
                                current /= pristineFor member

                            Nothing ->
                                False
                in
                List.any isMemberDirty f.members
        , codec = { encode = Encode.bool, decode = Decode.bool }
        }


memberInputId : Member -> Int
memberInputId member =
    case member of
        IForm.PlainMember m ->
            m.inputId

        IForm.ValidatedMember m ->
            m.inputId


memberInitial : Member -> Decode.Value
memberInitial member =
    case member of
        IForm.PlainMember m ->
            m.initial

        IForm.ValidatedMember m ->
            m.initial


{-| Bumps `submitSeq` and dispatches `validate` to each ValidatedMember.
-}
submit : Form fields -> Rad.Action model
submit (IForm.Form f) =
    IAction.Action
        (\registry ->
            let
                state =
                    IForm.readState f.stateId registry

                newState =
                    { state | submitSeq = state.submitSeq + 1 }

                r1 =
                    Registry.insert f.stateId (IForm.stateCodec.encode newState) registry

                bumpActivation member r =
                    case member of
                        IForm.ValidatedMember vm ->
                            let
                                current =
                                    Registry.get vm.activationSeqId r
                                        |> Maybe.andThen (Decode.decodeValue Decode.int >> Result.toMaybe)
                                        |> Maybe.withDefault 0
                            in
                            Registry.insert vm.activationSeqId (Encode.int (current + 1)) r

                        IForm.PlainMember _ ->
                            r
            in
            List.foldl bumpActivation r1 f.members
        )


{-| Restores all members to pristine value (snapshot or initial), zeros each
ValidatedMember's activation seq, sets validation slot to Dormant. Does NOT
modify submitSeq / lastResolvedSubmitSeq.
-}
reset : Form fields -> Rad.Action model
reset (IForm.Form f) =
    IAction.Action
        (\registry ->
            let
                state =
                    IForm.readState f.stateId registry

                snapshotIsNull =
                    Decode.decodeValue (Decode.null ()) state.snapshot == Ok ()

                pristineFor member =
                    if snapshotIsNull then
                        memberInitial member

                    else
                        case
                            Decode.decodeValue
                                (Decode.field (String.fromInt (memberInputId member)) Decode.value)
                                state.snapshot
                        of
                            Ok v ->
                                v

                            Err _ ->
                                memberInitial member

                resetMember member r =
                    let
                        r1 =
                            Registry.insert (memberInputId member) (pristineFor member) r
                    in
                    case member of
                        IForm.ValidatedMember vm ->
                            r1
                                |> Registry.insert vm.validationId dormantEncoded
                                |> Registry.insert vm.activationSeqId (Encode.int 0)

                        IForm.PlainMember _ ->
                            r1
            in
            List.foldl resetMember registry f.members
        )


dormantEncoded : Decode.Value
dormantEncoded =
    Encode.object [ ( "tag", Encode.string "Dormant" ) ]


{-| Bundled snapshot of the form's UI state. Suitable for rendering a submit
button. See `status` for precedence.
-}
type Status
    = Pristine
    | Editable
    | HasErrors
    | Validating
    | Submitting


{-| `True` iff submitSeq > lastResolvedSubmitSeq.
-}
submitPending : Form fields -> Rad.Source Bool
submitPending (IForm.Form f) =
    boolSource
        (\registry ->
            let
                s =
                    IForm.readState f.stateId registry
            in
            s.submitSeq > s.lastResolvedSubmitSeq
        )


{-| `True` iff any ValidatedMember's validation slot decodes to Invalid.
-}
invalid : Form fields -> Rad.Source Bool
invalid (IForm.Form f) =
    boolSource (\registry -> List.any (memberHasTag IForm.TagInvalid registry) f.members)


{-| `True` iff any ValidatedMember's validation slot decodes to Checking.
-}
checking : Form fields -> Rad.Source Bool
checking (IForm.Form f) =
    boolSource (\registry -> List.any (memberHasTag IForm.TagChecking registry) f.members)


{-| dirty AND not invalid AND not checking AND not submitPending.
-}
canSubmit : Form fields -> Rad.Source Bool
canSubmit form =
    boolSource
        (\registry ->
            Rad.readSource (dirty form) registry
                && not (Rad.readSource (invalid form) registry)
                && not (Rad.readSource (checking form) registry)
                && not (Rad.readSource (submitPending form) registry)
        )


{-| Bundled `Status`. Precedence: invalid → HasErrors; submitPending+checking
→ Validating; submitPending → Submitting; dirty → Editable; else Pristine.
-}
status : Form fields -> Rad.Source Status
status form =
    ISource.Source
        { read =
            \registry ->
                if Rad.readSource (invalid form) registry then
                    HasErrors

                else if Rad.readSource (submitPending form) registry && Rad.readSource (checking form) registry then
                    Validating

                else if Rad.readSource (submitPending form) registry then
                    Submitting

                else if Rad.readSource (dirty form) registry then
                    Editable

                else
                    Pristine
        , codec =
            { encode =
                \s ->
                    Encode.string
                        (case s of
                            Pristine ->
                                "Pristine"

                            Editable ->
                                "Editable"

                            HasErrors ->
                                "HasErrors"

                            Validating ->
                                "Validating"

                            Submitting ->
                                "Submitting"
                        )
            , decode =
                Decode.string
                    |> Decode.andThen
                        (\s ->
                            case s of
                                "Pristine" ->
                                    Decode.succeed Pristine

                                "Editable" ->
                                    Decode.succeed Editable

                                "HasErrors" ->
                                    Decode.succeed HasErrors

                                "Validating" ->
                                    Decode.succeed Validating

                                "Submitting" ->
                                    Decode.succeed Submitting

                                _ ->
                                    Decode.fail ("unknown Status tag: " ++ s)
                        )
            }
        }


boolSource : (Registry -> Bool) -> Rad.Source Bool
boolSource read =
    ISource.Source
        { read = read
        , codec = { encode = Encode.bool, decode = Decode.bool }
        }


memberHasTag : IForm.ValidationTag -> Registry -> Member -> Bool
memberHasTag tag registry member =
    case member of
        IForm.ValidatedMember m ->
            case Registry.get m.validationId registry of
                Just v ->
                    case Decode.decodeValue IForm.validationTagDecoder v of
                        Ok decoded ->
                            decoded == tag

                        Err _ ->
                            False

                Nothing ->
                    False

        IForm.PlainMember _ ->
            False


{-| Number of members in the form. For tests.
-}
memberCount : Form fields -> Int
memberCount (IForm.Form f) =
    List.length f.members


{-| Typed bundle of validators in a form, used to gate submission.
-}
type alias ValidatedGroup fields clean =
    IGroup.ValidatedGroup fields clean


{-| Read a group's clean values from registry. Returns `Just clean` iff every
validator is `Valid`. Mostly for tests.
-}
readGroup : ValidatedGroup fields clean -> fields -> Registry -> Maybe clean
readGroup =
    IGroup.readGroup


extractValid : (fields -> Rad.ValidatedCell err a) -> fields -> Registry -> Maybe a
extractValid getter fieldsRec registry =
    let
        c =
            IValidated.core (getter fieldsRec)

        validDecoder =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        if tag == "Valid" then
                            Decode.field "value" c.codec.decode

                        else
                            Decode.fail ("not Valid: " ++ tag)
                    )
    in
    Registry.get c.validationId registry
        |> Maybe.andThen (Decode.decodeValue validDecoder >> Result.toMaybe)


validationIdOf : (fields -> Rad.ValidatedCell err a) -> fields -> Int
validationIdOf getter fieldsRec =
    .validationId (IValidated.ref (getter fieldsRec))


{-| Group with a single validator. `clean` is the input type of the field.
-}
validators1 :
    (fields -> Rad.ValidatedCell err a)
    -> ValidatedGroup fields a
validators1 g1 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f ]
        , read = \f r -> extractValid g1 f r
        }


{-| Group with two validators. `clean` = `(a, b)`.
-}
validators2 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> ValidatedGroup fields ( a, b )
validators2 g1 g2 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f ]
        , read = \f r -> Maybe.map2 Tuple.pair (extractValid g1 f r) (extractValid g2 f r)
        }


{-| Group with three validators.
-}
validators3 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> ValidatedGroup fields ( a, b, c )
validators3 g1 g2 g3 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f ]
        , read =
            \f r ->
                Maybe.map3 (\a b c -> ( a, b, c ))
                    (extractValid g1 f r)
                    (extractValid g2 f r)
                    (extractValid g3 f r)
        }


{-| Group with four validators. `clean` = `( ( a, b ), ( c, d ) )`.
-}
validators4 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> (fields -> Rad.ValidatedCell err4 d)
    -> ValidatedGroup fields ( ( a, b ), ( c, d ) )
validators4 g1 g2 g3 g4 =
    IGroup.ValidatedGroup
        { ids = \f -> [ validationIdOf g1 f, validationIdOf g2 f, validationIdOf g3 f, validationIdOf g4 f ]
        , read =
            \f r ->
                Maybe.map2 Tuple.pair
                    (Maybe.map2 Tuple.pair (extractValid g1 f r) (extractValid g2 f r))
                    (Maybe.map2 Tuple.pair (extractValid g3 f r) (extractValid g4 f r))
        }


{-| Group with five validators. `clean` = `( ( a, b ), ( c, d, e ) )`.
-}
validators5 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> (fields -> Rad.ValidatedCell err4 d)
    -> (fields -> Rad.ValidatedCell err5 e)
    -> ValidatedGroup fields ( ( a, b ), ( c, d, e ) )
validators5 g1 g2 g3 g4 g5 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f
                , validationIdOf g2 f
                , validationIdOf g3 f
                , validationIdOf g4 f
                , validationIdOf g5 f
                ]
        , read =
            \f r ->
                Maybe.map2 Tuple.pair
                    (Maybe.map2 Tuple.pair (extractValid g1 f r) (extractValid g2 f r))
                    (Maybe.map3 (\c d e -> ( c, d, e ))
                        (extractValid g3 f r)
                        (extractValid g4 f r)
                        (extractValid g5 f r)
                    )
        }


{-| Group with six validators. `clean` = `( ( a, b, c ), ( d, e, ff ) )`.
-}
validators6 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> (fields -> Rad.ValidatedCell err4 d)
    -> (fields -> Rad.ValidatedCell err5 e)
    -> (fields -> Rad.ValidatedCell err6 ff)
    -> ValidatedGroup fields ( ( a, b, c ), ( d, e, ff ) )
validators6 g1 g2 g3 g4 g5 g6 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f
                , validationIdOf g2 f
                , validationIdOf g3 f
                , validationIdOf g4 f
                , validationIdOf g5 f
                , validationIdOf g6 f
                ]
        , read =
            \f r ->
                Maybe.map2 Tuple.pair
                    (Maybe.map3 (\a b c -> ( a, b, c ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                    )
                    (Maybe.map3 (\d e ff -> ( d, e, ff ))
                        (extractValid g4 f r)
                        (extractValid g5 f r)
                        (extractValid g6 f r)
                    )
        }


{-| Group with seven validators. `clean` = `( ( a, b, c ), ( d, e, ff, g ) )` where the second element is `( ( d, e ), ( ff, g ) )`.

Actually: `( ( a, b, c ), ( ( d, e ), ( ff, g ) ) )`.

-}
validators7 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> (fields -> Rad.ValidatedCell err4 d)
    -> (fields -> Rad.ValidatedCell err5 e)
    -> (fields -> Rad.ValidatedCell err6 ff)
    -> (fields -> Rad.ValidatedCell err7 g)
    -> ValidatedGroup fields ( ( a, b, c ), ( ( d, e ), ( ff, g ) ) )
validators7 g1 g2 g3 g4 g5 g6 g7 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f
                , validationIdOf g2 f
                , validationIdOf g3 f
                , validationIdOf g4 f
                , validationIdOf g5 f
                , validationIdOf g6 f
                , validationIdOf g7 f
                ]
        , read =
            \f r ->
                Maybe.map2 Tuple.pair
                    (Maybe.map3 (\a b c -> ( a, b, c ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                    )
                    (Maybe.map2 Tuple.pair
                        (Maybe.map2 Tuple.pair (extractValid g4 f r) (extractValid g5 f r))
                        (Maybe.map2 Tuple.pair (extractValid g6 f r) (extractValid g7 f r))
                    )
        }


{-| Group with eight validators. `clean` = `( ( a, b, c ), ( ( d, e ), ( ff, g, h ) ) )`.
-}
validators8 :
    (fields -> Rad.ValidatedCell err1 a)
    -> (fields -> Rad.ValidatedCell err2 b)
    -> (fields -> Rad.ValidatedCell err3 c)
    -> (fields -> Rad.ValidatedCell err4 d)
    -> (fields -> Rad.ValidatedCell err5 e)
    -> (fields -> Rad.ValidatedCell err6 ff)
    -> (fields -> Rad.ValidatedCell err7 g)
    -> (fields -> Rad.ValidatedCell err8 h)
    -> ValidatedGroup fields ( ( a, b, c ), ( ( d, e ), ( ff, g, h ) ) )
validators8 g1 g2 g3 g4 g5 g6 g7 g8 =
    IGroup.ValidatedGroup
        { ids =
            \f ->
                [ validationIdOf g1 f
                , validationIdOf g2 f
                , validationIdOf g3 f
                , validationIdOf g4 f
                , validationIdOf g5 f
                , validationIdOf g6 f
                , validationIdOf g7 f
                , validationIdOf g8 f
                ]
        , read =
            \f r ->
                Maybe.map2 Tuple.pair
                    (Maybe.map3 (\a b c -> ( a, b, c ))
                        (extractValid g1 f r)
                        (extractValid g2 f r)
                        (extractValid g3 f r)
                    )
                    (Maybe.map2 Tuple.pair
                        (Maybe.map2 Tuple.pair (extractValid g4 f r) (extractValid g5 f r))
                        (Maybe.map3 (\ff g_ h -> ( ff, g_, h ))
                            (extractValid g6 f r)
                            (extractValid g7 f r)
                            (extractValid g8 f r)
                        )
                    )
        }


{-| Transform a group's clean type. Useful for packing tuples into records.
-}
mapValidated : (a -> b) -> ValidatedGroup fields a -> ValidatedGroup fields b
mapValidated f (IGroup.ValidatedGroup g) =
    IGroup.ValidatedGroup
        { ids = g.ids
        , read = \fieldsRec registry -> Maybe.map f (g.read fieldsRec registry)
        }
