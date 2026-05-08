module Rad.Internal.Persist exposing (PersistEntry, cellEntry, debouncedEntry)

{-| Internal: per-cell persistence schema entry. Each cell-building primitive
(`with`, `withDebounced`, `withValidated`, `Form.withState`) appends one entry
to `BuildResult.persist`. The runtime walks this list to save and restore.

User code never references `PersistEntry` directly; it's an internal
collaboration between builders and the runtime.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Rad.Internal.Registry as Registry exposing (Registry)


type alias PersistEntry =
    { key : String
    , typeTag : String
    , encode : Registry -> Maybe Encode.Value
    , decode : Encode.Value -> Registry -> Result String Registry
    }


{-| Build a PersistEntry for a `Cell a`-typed slot.

Encoding format: `{"type": "cell", "value": <encoded a>}`.

Decode behavior:

  - If blob has `type=cell` field, decode `value` via the user's codec.
  - If blob is `null` (missing-cell case), try the user's codec on `null`
    directly. If accepted, use the decoded value (graceful schema drift).
  - Otherwise: strict-fail (returns Err).

-}
cellEntry :
    { id : Int
    , key : String
    , codec : { encode : a -> Encode.Value, decode : Decode.Decoder a }
    }
    -> PersistEntry
cellEntry r =
    { key = r.key
    , typeTag = "cell"
    , encode =
        \registry ->
            Registry.get r.id registry
                |> Maybe.map
                    (\v ->
                        Encode.object
                            [ ( "type", Encode.string "cell" )
                            , ( "value", v )
                            ]
                    )
    , decode =
        \blob registry ->
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "cell" then
                                    Decode.field "value" r.codec.decode

                                else
                                    Decode.fail ("expected type=cell, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok value ->
                    Ok (Registry.insert r.id (r.codec.encode value) registry)

                Err _ ->
                    -- Fallback: try the codec on the blob directly
                    -- (handles `null` for missing cells).
                    case Decode.decodeValue r.codec.decode blob of
                        Ok value ->
                            Ok (Registry.insert r.id (r.codec.encode value) registry)

                        Err e ->
                            Err (Decode.errorToString e)
    }


{-| Build a PersistEntry for a `DebouncedCell a`. Encodes the three slots
(raw, settled, timerSeq) as one blob.

Format: `{"type": "debounced", "raw": <a>, "settled": <a>, "timerSeq": <int>}`.

Missing-cell fallback: tries to decode null via the value codec; if accepted,
initializes raw=settled=null-decoded, timerSeq=0.

-}
debouncedEntry :
    { rawId : Int
    , settledId : Int
    , timerSeqId : Int
    , key : String
    , codec : { encode : a -> Encode.Value, decode : Decode.Decoder a }
    }
    -> PersistEntry
debouncedEntry r =
    { key = r.key
    , typeTag = "debounced"
    , encode =
        \registry ->
            Maybe.map3
                (\raw settled timerSeq ->
                    Encode.object
                        [ ( "type", Encode.string "debounced" )
                        , ( "raw", raw )
                        , ( "settled", settled )
                        , ( "timerSeq", timerSeq )
                        ]
                )
                (Registry.get r.rawId registry)
                (Registry.get r.settledId registry)
                (Registry.get r.timerSeqId registry)
    , decode =
        \blob registry ->
            case
                Decode.decodeValue
                    (Decode.field "type" Decode.string
                        |> Decode.andThen
                            (\tag ->
                                if tag == "debounced" then
                                    Decode.map3
                                        (\raw settled timerSeq -> ( raw, settled, timerSeq ))
                                        (Decode.field "raw" r.codec.decode)
                                        (Decode.field "settled" r.codec.decode)
                                        (Decode.field "timerSeq" Decode.int)

                                else
                                    Decode.fail ("expected type=debounced, got " ++ tag)
                            )
                    )
                    blob
            of
                Ok ( raw, settled, timerSeq ) ->
                    Ok
                        (registry
                            |> Registry.insert r.rawId (r.codec.encode raw)
                            |> Registry.insert r.settledId (r.codec.encode settled)
                            |> Registry.insert r.timerSeqId (Encode.int timerSeq)
                        )

                Err _ ->
                    -- Fallback: decode null via value codec; if accepted,
                    -- raw = settled = null-decoded, timerSeq = 0.
                    case Decode.decodeValue r.codec.decode blob of
                        Ok value ->
                            Ok
                                (registry
                                    |> Registry.insert r.rawId (r.codec.encode value)
                                    |> Registry.insert r.settledId (r.codec.encode value)
                                    |> Registry.insert r.timerSeqId (Encode.int 0)
                                )

                        Err e ->
                            Err (Decode.errorToString e)
    }
