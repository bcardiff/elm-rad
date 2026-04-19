module Rad.Http exposing
    ( Handler, prodHandler
    , RequestError(..), requestErrorCodec
    , httpGet, httpPost
    )

{-| HTTP effect library for `elm-rad`. Core `Rad` has no HTTP dependency;
this module owns `elm/http` entirely.


## Handler

@docs Handler, prodHandler


## Errors

@docs RequestError, requestErrorCodec


## Requests

@docs httpGet, httpPost

-}

import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Rad exposing (Codec, Request)
import Rad.Internal.Request as IRequest
import Task exposing (Task)


{-| A handler abstracts over how HTTP requests are actually made, so tests can
inject mock responses without touching `elm/http`.
-}
type alias Handler =
    { httpGet : String -> Task RequestError String
    , httpPost : String -> Encode.Value -> Task RequestError String
    }


{-| The production handler — delegates to `elm/http`.
-}
prodHandler : Handler
prodHandler =
    { httpGet = \url -> httpTask "GET" url Http.emptyBody
    , httpPost = \url body -> httpTask "POST" url (Http.jsonBody body)
    }


{-| Errors surfaced by `Rad.Http` request builders.
-}
type RequestError
    = Timeout
    | NetworkError
    | BadStatus Int
    | BadBody String


{-| A codec for `RequestError`. Useful as a default error codec when wrapping
HTTP results in `Remote err a`.
-}
requestErrorCodec : Codec RequestError
requestErrorCodec =
    let
        encode err =
            case err of
                Timeout ->
                    Encode.object [ ( "tag", Encode.string "Timeout" ) ]

                NetworkError ->
                    Encode.object [ ( "tag", Encode.string "NetworkError" ) ]

                BadStatus n ->
                    Encode.object
                        [ ( "tag", Encode.string "BadStatus" )
                        , ( "status", Encode.int n )
                        ]

                BadBody s ->
                    Encode.object
                        [ ( "tag", Encode.string "BadBody" )
                        , ( "message", Encode.string s )
                        ]

        decode =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "Timeout" ->
                                Decode.succeed Timeout

                            "NetworkError" ->
                                Decode.succeed NetworkError

                            "BadStatus" ->
                                Decode.map BadStatus (Decode.field "status" Decode.int)

                            "BadBody" ->
                                Decode.map BadBody (Decode.field "message" Decode.string)

                            other ->
                                Decode.fail ("unknown RequestError tag: " ++ other)
                    )
    in
    { encode = encode, decode = decode }


{-| Build a GET request. The decoder is applied to the response body.
-}
httpGet : Handler -> String -> Decode.Decoder a -> Request RequestError a
httpGet handler url decoder =
    handler.httpGet url
        |> Task.andThen (decodeBody decoder)
        |> IRequest.dispatch


{-| Build a POST request. The body is sent as JSON; the decoder is applied
to the response.
-}
httpPost : Handler -> String -> Encode.Value -> Decode.Decoder a -> Request RequestError a
httpPost handler url body decoder =
    handler.httpPost url body
        |> Task.andThen (decodeBody decoder)
        |> IRequest.dispatch



-- INTERNALS


decodeBody : Decode.Decoder a -> String -> Task RequestError a
decodeBody decoder body =
    case Decode.decodeString decoder body of
        Ok v ->
            Task.succeed v

        Err e ->
            Task.fail (BadBody (Decode.errorToString e))


httpTask : String -> String -> Http.Body -> Task RequestError String
httpTask method url body =
    Http.task
        { method = method
        , headers = []
        , url = url
        , body = body
        , resolver = Http.stringResolver stringResolver
        , timeout = Nothing
        }


stringResolver : Http.Response String -> Result RequestError String
stringResolver response =
    case response of
        Http.BadUrl_ url ->
            Err (BadBody ("bad url: " ++ url))

        Http.Timeout_ ->
            Err Timeout

        Http.NetworkError_ ->
            Err NetworkError

        Http.BadStatus_ meta _ ->
            Err (BadStatus meta.statusCode)

        Http.GoodStatus_ _ body ->
            Ok body
