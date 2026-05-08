module PersistEntryTest exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (build)
import Rad.Internal.CellBuilder as ICellBuilder
import Rad.Internal.Persist as IPersist
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias Model =
    { n : Rad.Cell Int }


init =
    build Model |> Rad.with "n" 7 Rad.intCodec


schemaResult =
    let
        (ICellBuilder.CellBuilder f) =
            init
    in
    f { nextId = 0, prefix = "" }


initialRegistry =
    schemaResult.metas
        |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty


suite : Test
suite =
    describe "PersistEntry — Cell a"
        [ test "with appends one schema entry with the cell's key" <|
            \_ ->
                case schemaResult.persist of
                    [ entry ] ->
                        Expect.equal "n" entry.key

                    _ ->
                        Expect.fail "expected exactly one persist entry"
        , test "encode reads the cell value from registry and produces correct blob" <|
            \_ ->
                let
                    entry =
                        case schemaResult.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"
                in
                case entry.encode initialRegistry of
                    Just blob ->
                        Expect.equal
                            (Ok 7)
                            (Decode.decodeValue (Decode.field "value" Decode.int) blob)

                    Nothing ->
                        Expect.fail "expected Just"
        , test "decode round-trips: encode then decode reproduces the registry" <|
            \_ ->
                let
                    entry =
                        case schemaResult.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"

                    blob =
                        case entry.encode initialRegistry of
                            Just b ->
                                b

                            Nothing ->
                                Debug.todo "encode failed"
                in
                case entry.decode blob Registry.empty of
                    Ok r ->
                        Expect.equal (Just (Encode.int 7)) (Registry.get 0 r)

                    Err e ->
                        Expect.fail ("decode failed: " ++ e)
        , test "DebouncedCell schema entry has correct key + type tag" <|
            \_ ->
                let
                    initD =
                        build (\d -> { d = d })
                            |> Rad.withDebounced "search" 500 "" Rad.stringCodec

                    (ICellBuilder.CellBuilder f) =
                        initD

                    result =
                        f { nextId = 0, prefix = "" }

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"
                in
                Expect.equal ( "search", "debounced" ) ( entry.key, entry.typeTag )
        , test "DebouncedCell encode/decode round-trips" <|
            \_ ->
                let
                    initD =
                        build (\d -> { d = d })
                            |> Rad.withDebounced "search" 500 "init-value" Rad.stringCodec

                    (ICellBuilder.CellBuilder f) =
                        initD

                    result =
                        f { nextId = 0, prefix = "" }

                    initRegistry =
                        result.metas
                            |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty

                    entry =
                        case result.persist of
                            [ e ] ->
                                e

                            _ ->
                                Debug.todo "expected one entry"

                    blob =
                        case entry.encode initRegistry of
                            Just b ->
                                b

                            Nothing ->
                                Debug.todo "encode failed"

                    decoded =
                        case entry.decode blob Registry.empty of
                            Ok r ->
                                r

                            Err e ->
                                Debug.todo ("decode failed: " ++ e)
                in
                Expect.equal
                    (Just (Encode.string "init-value"))
                    (Registry.get 0 decoded)
        ]
