# Layer 5 Examples — Design (L05E03, L05E04)

**Status:** Approved design. Next step: writing-plans skill to produce the implementation plan.

**Goal:** Add two new examples that exercise unused Layer 5 (Forms) features. Existing examples (`L05E01-profile-form`, `L05E02-wizard-step`) demo `validators2 + Form.onSubmit (noRequest)` and `validators1 + Form.onValid` respectively. The gaps these new examples fill:

- Real `Form.onSubmit` returning `Remote err r` with explicit success and failure paths.
- `mapValidated` packing a `validators3` tuple into a typed record.
- Async validator integrated into a form's submit gate.
- Cross-component form: a `ComponentDef` providing reusable validated fields with the parent owning the `Form.State`.
- `validators6` (packer-function form) exercised end-to-end.

---

## 1. Scope

**In scope:**
- `examples/src/L05E03_Signup.elm` — signup form with async username-availability validator, sync email + password validators, `validators3 + mapValidated → SignupClean` record, `Form.onSubmit` posting to `/api/signup`, deterministic failure path.
- `examples/src/L05E04_Checkout.elm` — parent-level checkout form over two `addressComponent` instances (billing + shipping), `validators6` with packer function, `Form.onValid` committing to a `Cell (Maybe Checkout)`.
- Two HTML harnesses (no JS glue: `persist = Nothing` for both).
- Two `examples/mock-api-plugin.js` endpoints: `GET /api/username-check` and `POST /api/signup`.
- `examples/vite.config.js` and `examples/index.html` updates.

**Out of scope:**
- Persistence integration (deferred; password persistence has a security concern noted in the punchlist).
- Cross-field validators (e.g., "passwords match" — Layer 4 doesn't support cross-field directly; would need a future feature).
- Server-side error mapping to per-field error display (we only show a top-level submit error).
- SimpleView `row` primitive for side-by-side layout — both addresses render stacked.
- New test files. Existing test suites cover the underlying Form machinery.

**Out-of-scope but tracked (memory `project_layer_punchlists.md`):**
- `Secret a` wrapper for non-persisted sensitive values (password use case surfaced this idea).

**Naming:** per memory `feedback_example_naming.md`:
- HTML: `L05E03-signup.html`, `L05E04-checkout.html`
- Elm: `L05E03_Signup.elm`, `L05E04_Checkout.elm`

---

## 2. L05E03 — Signup

### Model

```elm
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
```

`Fields` is the form-projection of the model (excludes `submitResult` and `formState`). `SignupClean` is the typed clean output of the validators group.

### Validators

```elm
usernameValidator : Rad.Validator String String
usernameValidator =
    compose
        [ sync (atLeast 3 "Username must be at least 3 characters")
        , async checkUsernameAvailability
        ]


checkUsernameAvailability : String -> Request (List String) String
checkUsernameAvailability q =
    Http.httpGet prodHandler ("/api/username-check?q=" ++ q) availableDecoder
        |> mapRequestError (\_ -> [ "username check failed; try again" ])
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


atLeast : Int -> String -> String -> Result (List String) String
atLeast n msg s =
    if String.length s >= n then
        Ok s

    else
        Err [ msg ]
```

### Form construction + validators group

```elm
init =
    build Model
        |> withValidated "username" "" stringCodec stringCodec usernameValidator
        |> withValidated "email"    "" stringCodec stringCodec emailValidator
        |> withValidated "password" "" stringCodec stringCodec passwordValidator
        |> with "submit-result" Idle resultCodec
        |> Form.withState "signup-form"


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
```

`signupGroup` is bound at module level (no per-render reconstruction).

### Submit reaction

```elm
reactions =
    \model _ ->
        Form.reactions (theForm model)
            ++ [ Form.onSubmit (theForm model)
                    signupGroup
                    submitRequest
                    model.submitResult
               ]


submitRequest : SignupClean -> Request RequestError ()
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
```

The `Decode.succeed ()` discards the response body; only the HTTP status is meaningful (`Done ()` on 2xx, `Failed (BadStatus n)` on non-2xx).

### View

Single-column layout per Section 4 of the brainstorm. Per-field validation hints render `Rad.validation field` via `watch`. Submit button reads `Form.canSubmit` for `disabled`. Result row renders `model.submitResult` via `watch`.

### Mock endpoints

Two new branches in `examples/mock-api-plugin.js`:

- `GET /api/username-check?q=<x>` → `{"available": <x not in ["admin","taken"]>}` with ~200ms delay.
- `POST /api/signup` → 400 `{"error": "..."}` if body's `username == "fail"`, else 200 `{"ok": true}`. ~300ms delay.

### Deterministic flows demoed

| User action | Result |
|---|---|
| Type "admin" as username | Validating → Invalid `["username unavailable"]` |
| Type "ok-user" + valid email + valid password → Submit | Submitting → Done () |
| Type "fail" + valid fields → Submit | Submitting → `Failed (BadStatus 400)` with error message |
| After failure, edit any field → Submit | Validation re-runs, fresh request fires |

---

## 3. L05E04 — Checkout

### Component

```elm
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
                |> withValidated "street" "" stringCodec stringCodec nonEmptyStreet
                |> withValidated "city"   "" stringCodec stringCodec nonEmptyCity
                |> withValidated "zip"    "" stringCodec stringCodec zipFormat
        , computed = \_ -> {}
        , view = \fs _ -> renderAddress fs
        , reactions = \_ _ -> []
        }
```

The component's `reactions` returns `[]`. Per-field validations are owned by the **parent's** `Form.reactions` — running them in both would duplicate. This is the central design lesson the example teaches.

### Parent model

```elm
type alias Model =
    { billing : AddressFields
    , shipping : AddressFields
    , checkoutForm : Cell Form.State
    , saved : Cell (Maybe Checkout)
    }


type alias Address =
    { street : String, city : String, zip : String }


type alias Checkout =
    { billing : Address
    , shipping : Address
    }
```

`Cell (Maybe Checkout)` holds the last successful save. Initial value `Nothing`.

### init

```elm
init =
    build Model
        |> withInstance "billing" addressComponent
        |> withInstance "shipping" addressComponent
        |> Form.withState "checkout-form"
        |> with "saved" Nothing savedCodec
```

`savedCodec : Codec (Maybe Checkout)` is a hand-rolled `maybeCodec` over a record codec for `Checkout`.

### Form + validators6

```elm
type alias Fields =
    { billStreet : ValidatedCell String String
    , billCity : ValidatedCell String String
    , billZip : ValidatedCell String String
    , shipStreet : ValidatedCell String String
    , shipCity : ValidatedCell String String
    , shipZip : ValidatedCell String String
    }


theForm : Model -> Form.Form Fields
theForm m =
    Form.over m.checkoutForm
        { billStreet = m.billing.street
        , billCity = m.billing.city
        , billZip = m.billing.zip
        , shipStreet = m.shipping.street
        , shipCity = m.shipping.city
        , shipZip = m.shipping.zip
        }
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
        .billStreet .billCity .billZip
        .shipStreet .shipCity .shipZip
```

### Submit reaction (client-only)

```elm
reactions =
    \model _ ->
        Form.reactions (theForm model)
            ++ [ Form.onValid (theForm model)
                    checkoutGroup
                    (\checkout -> set model.saved (Just checkout))
               ]
```

No HTTP. The Action commits the typed `Checkout` to `model.saved`. The form's snapshot advances automatically on success (per `Form.onValid` semantics), so `Form.dirty` drops to `False` after a save.

### View

Two stacked `embed addressComponent m.billing` / `m.shipping` blocks (labeled "Billing" / "Shipping"), then status hint, Save + Reset buttons, and a saved-display block reading `model.saved`.

### Demoed flows

| User action | Result |
|---|---|
| Type valid values in both addresses → Save | `model.saved` becomes `Just checkout`; status hint goes `Editable → Pristine` |
| Edit a field after save → Save again | New `Checkout` written; saved-display updates |
| Click Reset | All 6 fields back to previous saved snapshot (or initials if never saved); validations back to Dormant |
| Type one invalid field → Save | Status: `HasErrors`; gate blocks submit |

---

## 4. mock-api-plugin.js additions

Add two endpoints to the existing plugin. Style matches the file's existing router; specific code will be confirmed at implementation time by reading the current state of `examples/mock-api-plugin.js`.

```javascript
// GET /api/username-check?q=<x>
{
  url: /^\/api\/username-check/,
  method: "GET",
  handler: (req, res) => {
    const q = new URL(req.url, "http://x").searchParams.get("q") || "";
    const unavailable = new Set(["admin", "taken"]);
    setTimeout(() => {
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ available: !unavailable.has(q) }));
    }, 200);
  },
}

// POST /api/signup
{
  url: "/api/signup",
  method: "POST",
  handler: (req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      setTimeout(() => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.username === "fail") {
            res.statusCode = 400;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({ error: "username 'fail' is reserved" }));
          } else {
            res.statusCode = 200;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({ ok: true }));
          }
        } catch {
          res.statusCode = 400;
          res.end("bad json");
        }
      }, 300);
    });
  },
}
```

If the existing plugin uses Vite's middleware-array style (`server.middlewares.use(...)`), the implementation will adapt the snippet to match — same logic, different framing.

---

## 5. Integration wiring

`examples/vite.config.js` — add two `input` entries after `L07E01-persist-counter`:

```javascript
"L05E03-signup": resolve(__dirname, "L05E03-signup.html"),
"L05E04-checkout": resolve(__dirname, "L05E04-checkout.html"),
```

`examples/index.html` — append to the existing Layer 5 `<ul>`:

```html
<li><a href="L05E03-signup.html">signup</a></li>
<li><a href="L05E04-checkout.html">checkout</a></li>
```

`examples/L05E03-signup.html` and `L05E04-checkout.html` — minimal harnesses (no JS glue; `persist = Nothing`):

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

(L05E04 mirrors with WizardStep-style mounting.)

---

## 6. Verification

- `cd examples && npm run build` — should produce 23 example entries + index = **24 vite entries total** (was 22).
- Manual browser smoke per the demoed-flows tables (§§2–3).
- No new package tests; the framework machinery is already covered by `tests/`.

---

## 7. Non-goals

- No persistence on either example.
- No cross-field validators.
- No server-side per-field error mapping.
- No SimpleView extensions.
- No new test suites.
