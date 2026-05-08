module PersistRestoreTest exposing (suite)

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


schemaOf builder =
    let
        (ICellBuilder.CellBuilder f) =
            builder

        result =
            f { nextId = 0, prefix = "" }
    in
    ( result.persist, result.metas )


initialRegistry metas =
    metas |> List.foldl (\( id, v ) -> Registry.insert id v) Registry.empty


suite : Test
suite =
    describe "Persist.restore"
        [ test "null flags returns initial registry unchanged" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            Encode.null
                in
                Expect.equal initial result
        , test "version mismatch returns initial registry unchanged" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 99 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n"
                                      , Encode.object
                                            [ ( "type", Encode.string "cell" )
                                            , ( "value", Encode.int 42 )
                                            ]
                                      )
                                    ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal initial result
        , test "valid stored data populates registry" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n"
                                      , Encode.object
                                            [ ( "type", Encode.string "cell" )
                                            , ( "value", Encode.int 42 )
                                            ]
                                      )
                                    ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal (Just (Encode.int 42)) (Registry.get 0 result)
        , test "missing cell with non-null-tolerant codec discards entire restore" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells", Encode.object [] )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal initial result
        , test "decode failure on a present blob discards entire restore" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    storedJson =
                        Encode.object
                            [ ( "version", Encode.int 1 )
                            , ( "cells"
                              , Encode.object
                                    [ ( "n"
                                      , Encode.object
                                            [ ( "type", Encode.string "cell" )
                                            , ( "value", Encode.string "not-an-int" )
                                            ]
                                      )
                                    ]
                              )
                            ]

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            storedJson
                in
                Expect.equal initial result
        , test "string flags get parsed as JSON" <|
            \_ ->
                let
                    ( schema, metas ) =
                        schemaOf init

                    initial =
                        initialRegistry metas

                    -- Pass flags as a string containing JSON (simulates the
                    -- raw string from localStorage being passed via flags).
                    flagsString =
                        "{\"version\":1,\"cells\":{\"n\":{\"type\":\"cell\",\"value\":99}}}"

                    flagsValue =
                        Encode.string flagsString

                    result =
                        IPersist.restore { key = "test", version = 1 }
                            schema
                            initial
                            flagsValue
                in
                Expect.equal (Just (Encode.int 99)) (Registry.get 0 result)
        ]
