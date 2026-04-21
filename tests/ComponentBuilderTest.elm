module ComponentBuilderTest exposing (suite)

import Expect
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , defineComponent
        , intCodec
        , with
        )
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model (String -> String) CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> \s -> s
        , reactions = \_ _ -> []
        }


suite : Test
suite =
    describe "defineComponent"
        [ test "constructs a ComponentDef usable as a type alias" <|
            \_ ->
                -- Simply exercising the constructor is enough; the type-check
                -- is the assertion.
                let
                    _ =
                        counterComponent
                in
                Expect.pass
        ]
