module ValidatorTest exposing (suite)

import Expect
import Rad exposing (Validation(..), async, compose, runSyncOnly, sync)
import Rad.Internal.Request as IRequest
import Task
import Test exposing (..)


suite : Test
suite =
    describe "Validator evaluation via runSyncOnly"
        [ test "Sync Ok returns Just (Valid a)" <|
            \_ ->
                runSyncOnly (sync Ok) "hello"
                    |> Expect.equal (Just (Valid "hello"))
        , test "Sync Err returns Just (Invalid errs)" <|
            \_ ->
                let
                    v =
                        sync (\_ -> Err [ "bad" ])
                in
                runSyncOnly v "hello"
                    |> Expect.equal (Just (Invalid [ "bad" ]))
        , test "Async returns Nothing (can't run sync)" <|
            \_ ->
                let
                    v =
                        async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                in
                runSyncOnly v "hello"
                    |> Expect.equal Nothing
        , test "Compose [] returns Just (Valid value)" <|
            \_ ->
                runSyncOnly (compose []) "hello"
                    |> Expect.equal (Just (Valid "hello"))
        , test "Compose [Sync Ok, Sync Ok] runs both" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\s -> Ok (s ++ "1"))
                            , sync (\s -> Ok (s ++ "2"))
                            ]
                in
                runSyncOnly v "x"
                    |> Expect.equal (Just (Valid "x12"))
        , test "Compose [Sync Err, Sync Ok] short-circuits at first failure" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\_ -> Err [ "first" ])
                            , sync (\_ -> Err [ "second — should not run" ])
                            ]
                in
                runSyncOnly v "x"
                    |> Expect.equal (Just (Invalid [ "first" ]))
        , test "Compose [Sync Err, Async ...] doesn't reach the async" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync (\_ -> Err [ "blocked" ])
                            , async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                            ]
                in
                runSyncOnly v "x"
                    |> Expect.equal (Just (Invalid [ "blocked" ]))
        , test "Compose [Sync Ok, Async ...] reaches async, returns Nothing" <|
            \_ ->
                let
                    v =
                        compose
                            [ sync Ok
                            , async (\_ -> IRequest.DispatchRequest (Task.succeed "x"))
                            ]
                in
                runSyncOnly v "hello"
                    |> Expect.equal Nothing
        ]
