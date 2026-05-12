# Secret Cells — Design Exploration (not implemented)

**Status:** Exploration only. Not approved for implementation; not on a roadmap. Captured so the thinking isn't lost.

**Context:** `elm-rad` Layer 7 introduced opt-in `localStorage` persistence. Cells with sensitive values (passwords, tokens, etc.) are at risk of being saved to disk by default. The signup example L05E03 surfaced the concern: a `password` `ValidatedCell` would, if persistence were enabled, store the plaintext password in `localStorage`.

The current mitigation is: do not enable persistence for apps that hold sensitive data, OR write a custom codec that elides the secret. Both options put the burden on the user. A first-class `secret` primitive would let the user mark a cell as never-persisted at allocation time.

This document records the exploration so a future iteration can pick it up without re-deriving the problem space.

---

## Problem statement

A persisted `Cell a` writes its current value through its `Codec a` to localStorage every save (after debounce or on `persistNow`). The codec drives **both** the in-memory Registry and the persisted blob. We cannot suppress persistence by replacing the codec — that would also break runtime behavior.

To suppress persistence while keeping runtime intact, the mechanism must live in `Rad.Internal.Persist.PersistEntry`, not in `Codec`.

---

## What was discussed

### 1. API shape

Three candidate shapes:

- **Wrapper newtype `type Secret a = Secret a`** — type-system marker; ripples through every read/write site (`Rad.set cell (Secret "value")`); doesn't actually solve persistence on its own because the codec is still required at runtime.
- **Builder primitive `withSecret`** — non-composable; combinatorial explosion (`withSecret`, `withSecretValidated`, `withSecretDebounced`...).
- **Builder modifier `secret`** *(chosen direction)* — composes with `with` / `withDebounced` / `withValidated`. Mutates the most-recently-added `PersistEntry` to encode as a placeholder and decode by writing initial values back.

The modifier approach is the smallest delta and works uniformly across cell types.

### 2. Architectural prerequisite

`PersistEntry` would gain a `resetToInitial : Registry -> Registry` field, populated by each existing builder primitive:

- `cellEntry`: writes the encoded initial back to the cell's slot.
- `debouncedEntry`: writes initial to `rawId` and `settledId`, `0` to `timerSeqId`.
- `validatedEntry`: writes initial to `inputId`, `Dormant` to `validationId`, `0` to `activationSeqId`.

The `secret` modifier replaces `encode` (returns a placeholder blob) and `decode` (ignores blob, calls `resetToInitial`) on the most-recent persist entry. Runtime behavior is unchanged.

### 3. Form integration (unresolved)

A secret cell used as a `Form.field` / `Form.validatedField` member would still leak its value into `Form.State.snapshot` (which IS persisted via the form-state cell's regular persistence path). `Form.advanceSnapshot` writes every member's current value into the snapshot blob.

Three candidate fixes were considered:

- **`Form.secretField` / `Form.secretValidatedField`** — new member constructors that mark a member as secret. `Form.advanceSnapshot` skips them. Other Form behaviors (validation, submit gating, reset) work normally. Most user-friendly; most API surface.
- **Document the carve-out** — secret cells must not be Form members. The user combines `Form.canSubmit` with the cell's own validation source manually. Real call-site friction.
- **Auto-detect via PersistEntry inspection** — at snapshot time, walk the persist list to find each member's entry and check `typeTag` for `secret-*`. Couples Form to Persist internals.

The session paused before picking one.

### 4. Type-level marker (skipped)

A wrapper newtype `type Secret a = Secret a` would communicate sensitivity at the type level (e.g., `Cell (Secret String)` for a password). The session deferred this — it doesn't address the persistence leak by itself, and it ripples through every read/write site. Could be layered on top of the modifier approach later if useful.

### 5. Adjacent question: Debounced + Validated composition

A side question surfaced: today `withDebounced` and `withValidated` are mutually exclusive (a cell is one or the other). Making the builder API genuinely modifier-based (e.g., a `CellRecipe a` abstraction with `debounce`, `validate`, `secret` modifiers) would address both Secret AND the Debounced+Validated gap. This is a much larger redesign and was explicitly deferred.

---

## Why standing down

Three reasons:

1. **No published app uses persistence yet.** Layer 7 shipped recently; the leak is theoretical until a real consumer hits it.
2. **Workaround exists.** Apps that hold sensitive data should leave `persist = Nothing`. The README already declares persistence opt-in. Adding a `secret` primitive without a real consumer risks YAGNI.
3. **Form integration is unresolved.** Any implementation that's useful for the signup case needs Form integration, and the three candidate fixes have different ergonomic / coupling trade-offs. Solving this without a concrete use case in hand risks the wrong choice.

The persistence section in `docs/design-elm-rad.md` and the LLM target spec now carry an explicit warning that persistence + sensitive data is a foot-gun.

---

## Future-direction notes

When this is picked up:

- The `resetToInitial` field on `PersistEntry` is a tiny prerequisite refactor (each existing builder primitive adds one closure). Safe to land independently of the secret modifier.
- The modifier `secret : CellBuilder rest -> CellBuilder rest` operates on the most-recent persist entry. Empty-list case (called before any cell) is a no-op or a panic — pick at implementation time.
- For Form integration, the `Form.secretField` / `Form.secretValidatedField` option scales best as the public API grows; the auto-detect option scales worse.
- A type-level wrapper `Secret a` is a separable concern that can ship later as a defense-in-depth layer.
- If the broader composable-builder redesign happens (`CellRecipe`), this exploration becomes a special case of it: `secret` is a `Recipe a -> Recipe a` modifier.

---

## References

- Punchlist memory entry: `project_layer_punchlists.md` Layer 7 §2.
- Design doc Persistence section: `docs/design-elm-rad.md`.
- LLM target spec: `docs/llm/elm-rad-app-spec.md` (Anti-patterns section).
- Signup example using a plaintext password cell: `examples/src/L05E03_Signup.elm` (`persist = Nothing`).
