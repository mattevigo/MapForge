# Bestiary

Status: implemented on `feature/bestiary`

Say which **Monster** a **Creature** is, from the DM's own notes, and have the numbers a fight
needs filled in. Vocabulary: `CONTEXT.md` (**Monster**, **Bestiary**, **Add**). Decisions:
ADR-0019 (Yams), ADR-0020 (read from notes, copied, never persisted), ADR-0021 (the sheet's OK
stamps a Stat Block). This file is the agreed design from the grilling session, as decided.

## Source

- `.mapforge/config.json` — the Workspace's generic, hand-edited configuration: one JSON object,
  one optional property per setting. The first is `{ "bestiaryStatBlockPath": "03_Bestiario" }`.
  The app reads it and **never writes it**. Not `preferences.json` (which the app writes, and
  overwrites when unreadable), not the Manifest. No `version`; unknown keys are ignored.
- `bestiaryStatBlockPath` is relative to the Workspace root and must be inside it. Absolute,
  `~`, or escaping with `..` → no Bestiary, with a reason. Missing file, unreadable file, file
  without the property, missing folder → no Bestiary, each with its own reason.
- Scanned recursively for markdown notes holding a ```` ```statblock ```` fence (YAML, parsed
  with Yams).
- Read in `AppState.open(_ workspace:)`, off the main thread; cleared in `closeWorkspace()`.
  In memory only. **No rescan control, no file watching, no disk cache.**

## Reading

- Lenient: leading integer of `hp` and `ac` (`67 (9d8 + 27)` → 67); `initiative` accepts `-` and
  `−` (U+2212) (`"−1 (9)"` → −1); unknown `size` → not Big; Grande/Enorme/Mastodontica and
  Large/Huge/Gargantuan → Big. HP is the book average; `hit_dice` is display only.
- No fence → silently not a Monster. Bad YAML, no `name`, or a `name` already read (first by
  path wins) → **skipped and listed** with file and reason.
- A Monster missing `ac`/`hp` is still offered and stamps what it has.

## The Edit Pawn sheet

- A search box to the right of the Kind picker, **for Kind = Creature only**.
- Substring of `name`, case- and diacritic-insensitive. Rows: name · CR · type. Arrow keys and
  Return pick; Return inside the open results must **not** trigger OK. Once picked: the name
  with a × to clear.
- A quiet caption under it, only when there is something to say: "37 Monsters · 1 file skipped"
  (opens file + reason), or why there is no Bestiary. Disabled box when there is none.
- No settings UI, no folder picker.

## The stamp

- On OK, and **only if the Monster changed** since the sheet opened. Cancel writes nothing.
- Sets AC, initiative bonus, max HP, and **current HP = max**. Leaves temporary HP, Conditions,
  exhaustion, concentration and `isInCombat` alone. Also sets Big from `size`.
- A label that is still a bare integer becomes initials + number: first letter of each
  whitespace-separated word, uppercased (Gnoll Guerriero → GG, Naga d'Ossa → ND); a single word
  takes its first two letters (Wraith → Wr). Numbered per prefix across the Map (GG1…GG4 even
  for gnolls and goblins mixed). A label the DM typed is never touched.
- **Confirmation only when an existing current HP would be overwritten** (from an earlier
  Monster or typed by hand), naming the change ("12/27 → 45/45"); declining returns to the
  open sheet. A first stamp asks nothing.
- During an Encounter the stamp goes through `editStatBlock`, so it is logged as Changes —
  including the bonus, as the new `initiativeBonusChanged`. Initiative is not re-rolled. A
  Pawn on the Map but not in the running fight is stamped straight to `stats.json`.
- × , or changing Kind away from Creature, drops the memory and leaves the Stat Block as it is.
- `Pawn` gains optional, advisory `monsterName` (`decodeIfPresent`, omitted when nil) in
  `<map>.fog.json`. A copy, not a link: combat never reads the Bestiary.

## Add

A Creature placed by **Add** inherits the last Creature's Monster (when the Bestiary still has
it), is labelled in the GG-n form, and is stamped afresh at full HP **before** `joinEncounter`,
so Initiative rolls with the right bonus. Never asks.

## Reference view (second slice)

Combat tab, beneath `StatEditor`, for the selected/active Combatant that remembers a Monster.
Looked up **live** by name — the one live read. Shows speed, senses, saves, skills,
resistances/immunities, CR; then Traits, Actions, Bonus Actions, Reactions, Legendary Actions.
`desc` as inline markdown, `[[wikilinks]]` flattened to text. Says so plainly if the Monster is
gone. DM-only; never on the Player Display.

## Out of scope

Roll Modifiers from ability scores or saves (ADR-0017); Monsters for Players; a folder picker or
settings UI; matching on frontmatter `nome_inglese`; rolled HP; Rescan.
