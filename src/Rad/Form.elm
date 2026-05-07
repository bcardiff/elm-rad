module Rad.Form exposing
    ( Form, Member, State, stateCodec
    , withState
    , over, field, validatedField
    , memberCount
    )

{-| Layer 5 — Forms. Designed for `import Rad.Form as Form`.


# Types

@docs Form, Member, State, stateCodec


# Builder

@docs withState


# Use-site construction

@docs over, field, validatedField


# Inspection

@docs memberCount

-}

import Rad exposing (Cell, CellBuilder, Codec)
import Rad.Internal.CellBuilder exposing (CellBuilder(..))
import Rad.Internal.Form as IForm
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


{-| Number of members in the form. For tests.
-}
memberCount : Form fields -> Int
memberCount (IForm.Form f) =
    List.length f.members
