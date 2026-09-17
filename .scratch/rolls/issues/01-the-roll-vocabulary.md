# 01 — The Roll vocabulary

Status: ready-for-agent

The domain types, with no persistence and no UI. Everything else depends on this.

## What to add

A new file, `MapForge/Roll.swift`.

**`enum Ability: String, Codable, CaseIterable`** — six cases. `title` ("Dexterity") and
`abbreviation` ("DEX"), as `Condition` has `title`/`symbolName`.

**`enum Skill: String, Codable, CaseIterable`** — eighteen cases. `title` ("Stealth") and
`ability: Ability` — the permanent tie, derived and never stored. Acrobatics DEX, Animal
Handling WIS, Arcana INT, Athletics STR, Deception CHA, History INT, Insight WIS,
Intimidation CHA, Investigation INT, Medicine WIS, Nature INT, Perception WIS, Performance
CHA, Persuasion CHA, Religion INT, Sleight of Hand DEX, Stealth DEX, Survival WIS.

**`struct Roll: Codable, Equatable`** — the shared shape both kinds carry:
- `d20: Int` — 1...20
- `modifier: Int`
- `difficultyClass: Int?` — optional, and the reason is in the ADR
- `var total: Int { d20 + modifier }`
- `var succeeded: Bool?` — `nil` when there is no DC, else `total >= dc`. Computed, never
  stored, never encoded.

Raw values are wire names and outlive any rename — see the `combatantRemoved`/"benched"
precedent at `CombatLogFold.swift:180-183`.

## Tests

`MapForgeTests/RollTests.swift`:
- every `Skill` maps to the Ability the rules give it (all eighteen, explicitly)
- `succeeded` is `nil` with no DC, `true` at exactly the DC, `false` one under
- `total` with a negative modifier
- raw values round-trip — the guard against a rename silently orphaning old Logs

## Done when

The types exist, the tests pass, and nothing else in the app references them yet.
