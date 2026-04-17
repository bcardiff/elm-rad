module CodecTest exposing (suite)

import Expect
import Test exposing (..)


suite : Test
suite =
    test "elm-test harness works" <|
        \_ -> Expect.equal 1 1
