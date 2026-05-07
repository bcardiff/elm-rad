module Rad.Form exposing
    ( Form, Member, State, stateCodec
    , withState
    , over, field, validatedField
    , dirty, submit, reset
    , Status(..), status, canSubmit, submitPending, invalid, checking
    , memberCount
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
