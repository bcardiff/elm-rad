---
name: elm-rad-docgen
description: Generate an LLM-targeted reference doc for building elm-rad applications, with a view-engine slot that can be filled in later. Use when the user asks to produce/update LLM documentation for elm-rad, or to attach a specific view engine to the base spec.
---

# elm-rad-docgen

Generates a single self-contained markdown doc that an LLM can use as a system prompt or context to produce well-formed `elm-rad` applications. The framework portion is fixed; the view-engine portion is parameterized.

## When to invoke

- "Generate the elm-rad LLM doc."
- "Update the elm-rad reference spec."
- "Make me a doc I can paste into another LLM to build elm-rad apps using `<engine>`."

## Inputs

- **No args** → regenerates the base spec at `docs/llm/elm-rad-app-spec.md`. The view-engine section is left as a clearly-marked placeholder for users to fill in manually.
- **`--view-engine <path>`** → reads the supplied view-engine spec file and inlines it into the view-engine section. Output: `docs/llm/elm-rad-app-spec--<engine-slug>.md` (engine-slug derived from the spec's `name` frontmatter or filename).

## Workflow

1. **Read `docs/llm/elm-rad-app-spec.md`** if it exists (this is the base template). If not, treat the structure below as the source of truth and produce a fresh one.

2. **Verify the framework section is current** by spot-checking the exposing lists of:
   - `src/Rad.elm`
   - `src/Rad/Form.elm`
   - `src/Rad/Internal/Engine.elm`
   - `src/Rad/Http.elm`
   - `src/Rad/Read.elm`
   - `src/Rad/View.elm`
   Any new exports not mentioned in the doc → update the doc inline. Any removed exports still mentioned → strip them.

3. **If a view-engine spec was provided:**
   - Read the spec file.
   - It is expected to be a markdown file with a YAML frontmatter `name:` and a body that documents view-engine primitives (types, constructors, examples).
   - Replace the `<!-- VIEW_ENGINE_SLOT -->` marker in the base doc with the spec body (drop its frontmatter).
   - Write to `docs/llm/elm-rad-app-spec--<slug>.md`.

4. **If no view-engine spec was provided:**
   - Ensure the `<!-- VIEW_ENGINE_SLOT -->` marker is present in the base doc, surrounded by a short explanation block ("Add view-engine primitives here").
   - Write/update `docs/llm/elm-rad-app-spec.md`.

5. **Verify the result compiles a hypothetical sample.** Open the doc, locate the "Complete app skeleton" section, mentally check that the example references only names actually exported by the codebase. Fix any drift inline.

6. **Commit** the result with a single-line imperative message:
   - `Regenerate elm-rad LLM spec` (for the base)
   - `Generate elm-rad LLM spec for <engine-slug>` (for an engine variant)

## What goes in the base spec

The base doc structure (sections, in order) is defined in `docs/llm/elm-rad-app-spec.md`. Recompiling the file from scratch is rare — typically you only update a section in place. The expected sections:

1. Overview and mental model
2. Type-level primer (Cell, Source, Reaction, Action, Codec)
3. Building a model — the `CellBuilder` pipeline
4. Reading state — `toSource`, `Read`, `watch`
5. Synchronous actions — `set`, `modify`, `copy`, `batch`, `validate`, `resetValidation`, `noAction`
6. Reactions — `on`, `noRequest`, `Rad.Http`
7. Debounced cells — `withDebounced`, `settled`, debounced inputs
8. Validated cells — `withValidated`, validators, `validationReactions`
9. Components — `defineComponent`, `withInstance`, `embed`, `include`
10. Forms (`Rad.Form`) — state, members, status, submit gating, validators groups
11. Persistence — `PersistConfig`, `persistNow`, JS glue, restore
12. The `AppDef` shape and `run`
13. **View engine slot** (`<!-- VIEW_ENGINE_SLOT -->`)
14. Complete app skeleton
15. Anti-patterns and pitfalls
16. Type-signature reference (alphabetical)

## View-engine spec format

A view-engine spec file (input to the skill via `--view-engine`) should look like:

```markdown
---
name: simple-view
description: SimpleView — the example view engine bundled with the elm-rad examples.
---

## Type

`SimpleView model` — opaque; constructed by combinators below.

## Constructors

| Function | Type | Notes |
|---|---|---|
| `text` | `String -> SimpleView model` | Static text |
| `col` | `List (SimpleView model) -> SimpleView model` | Vertical stack |
| ... | ... | ... |

## Watching reactive sources

`watch : Source a -> (a -> SimpleView model) -> SimpleView model`

## Bound inputs

`input : { label : String, cell : Cell String } -> SimpleView model`

## Engine value

`simpleViewEngine : Rad.Internal.Engine.ViewEngine (SimpleView model) model`

## Complete idiomatic example

(snippet)
```

The skill copies this body (without the frontmatter) into the view-engine slot.

## Notes for the agent

- Do NOT commit changes unless the user explicitly asks; ask first.
- Cell types and Form internals change over time — always re-check the source before claiming a type signature is current.
- The doc is intended as LLM input, so prefer typed examples over prose. Keep paragraphs short.
- One source of truth: when the doc and the codebase disagree, the codebase wins.
