module Rad.Internal.Persist exposing (PersistEntry, cellEntry)

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
