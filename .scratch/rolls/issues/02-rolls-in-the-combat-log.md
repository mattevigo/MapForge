# 02 — Rolls in the Combat Log

Status: ready-for-agent
Blocked by: 01

Two new `Change` cases, the fold that ignores them, and the wording that reads them back.

## What to add

**`CombatLog.swift`**, `enum Change`:

```swift
case savingThrow(combatantID: UUID, ability: Ability, roll: Roll)
case abilityCheck(combatantID: UUID, skill: Skill, roll: Roll)
```

Then, in order, every exhaustive switch:
- `Change.combatantID` (`CombatLog.swift:57-76`) — both return their id
- `Change.Kind` — add both raw values
- `init(from:)` — decode arms, using `requiredID()`
- `encode(to:)` — encode arms. New `CodingKeys`: `ability`, `skill`, `d20`, `modifier`,
  `difficultyClass`. Encode the `Roll` flat, not nested, so a DM reading the file sees
  `"d20": 16, "modifier": 5, "difficultyClass": 15` on the line. Omit `difficultyClass`
  entirely when nil. **Never encode `succeeded`** — it is derived.

**`CombatLogFold.swift`**, `apply`: add both to the `case .moved, .noteAdded:` arm — they are
records, not mutations, and the existing comment there already says why. Extend it to name
Rolls.

**`LogRowText.swift`**, `describe(_ change:combatantName:)`:
- with a DC: `"Rogue — DEX save 21 (16 + 5) vs DC 15 — succeeded"`
- without: `"Rogue — DEX save 21 (16 + 5)"`
- an Ability Check names the Skill and its Ability: `"Rogue — Stealth (DEX) 19 (12 + 7) vs DC 15 — succeeded"`

Match the existing em-dash style of its neighbours.

## Tests

`CombatLogFormatTests` — round-trip both cases, with and without a DC; assert the JSON is
flat and has no `succeeded` key; assert an unknown `type` still decodes to `.unrecognised`
(the forward-compat guarantee the ADR leans on).

`CombatLogFoldTests` — a Roll changes no folded state: HP, conditions, order and round are
identical before and after, and the fold does not count it as skipped-unrecognised.

`LogRowTextTests` — all four wordings above.

## Done when

A Roll appended to a Turn round-trips, folds to nothing, and reads as a sentence.
