module ValidatedLatestWinsTest exposing (suite)

import Expect
import Json.Decode as Decode
import Rad
    exposing
        ( ValidatedCell
        , Validation(..)
        , build
        , stringCodec
        , sync
        , validationCodec
        , withValidated
        )
import Rad.Internal.Reaction as IReaction
import Rad.Internal.Registry as Registry
import Rad.Internal.Validated as IValidated
import Test exposing (..)


type alias Model =
    { name : ValidatedCell String String }


init : Rad.CellBuilder Model
init =
    build Model
        |> withValidated "name" "hello" stringCodec stringCodec (sync Ok)


readValidation : Int -> Registry.Registry -> Maybe (Validation String String)
readValidation id registry =
    let
        c =
            validationCodec stringCodec stringCodec
    in
    Registry.get id registry
        |> Maybe.andThen (Decode.decodeValue c.decode >> Result.toMaybe)


getReaction : Rad.ValidatedCell err a -> Maybe (IReaction.Reaction model)
getReaction vcell =
    Rad.validationReactions vcell |> List.head


suite : Test
suite =
    describe "Validated latest-wins"
        [ test "writeResult overwrites — runtime owns seq filtering" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    c =
                        validationCodec stringCodec stringCodec

                    encodedStale =
                        c.encode (Valid "stale")

                    encodedFresh =
                        c.encode (Valid "fresh")
                in
                case getReaction model.name of
                    Just (IReaction.Reaction r) ->
                        let
                            registryBoth =
                                registry0
                                    |> r.writeResult encodedStale
                                    |> r.writeResult encodedFresh

                            registryFreshFirst =
                                registry0
                                    |> r.writeResult encodedFresh
                        in
                        Expect.equal
                            (readValidation (IValidated.ref model.name).validationId registryBoth)
                            (readValidation (IValidated.ref model.name).validationId registryFreshFirst)

                    Nothing ->
                        Expect.fail "no reaction"
        , test "writeResult writes the exact bytes passed, no filtering" <|
            \_ ->
                let
                    ( model, registry0 ) =
                        Rad.runBuilder init

                    c =
                        validationCodec stringCodec stringCodec

                    invalidEncoded =
                        c.encode (Invalid [ "nope" ])
                in
                case getReaction model.name of
                    Just (IReaction.Reaction r) ->
                        let
                            registry1 =
                                r.writeResult invalidEncoded registry0
                        in
                        Expect.equal (Just (Invalid [ "nope" ]))
                            (readValidation (IValidated.ref model.name).validationId registry1)

                    Nothing ->
                        Expect.fail "no reaction"
        ]
