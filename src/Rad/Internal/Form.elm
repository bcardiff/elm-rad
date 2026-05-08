module Rad.Internal.Form exposing
    ( Form(..)
    , Member(..)
    , State
    , ValidationTag(..)
    , initialState
    , readState
    , stateCodec
    , validationTagDecoder
    )

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry exposing (Registry)


type alias State =
    { snapshot : Decode.Value
    , submitSeq : Int
    , lastResolvedSubmitSeq : Int
    }


initialState : State
initialState =
    { snapshot = Encode.null
    , submitSeq = 0
    , lastResolvedSubmitSeq = 0
    }


stateCodec : { encode : State -> Decode.Value, decode : Decode.Decoder State }
stateCodec =
    { encode =
        \s ->
            Encode.object
                [ ( "snapshot", s.snapshot )
                , ( "submitSeq", Encode.int s.submitSeq )
                , ( "lastResolvedSubmitSeq", Encode.int s.lastResolvedSubmitSeq )
                ]
    , decode =
        Decode.oneOf
            [ Decode.null initialState
            , Decode.map3 State
                (Decode.field "snapshot" Decode.value)
                (Decode.field "submitSeq" Decode.int)
                (Decode.field "lastResolvedSubmitSeq" Decode.int)
            ]
    }


readState : Int -> Registry -> State
readState stateId registry =
    case Registry.get stateId registry of
        Just v ->
            Result.withDefault initialState (Decode.decodeValue stateCodec.decode v)

        Nothing ->
            initialState


type Form fields
    = Form
        { stateId : Int
        , fields : fields
        , members : List Member
        }


type Member
    = PlainMember
        { inputId : Int
        , initial : Decode.Value
        }
    | ValidatedMember
        { inputId : Int
        , validationId : Int
        , activationSeqId : Int
        , initial : Decode.Value
        , reactionGuts : IReaction.Guts
        }


type ValidationTag
    = TagDormant
    | TagChecking
    | TagValid
    | TagInvalid


validationTagDecoder : Decode.Decoder ValidationTag
validationTagDecoder =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "Dormant" ->
                        Decode.succeed TagDormant

                    "Checking" ->
                        Decode.succeed TagChecking

                    "Valid" ->
                        Decode.succeed TagValid

                    "Invalid" ->
                        Decode.succeed TagInvalid

                    _ ->
                        Decode.fail ("unknown Validation tag: " ++ s)
            )
