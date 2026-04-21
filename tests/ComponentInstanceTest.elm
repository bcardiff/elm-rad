module ComponentInstanceTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( Cell
        , ComponentDef
        , build
        , cellKey
        , defineComponent
        , intCodec
        , with
        , withInstance
        )
import Rad.Internal.Registry as Registry
import Test exposing (..)


type alias CounterCells =
    { n : Cell Int }


counterComponent : ComponentDef model () CounterCells {}
counterComponent =
    defineComponent
        { init = build CounterCells |> with "n" 0 intCodec
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \_ _ -> []
        }


type alias SingleInstance =
    { a : CounterCells }


type alias TwoInstances =
    { a : CounterCells, b : CounterCells }


type alias NestedCells =
    { outer : Cell Int, inner : CounterCells }


nestedComponent : ComponentDef model () NestedCells {}
nestedComponent =
    defineComponent
        { init =
            build NestedCells
                |> with "outer" 99 intCodec
                |> withInstance "inner" counterComponent
        , computed = \_ -> {}
        , view = \_ _ -> ()
        , reactions = \_ _ -> []
        }


type alias Outer =
    { nested : NestedCells }


suite : Test
suite =
    describe "withInstance"
        [ test "single instance produces namespaced key" <|
            \_ ->
                let
                    init_ =
                        build SingleInstance |> withInstance "a" counterComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal "a.n" (cellKey model.a.n)
        , test "two instances produce distinct namespaced keys" <|
            \_ ->
                let
                    init_ =
                        build TwoInstances
                            |> withInstance "a" counterComponent
                            |> withInstance "b" counterComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal
                    { a = "a.n", b = "b.n" }
                    { a = cellKey model.a.n, b = cellKey model.b.n }
        , test "nested instance produces doubly-namespaced keys" <|
            \_ ->
                let
                    init_ =
                        build Outer |> withInstance "outer" nestedComponent

                    ( model, _ ) =
                        Rad.runBuilder init_
                in
                Expect.equal
                    { keyOuter = "outer.outer", keyInner = "outer.inner.n" }
                    { keyOuter = cellKey model.nested.outer
                    , keyInner = cellKey model.nested.inner.n
                    }
        , test "registry contains entries at the allocated IDs" <|
            \_ ->
                let
                    init_ =
                        build TwoInstances
                            |> withInstance "a" counterComponent
                            |> withInstance "b" counterComponent

                    ( model, registry ) =
                        Rad.runBuilder init_

                    valueFor cell =
                        Rad.readSource (Rad.toSource cell) registry
                in
                Expect.equal
                    { a = 0, b = 0 }
                    { a = valueFor model.a.n, b = valueFor model.b.n }
        ]
