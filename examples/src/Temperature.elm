module Temperature exposing (main)

import Rad exposing (AppDef, AppModel, Cell, Source, build, derive, run, stringCodec, toSource, with)
import Rad.Engine exposing (Msg)
import Rad.Read as Read
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { celsius : Cell String }


type alias Computed =
    { fahrenheit : Source String
    , kelvin : Source String
    }


app : AppDef (SimpleView Model) Model Computed
app =
    { init =
        build Model |> with "celsius" "0" stringCodec
    , computed =
        \model ->
            { fahrenheit =
                derive stringCodec
                    (Read.map (formatTemp << toFahrenheit)
                        (Read.read (toSource model.celsius))
                    )
            , kelvin =
                derive stringCodec
                    (Read.map (formatTemp << toKelvin)
                        (Read.read (toSource model.celsius))
                    )
            }
    , view =
        \model c ->
            col
                [ input { label = "°C", cell = model.celsius }
                , watch c.fahrenheit (\f -> text ("°F: " ++ f))
                , watch c.kelvin (\k -> text ("K: " ++ k))
                ]
    , reactions = \_ _ -> []
    }


main : Program () (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app


toFahrenheit : String -> Maybe Float
toFahrenheit s =
    String.toFloat s |> Maybe.map (\c -> c * 9 / 5 + 32)


toKelvin : String -> Maybe Float
toKelvin s =
    String.toFloat s |> Maybe.map (\c -> c + 273.15)


formatTemp : Maybe Float -> String
formatTemp m =
    case m of
        Just f ->
            String.fromFloat f

        Nothing ->
            "—"
