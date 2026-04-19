module RequestTest exposing (suite)

import Expect
import Rad exposing (Request, mapRequestError, noRequest)
import Rad.Internal.Request as IR
import Task
import Test exposing (..)


suite : Test
suite =
    describe "Request"
        [ test "noRequest is the NoRequest variant" <|
            \_ ->
                case noRequest of
                    IR.NoRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected NoRequest"
        , test "mapRequestError on NoRequest is identity" <|
            \_ ->
                case mapRequestError (\_ -> "x") noRequest of
                    IR.NoRequest ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected NoRequest"
        , test "mapRequestError composes" <|
            \_ ->
                let
                    f n =
                        n + 1

                    g n =
                        n * 2

                    base =
                        IR.DispatchRequest (Task.fail 3)

                    composed =
                        base |> mapRequestError g |> mapRequestError f

                    oneShot =
                        base |> mapRequestError (\n -> f (g n))
                in
                case ( composed, oneShot ) of
                    ( IR.DispatchRequest _, IR.DispatchRequest _ ) ->
                        Expect.pass

                    _ ->
                        Expect.fail "expected both to be DispatchRequest"
        ]
