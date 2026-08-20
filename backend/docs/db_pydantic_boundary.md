# DB ↔ Pydantic Boundary — Decision D4

**Status:** Decided 2026-07-04 (Phase 1.3 of the schema SSOT plan).
**Decision:** **Converter-at-router.** `database/` returns domain dicts; a
`utils/<domain>_response.py` normalizer transforms Firestore-native types into
model-conformant dicts; FastAPI's `response_model` validates + serializes the
final shape against Pydantic. `database/` does **not** import from `models/`.

## Why not construct-in-DB (option A)?

`database/` is the lowest layer in the import hierarchy
(`database/` → `utils/` → `routers/` → `main.py`). Coupling it to wire models
(`models/`) would mean DB-function signatures change whenever a wire contract
changes — the wrong direction of dependency. It would also make every DB
function (192 dict-annotated returns) return Pydantic, a massive blast-radius
refactor with no incremental safety gain over the router-boundary coercion that
is already in place.

## The pattern (already applied on 419 typed routes)

```
database/<domain>.py        → returns dict (Firestore-native types: Datetime, etc.)
utils/<domain>_response.py  → normalize_<thing>(dict) -> dict  (type coercion + defaults)
routers/<domain>.py         → returns the normalized dict
FastAPI response_model      → validates dict against Pydantic model, serializes to JSON
```

Use a retained domain-specific response model and normalizer; hosted task and
goal response paths were retired when macOS became local-authoritative.

The normalizer handles coercion that Pydantic's runtime validation cannot:
Firestore `Datetime` → `datetime`, stringy booleans, missing-field defaults,
`bool`-is-not-`float` guards. The Pydantic model is the authoritative shape;
the normalizer is the adapter that makes DB output conform to it.

## Rules

1. **Every typed route already has this boundary** — `response_model` is the
   converter. Do not return a raw DB dict from a handler that lacks
   `response_model` (enforced by `scripts/check_response_model_coverage.py`).
2. **Type coercion lives in `utils/<domain>_response.py`**, not inline in the
   router. If a router is hand-coercing DB types (`entry['x'] = ...isoformat()`),
   extract it into the domain normalizer.
   for the before/after.
3. **`database/` stays dict-based.** New DB functions return `dict` or
   `List[dict]`. Do not import `models/` from `database/`.
4. **New domains create a `utils/<domain>_response.py`** with
   `normalize_<thing>()` helpers when Firestore types need coercion. If the DB
   dict already matches the model shape (simple types only), the normalizer is
   optional — FastAPI's coercion is sufficient.
