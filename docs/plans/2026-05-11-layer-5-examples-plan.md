# Layer 5 Examples Implementation Plan (L05E03 signup, L05E04 checkout)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new Layer 5 examples — `L05E03_Signup` (real submit with success/failure paths + `mapValidated`) and `L05E04_Checkout` (parent-level form over two `ComponentDef` instances + `validators6`).

**Architecture:** Each example is one Elm module + one HTML harness + vite/index wiring. L05E03 reuses the existing `/api/username-check` mock endpoint and adds one new `/api/signup` endpoint. L05E04 is client-only (no HTTP).

**Tech Stack:** Elm 0.19.1, `vite-plugin-elm`, the bundled `SimpleView` engine, the existing `mock-api-plugin.js`.

**Workflow conventions:**
- Commit directly on `main`, atomic commits, single-line imperative messages.
- Run `(cd examples && npx --yes elm-format src --yes)` before each Elm commit.
- Verify with `cd examples && npm run build` after each task.
- No `Co-Authored-By` trailers.
- No new package tests; existing framework test suites cover the underlying machinery.

**Design-doc deviations:**
- The design proposed adding `/api/check-username` as a new endpoint. The existing `/api/username-check` (in `mock-api-plugin.js`) covers the same need. Plan uses the existing endpoint; only `/api/signup` is added.

---

## Task 1: Add `/api/signup` mock endpoint

**Files:**
- Modify: `examples/mock-api-plugin.js`

- [ ] **Step 1: Verify baseline build.**

```
cd examples && npm run build
```
Expected: success — 22 entries (current count after Layer 7).

- [ ] **Step 2: Edit `examples/mock-api-plugin.js`.** Find the `/api/username-check` middleware block and add `/api/signup` immediately after it (inside the same `configureServer(server)` body, before the closing `},`).

```javascript
// POST /api/signup
// 200 on success; 400 if the username is "fail" (deterministic failure path).
server.middlewares.use("/api/signup", async (req, res, next) => {
  if (req.method !== "POST") {
    res.statusCode = 405;
    res.end();
    return;
  }
  const raw = await readBody(req);
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_e) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: "invalid json" }));
    return;
  }
  if (parsed.username === "fail") {
    setTimeout(() => {
      res.statusCode = 400;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ error: "username 'fail' is reserved" }));
    }, 1500);
    return;
  }
  sendJson(res, { ok: true }, 1500);
});
```

(Uses the existing `readBody`/`sendJson` helpers. Delay 1500ms to match the username-check delay; submit feels uniform.)

- [ ] **Step 3: Verify the dev server still runs (skip if not testing live):**

```
cd examples && npm run dev
```
Expected: starts cleanly. Stop with Ctrl-C.

- [ ] **Step 4: Build still succeeds (mock-api-plugin only affects dev, not build, but worth sanity-checking).**

```
cd examples && npm run build
```
Expected: success — 22 entries.

- [ ] **Step 5: Commit.**

```
git add examples/mock-api-plugin.js
git commit -m "Add /api/signup mock endpoint"
```

---

## Task 2: Ship L05E03 signup example

**Files:**
- Create: `examples/src/L05E03_Signup.elm`
- Create: `examples/L05E03-signup.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Read one existing example for SimpleView shape reference.** E.g. `examples/src/ProfileForm.elm` (the existing Layer 5 reference). Note the `SimpleView` import list, the `input` constructor shape, and the `Form.over`/`onSubmit` pattern.

- [ ] **Step 2: Write `examples/src/L05E03_Signup.elm`:**

```elm
module L05E03_Signup exposing (main)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Rad
    exposing
        ( AppDef
        , AppModel
        , Cell
        , Remote(..)
        , ValidatedCell
        , andThenRequest
        , async
        , build
        , compose
        , remoteCodec
        , run
        , stringCodec
        , sync
        , toSource
        , with
        , withValidated
        )
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import Rad.Http as Http exposing (RequestError, prodHandler, requestErrorCodec)
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)


type alias Model =
    { username : ValidatedCell String String
    , email : ValidatedCell String String
    , password : ValidatedCell String String
    , submitResult : Cell (Remote RequestError ())
    , formState : Cell Form.State
    }


type alias Fields =
    { username : ValidatedCell String String
    , email : ValidatedCell String String
    , password : ValidatedCell String String
    }


type alias SignupClean =
    { username : String
    , email : String
    , password : String
    }



-- Validators


atLeast : Int -> String -> String -> Result (List String) String
atLeast n msg s =
    if String.length s >= n then
        Ok s

    else
        Err [ msg ]


usernameValidator : Rad.Validator String String
usernameValidator =
    compose
        [ sync (atLeast 3 "Username must be at least 3 characters")
        , async checkUsernameAvailability
        ]


checkUsernameAvailability : String -> Rad.Request (List String) String
checkUsernameAvailability q =
    Http.httpGet prodHandler ("/api/username-check?q=" ++ q) availableDecoder
        |> Rad.mapRequestError (\_ -> [ "username check failed; try again" ])
        |> andThenRequest
            (\available ->
                if available then
                    Ok q

                else
                    Err [ "username unavailable" ]
            )


availableDecoder : Decoder Bool
availableDecoder =
    Decode.field "available" Decode.bool


emailValidator : Rad.Validator String String
emailValidator =
    sync
        (\s ->
            if String.contains "@" s && String.contains "." s then
                Ok s

            else
                Err [ "Must look like an email address" ]
        )


passwordValidator : Rad.Validator String String
passwordValidator =
    sync (atLeast 6 "Password must be at least 6 characters")



-- Codecs


unitCodec : Rad.Codec ()
unitCodec =
    { encode = \_ -> Encode.null
    , decode = Decode.null ()
    }


resultCodec : Rad.Codec (Remote RequestError ())
resultCodec =
    remoteCodec requestErrorCodec unitCodec



-- Form


fields : Model -> Fields
fields m =
    { username = m.username, email = m.email, password = m.password }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.formState
        (fields m)
        [ Form.validatedField m.username
        , Form.validatedField m.email
        , Form.validatedField m.password
        ]


signupGroup : Form.ValidatedGroup Fields SignupClean
signupGroup =
    Form.validators3 .username .email .password
        |> Form.mapValidated (\( u, e, p ) -> SignupClean u e p)



-- Submit request


submitRequest : SignupClean -> Rad.Request RequestError ()
submitRequest clean =
    Http.httpPost prodHandler
        "/api/signup"
        (Encode.object
            [ ( "username", Encode.string clean.username )
            , ( "email", Encode.string clean.email )
            , ( "password", Encode.string clean.password )
            ]
        )
        (Decode.succeed ())



-- App


app : AppDef (SimpleView Model) Model {}
app =
    { init =
        build Model
            |> withValidated "username" "" stringCodec stringCodec usernameValidator
            |> withValidated "email" "" stringCodec stringCodec emailValidator
            |> withValidated "password" "" stringCodec stringCodec passwordValidator
            |> with "submit-result" Idle resultCodec
            |> Form.withState "signup-form"
    , computed = \_ -> {}
    , view =
        \model _ ->
            col
                [ input { label = "Username", cell = Rad.input model.username }
                , watch (Rad.validation model.username) renderValidationHint
                , input { label = "Email", cell = Rad.input model.email }
                , watch (Rad.validation model.email) renderValidationHint
                , input { label = "Password", cell = Rad.input model.password }
                , watch (Rad.validation model.password) renderValidationHint
                , watch (Form.status (theForm model)) renderStatusHint
                , button { label = "Submit", onClick = Form.submit (theForm model) }
                , button { label = "Reset", onClick = Form.reset (theForm model) }
                , watch (toSource model.submitResult) renderResult
                ]
    , reactions =
        \model _ ->
            Form.reactions (theForm model)
                ++ [ Form.onSubmit (theForm model)
                        signupGroup
                        submitRequest
                        model.submitResult
                   ]
    , persist = Nothing
    }



-- View helpers


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


renderStatusHint : Status -> SimpleView Model
renderStatusHint status =
    case status of
        Pristine ->
            text ""

        Editable ->
            text "Ready to submit"

        HasErrors ->
            text "(fix errors before submitting)"

        Validating ->
            text "Checking..."

        Submitting ->
            text "Submitting..."


renderResult : Remote RequestError () -> SimpleView Model
renderResult r =
    case r of
        Idle ->
            text ""

        Loading ->
            text "Submitting..."

        Failed (Http.BadStatus 400) ->
            text "Sign-up failed: that username is reserved (try a different one)"

        Failed _ ->
            text "Sign-up failed (network/other error)"

        Done _ ->
            text "Welcome!"


main : Program Decode.Value (AppModel Model) (Msg Model)
main =
    run simpleViewEngine app
```

**Notes for the implementer:**
- `Rad.Request err r` is the public type alias used in the two type annotations (`checkUsernameAvailability`, `submitRequest`). The internal module `Rad.Internal.Request` is not importable from outside the package; always use `Rad.Request`.
- `Rad.validation` returns `Source (Validation err a)`; `Rad.Validation` is the type with constructors `Dormant | Checking | Valid a | Invalid (List err)`.
- `Rad.mapRequestError` is used qualified to avoid potential local collisions.

- [ ] **Step 3: Create `examples/L05E03-signup.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>L05E03 signup</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/L05E03_Signup.elm";
      Elm.L05E03_Signup.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 4: Add to `examples/vite.config.js`.** Locate the existing inputs object. After the last existing entry (likely `L07E01-persist-counter`), add:

```javascript
"L05E03-signup": resolve(__dirname, "L05E03-signup.html"),
```

- [ ] **Step 5: Add to `examples/index.html`.** Find the Layer 5 `<ul>` (currently has profile-form and wizard-step links). Append:

```html
<li><a href="L05E03-signup.html">signup</a></li>
```

- [ ] **Step 6: Format Elm.**

```
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 7: Build verification.**

```
cd examples && npm run build
```
Expected: success — 23 entries (was 22).

- [ ] **Step 8: Commit.**

```
git add examples/src/L05E03_Signup.elm examples/L05E03-signup.html examples/vite.config.js examples/index.html
git commit -m "Ship L05E03 signup example"
```

---

## Task 3: Ship L05E04 checkout example

**Files:**
- Create: `examples/src/L05E04_Checkout.elm`
- Create: `examples/L05E04-checkout.html`
- Modify: `examples/vite.config.js`
- Modify: `examples/index.html`

- [ ] **Step 1: Write `examples/src/L05E04_Checkout.elm`:**

```elm
module L05E04_Checkout exposing (main)

import Json.Decode as Decode exposing (Decoder)
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
import Rad.Engine exposing (Msg)
import Rad.Form as Form exposing (Status(..))
import SimpleView exposing (SimpleView, button, col, input, simpleViewEngine, text, watch)



-- Address (typed clean output for one address)


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
```

**Notes for the implementer:**
- The component's `reactions = \_ _ -> []` is intentional. Parent's `Form.reactions (theForm m)` already covers per-field validation. Returning the component's own `validationReactions` here would duplicate.
- `withInstance "billing" addressComponent` followed by `withInstance "shipping" addressComponent` uses the SAME ComponentDef bound at module level (per Layer 6 recommended pattern).
- `Rad.Validation` constructors must be imported. Available as `Rad.Validation(..)` if you want unqualified; otherwise use `Rad.Dormant` / `Rad.Checking` / `Rad.Valid` / `Rad.Invalid` as shown.

- [ ] **Step 2: Create `examples/L05E04-checkout.html`:**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>L05E04 checkout</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module">
      import { Elm } from "./src/L05E04_Checkout.elm";
      Elm.L05E04_Checkout.init({ node: document.getElementById("app") });
    </script>
  </body>
</html>
```

- [ ] **Step 3: Add to `examples/vite.config.js`** (after the L05E03 entry from Task 2):

```javascript
"L05E04-checkout": resolve(__dirname, "L05E04-checkout.html"),
```

- [ ] **Step 4: Add to `examples/index.html`** Layer 5 list (after the L05E03 link):

```html
<li><a href="L05E04-checkout.html">checkout</a></li>
```

- [ ] **Step 5: Format Elm.**

```
(cd examples && npx --yes elm-format src --yes)
```

- [ ] **Step 6: Build verification.**

```
cd examples && npm run build
```
Expected: success — 24 entries (was 23).

- [ ] **Step 7: Commit.**

```
git add examples/src/L05E04_Checkout.elm examples/L05E04-checkout.html examples/vite.config.js examples/index.html
git commit -m "Ship L05E04 checkout example"
```

---

## Task 4: Final verification

No commit unless something needs fixing.

- [ ] **Step 1: Full build.**

```
cd examples && npm run build
```
Expected: 24 entries (index + 23 examples). The build summary should list `L05E03-signup` and `L05E04-checkout` among the emitted HTML files.

- [ ] **Step 2: Package tests.**

```
npx --yes elm-test
```
Expected: **137 passed** (unchanged; no new test files in this slice).

- [ ] **Step 3: Live browser smoke (if dev server running).**

```
cd examples && npm run dev
```

Open each new example in a browser:

**L05E03 signup:**
- Type `taken` as username → after ~1.5s, shows "username unavailable" hint.
- Type `alice` + valid email + valid password → status goes Editable → Submit → "Submitting..." → "Welcome!".
- Type `fail` + valid email + valid password → Submit → "Submitting..." → "Sign-up failed: that username is reserved...".
- After failure, edit any field → Submit again → success.

**L05E04 checkout:**
- Type valid values in all 6 fields → Save → status hint goes to "(Saved ✓)" → saved-display shows both addresses.
- Edit one field → status hint goes back to Editable → Save → saved-display updates.
- Click Reset → all 6 fields cleared, validations back to Dormant, saved-display unchanged.
- Type one invalid field (empty street) + others valid → status: "(fix errors before saving)" → Save does nothing visible (gate blocks).

- [ ] **Step 4: Commit history sanity.**

```
git log --oneline 92268f2..HEAD
```
Expected: 3 commits — "Add /api/signup mock endpoint", "Ship L05E03 signup example", "Ship L05E04 checkout example".

- [ ] **Step 5: Clean tree.**

```
git status
```
Expected: clean.

---

## Out-of-slice notes

- **If the existing `mock-api-plugin.js` `/api/username-check` endpoint returns a different shape than `{available: bool}`,** verify by reading the file and adjust the `availableDecoder` in L05E03_Signup.elm. As of this plan it returns `{available: q !== "taken"}` with a 1500ms delay.
- **If `Rad.Validation(..)` constructors are not exposed by `Rad`'s exposing list,** import them via `import Rad exposing (Validation(..))`. The current exposing list does include `Validation(..)`.
- **The examples are a separate Elm package** (`examples/elm.json`); they can only import public modules from `bcardiff/elm-rad` (e.g., `Rad`, `Rad.Form`, `Rad.Http`). `Rad.Internal.*` modules are NOT importable from outside the package — the plan uses `Rad.Request` for the public type alias accordingly.
- **If `SimpleView`'s `input` collides with `Rad.input`,** qualify one. `Rad.input` extracts the `Cell a` from a `ValidatedCell err a`. `SimpleView.input` is a view constructor. Both are used in the example via clean imports; if a compilation error appears about ambiguity, qualify `Rad.input` explicitly.
- **If `embed` is also exported by something other than `Rad` in your namespace,** qualify as `Rad.embed`.
