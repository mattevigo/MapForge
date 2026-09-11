# 02 — A Pawn remembers which Character stamped it

Status: ready-for-human

Depends on: 01

One optional field on `Pawn`, and the migration that lets it be added without breaking a
single existing `.fog.json`.

## Build

**`Pawn.characterID: UUID?`** in `FogDocument.swift:155`. Nil for every Pawn placed by hand
and for every Pawn in every file written before this change.

Read `docs/adr/0007-characters-are-stamped-not-linked.md` before touching this. The field is
**advisory**: nothing about drawing, Visibility, Solo Sight, Measurement anchoring or
persistence may branch on it. Its only reader is the roster's placed-count in issue 03. A
Pawn whose `characterID` names a deleted Character is in every way a normal Pawn.

**The `Codable` migration.** `Pawn` hand-writes `init(from:)`/`encode(to:)`
(`FogDocument.swift:252-306`) precisely for this. Add the `CodingKeys` case and decode with
`decodeIfPresent` exactly as `isHidden` and `isBig` already do. This is additive: it does not
need a `FogDocument.version` bump, and an old file must not be rewritten into a new shape
merely by being opened.

**The designated init** (`FogDocument.swift:231`) takes `characterID: UUID? = nil`, so every
existing call site is untouched.

## Tests

- A v1 and a v2 fixture without the key decode with `characterID == nil` and are otherwise
  byte-identical in meaning to today — extend whatever fixture-based decode tests already
  cover the `isCreature` legacy key.
- A Pawn with a `characterID` round-trips.
- A Pawn with `characterID == nil` encodes **without** the key, so untouched files do not
  churn.
- Equality, Visibility and the fog computation are unaffected by the field: two Pawns
  differing only in `characterID` light the Map identically.

## Done when

The field exists, round-trips, and no behaviour reads it.
