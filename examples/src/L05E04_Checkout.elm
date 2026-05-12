module L05E04_Checkout exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , ComponentDef
        , ValidatedCell
        , build
        , defineComponent
        , embed
        , maybeCodec
        , run
        , set
        , stringCodec
        , sync
        , toSource
        , with
        , withInstance
        , withValidated
        )
import Rad.Form as Form exposing (Status(..))
import Rad.Internal.Engine exposing (Msg)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)



-- Domain types


type alias Address =
    { street : String
    , city : String
    , zip : String
    }


type alias Checkout =
    { billing : Address
    , shipping : Address
    }


addressCodec : Rad.Codec Address
addressCodec =
    { encode =
        \a ->
            Encode.object
                [ ( "street", Encode.string a.street )
                , ( "city", Encode.string a.city )
                , ( "zip", Encode.string a.zip )
                ]
    , decode =
        Decode.map3 Address
            (Decode.field "street" Decode.string)
            (Decode.field "city" Decode.string)
            (Decode.field "zip" Decode.string)
    }


checkoutCodec : Rad.Codec Checkout
checkoutCodec =
    { encode =
        \c ->
            Encode.object
                [ ( "billing", addressCodec.encode c.billing )
                , ( "shipping", addressCodec.encode c.shipping )
                ]
    , decode =
        Decode.map2 Checkout
            (Decode.field "billing" addressCodec.decode)
            (Decode.field "shipping" addressCodec.decode)
    }



-- Validators


nonEmpty : String -> String -> Result (List String) String
nonEmpty label s =
    if String.trim s == "" then
        Err [ label ++ " is required" ]

    else
        Ok s


zipFormat : String -> Result (List String) String
zipFormat s =
    if String.length s >= 4 then
        Ok s

    else
        Err [ "Zip must be at least 4 characters" ]



-- Component: reusable address form


type alias AddressFields =
    { street : ValidatedCell String String
    , city : ValidatedCell String String
    , zip : ValidatedCell String String
    }


addressComponent : ComponentDef Model (SimpleView Model) AddressFields {}
addressComponent =
    defineComponent
        { init =
            build AddressFields
                |> withValidated "street" "" stringCodec stringCodec (sync (nonEmpty "Street"))
                |> withValidated "city" "" stringCodec stringCodec (sync (nonEmpty "City"))
                |> withValidated "zip" "" stringCodec stringCodec (sync zipFormat)
        , computed = \_ -> {}
        , view = \fs _ -> renderAddress fs
        , reactions = \_ _ -> []
        }


renderAddress : AddressFields -> SimpleView Model
renderAddress fs =
    col
        [ input { label = "Street", cell = Rad.input fs.street }
        , watch (Rad.validation fs.street) renderValidationHint
        , input { label = "City", cell = Rad.input fs.city }
        , watch (Rad.validation fs.city) renderValidationHint
        , input { label = "Zip", cell = Rad.input fs.zip }
        , watch (Rad.validation fs.zip) renderValidationHint
        ]


renderValidationHint : Rad.Validation String String -> SimpleView Model
renderValidationHint v =
    case v of
        Rad.Dormant ->
            text ""

        Rad.Checking ->
            text "(checking...)"

        Rad.Valid _ ->
            text "✓"

        Rad.Invalid errs ->
            text (String.join "; " errs)



-- Parent model


type alias Model =
    { billing : AddressFields
    , shipping : AddressFields
    , checkoutForm : Cell Form.State
    , saved : Cell (Maybe Checkout)
    }


type alias Fields =
    { billStreet : ValidatedCell String String
    , billCity : ValidatedCell String String
    , billZip : ValidatedCell String String
    , shipStreet : ValidatedCell String String
    , shipCity : ValidatedCell String String
    , shipZip : ValidatedCell String String
    }


fields : Model -> Fields
fields m =
    { billStreet = m.billing.street
    , billCity = m.billing.city
    , billZip = m.billing.zip
    , shipStreet = m.shipping.street
    , shipCity = m.shipping.city
    , shipZip = m.shipping.zip
    }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.checkoutForm
        (fields m)
        [ Form.validatedField m.billing.street
        , Form.validatedField m.billing.city
        , Form.validatedField m.billing.zip
        , Form.validatedField m.shipping.street
        , Form.validatedField m.shipping.city
        , Form.validatedField m.shipping.zip
        ]


checkoutGroup : Form.ValidatedGroup Fields Checkout
checkoutGroup =
    Form.validators6
        (\bs bc bz ss sc sz ->
            { billing = Address bs bc bz
            , shipping = Address ss sc sz
            }
        )
        .billStreet
        .billCity
        .billZip
        .shipStreet
        .shipCity
        .shipZip



-- App


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withInstance "billing" addressComponent
            |> withInstance "shipping" addressComponent
            |> Form.withState "checkout-form"
            |> with "saved" Nothing (maybeCodec checkoutCodec)
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ text "Billing"
                , embed addressComponent model.billing
                , text "Shipping"
                , embed addressComponent model.shipping
                , watch (Form.status (theForm model)) renderStatusHint
                , button { label = "Save", onClick = Form.submit (theForm model) }
                , button { label = "Reset", onClick = Form.reset (theForm model) }
                , watch (toSource model.saved) renderSaved
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onValid (theForm model)
                        checkoutGroup
                        (\checkout -> set model.saved (Just checkout))
                   ]
    , persist = Nothing
    }



-- View helpers


renderStatusHint : Status -> SimpleView Model
renderStatusHint status =
    case status of
        Pristine ->
            text "(Saved ✓)"

        Editable ->
            text "Ready to save"

        HasErrors ->
            text "(fix errors before saving)"

        Validating ->
            text "Checking..."

        Submitting ->
            text "Saving..."


renderSaved : Maybe Checkout -> SimpleView Model
renderSaved m =
    case m of
        Nothing ->
            text ""

        Just c ->
            col
                [ text "Saved checkout:"
                , text ("Billing: " ++ formatAddress c.billing)
                , text ("Shipping: " ++ formatAddress c.shipping)
                ]


formatAddress : Address -> String
formatAddress a =
    a.street ++ ", " ++ a.city ++ " " ++ a.zip


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
