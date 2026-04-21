module ComponentDispatchTest exposing (suite)

import Expect
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , defineComponent
        , embed
        , include
        , intCodec
        , with
        , withInstance
        )
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model String CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> "counter-view"
        , reactions = \_ _ -> []
        }


type alias Model =
    { counter : CounterCells }


init : Rad.CellBuilder Model
init =
    build Model |> withInstance "counter" counterComponent


suite : Test
suite =
    describe "embed and include"
        [ test "embed returns the component's view output" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal "counter-view" (embed counterComponent model.counter)
        , test "include returns the component's reactions list (empty here)" <|
            \_ ->
                let
                    ( model, _ ) =
                        Rad.runBuilder init
                in
                Expect.equal 0 (List.length (include counterComponent model.counter))
        ]
