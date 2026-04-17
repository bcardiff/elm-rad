module Main exposing (main)

import Browser
import Html exposing (Html, h1, text)


main : Program () () Never
main =
    Browser.sandbox
        { init = ()
        , update = \_ _ -> ()
        , view = view
        }


view : () -> Html Never
view _ =
    h1 [] [ text "elm-rad examples" ]
