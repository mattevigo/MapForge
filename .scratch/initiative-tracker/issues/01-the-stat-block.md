# 01 — The Stat Block and its store

Status: done

The pure, testable core: what a Combatant's numbers *are*, and where they live on disk. No
views, no Encounter, no Log.

See `docs/adr/0009-combat-state-lives-outside-the-fog-document.md` for why none of this goes
on `Pawn`.

## Build

**`Condition`.** A `String`-backed `Codable, CaseIterable` enum of the fourteen DnD 5.5e
conditions: `blinded`, `charmed`, `deafened`, `frightened`, `grappled`, `incapacitated`,
`invisible`, `paralyzed`, `petrified`, `poisoned`, `prone`, `restrained`, `stunned`,
`unconscious`. **Exhaustion is not a case** — it is a level and lives on the Stat Block as an
`Int`. Give each a `title` the way `PawnKind` does (`FogDocument.swift`), and an SF Symbol
name for the row icons in issue 05.

**`StatBlock`.** `initiativeBonus: Int`, `armorClass: Int`, `currentHP: Int?`, `maxHP: Int?`,
`temporaryHP: Int`, `conditions: Set<Condition>`, `exhaustion: Int`, `isConcentrating: Bool`.
`Codable, Equatable`.

Hit points are **optional** because a Creature stamped and not yet filled in has none, and
zero is a meaningful value that must not stand in for absent. `temporaryHP` is not optional —
absent temporary hit points are zero. Defaults: AC 10, bonus 0, no hit points, no conditions,
exhaustion 0, not concentrating.

`isComplete` is true when `maxHP` and `currentHP` are both present; issue 05 flags the rest.

Temporary hit points belong to **every** Stat Block, Player and Creature alike. The original
request tracks them only for player characters, and that is a habit rather than a rule — a
monster can have them, and one shape beats two for one optional Int.

**Exhaustion** clamps to 0...6.

**`StatsDocument`.** `version: Int` plus `blocks: [UUID: StatBlock]` keyed by `Pawn.ID`.
Stamp `Self.current` on encode rather than echoing what was read, as
`FogDocument.encode(to:)` does. A dictionary keyed by `UUID` needs `JSONEncoder` help — Swift
encodes `[UUID: T]` as an unkeyed array of alternating keys and values, which is not readable.
Encode it as an array of `{pawnID, block}` and rebuild the dictionary on decode.

**`StatsStore`.** Load and save at `<map>.combat/stats.json`. Model it on `FogStore.swift`
exactly: `JSONEncoder` with `[.prettyPrinted, .sortedKeys]`, written `.atomic`, a missing file
is normal and returns an empty document, an unreadable file surfaces a failure and is **never
overwritten**. Like `PartyStore` it must create its directory. A `combatDirectory(forMapAt:)`
helper belongs here — issues 02 and 07 both need it.

**`PartyCharacter` gains three fields**: `initiativeBonus: Int`, `armorClass: Int`,
`maxHP: Int?`, all `decodeIfPresent` with the defaults above, so existing `parties.json` files
decode unchanged. `Stamp.pawn(from:...)` copies them into a fresh `StatBlock` for the new
Pawn, with `currentHP` seeded to `maxHP`. This is ADR-0007's copy rule applying to more
fields, not a new decision.

## Tests

Unit tests, no UI:

- A `StatsDocument` round-trips through the store: write, read, equal.
- A missing file loads as empty, not an error.
- An unreadable file reports failure and is not overwritten.
- Saving creates `<map>.combat/` when absent.
- `stats.json` is readable: the dictionary encodes as named keys, not an alternating array.
- Exhaustion clamps at both ends.
- A `PartyCharacter` written before this issue decodes with the three defaults.
- Stamping a Character with `maxHP: 32` gives a Pawn a Stat Block at 32/32.
- `isComplete` is false for a Stat Block with no hit points and true once both are set.

## Done when

Stat Blocks persist beside a Map and survive a round trip, `parties.json` migrates silently,
and stamping a Character carries its numbers. Nothing yet shows any of it.

## Comments

**Built.** Three deviations worth recording.

`StatBlock` needed a **hand-written `init(from:)`**, which the issue did not anticipate. The
`didSet` that clamps exhaustion does not fire during decoding — the synthesized decoder
assigns stored properties directly — so a hand-edited `stats.json` with `"exhaustion": 99`
decoded to 99. Caught by mutation testing, not by writing the test first. Decoding now goes
through the initialiser, which clamps in one place.

`PartyCharacter` needed a hand-written decoder too, for the same class of reason: the
synthesized one *throws* on a missing non-optional key, so adding `initiativeBonus` and
`armorClass` as plain `Int`s would have made every existing `parties.json` unreadable rather
than merely incomplete. `decodeIfPresent` throughout.

`Condition.symbolName` shipped `"stars"` for Stunned, which does not resolve on macOS 15.
`ConditionTests.testEveryConditionSymbolResolves` caught it — the same bug class
`LiveRowSymbolTests` was written for. Now `"sparkles"`.

`StatsDocument` encodes `blocks` as a sorted array of `{pawnID, block}` entries rather than a
dictionary, because `[UUID: StatBlock]` encodes by default as an unkeyed array of alternating
keys and values. Sorted so a DM who version-controls their maps gets meaningful diffs.

- 2026-09-14: verified at the table on real hardware. Closed.
