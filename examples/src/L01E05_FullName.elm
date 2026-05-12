module L01E05_FullName exposing (main)

import Json.Decode
import Rad exposing (AppDef, AppModel, Cell, Source, build, derive, run, stringCodec, toSource, with)
import Rad.Internal.Engine exposing (Msg)
import Rad.Read as Read
import SimpleView exposing (SimpleView, col, input, simpleViewEngine, text, watch)


type alias Model =
    { first : Cell String
    , last : Cell String
    }


type alias Computed =
    { full : Source String }


app : AppDef (SimpleView Model) Model Computed
app =
    { init =
        build Model
            |> with "first" "" stringCodec
            |> with "last" "" stringCodec
    , computed =
        \model ->
            { full =
                derive stringCodec
                    (Read.map2 (\f l -> f ++ " " ++ l)
                        (Read.read (toSource model.first))
                        (Read.read (toSource model.last))
                    )
            }
    , view =
        \model c ->
            col
                [ input { label = "First", cell = model.first }
                , input { label = "Last", cell = model.last }
                , watch c.full (\name -> text ("Full name: " ++ name))
                ]
    , reactions = \_ _ -> []
    , persist = Nothing
    }


main : Program Json.Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
