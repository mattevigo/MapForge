# What MapForge saves

Everything the app keeps between launches, where it lives, what each file contains, and how
the pieces of one evening — the Session and the Encounters inside it — point at each other.
Written for a DM who opens these files in a text editor and for anyone changing the code
that writes them. Vocabulary is `CONTEXT.md`'s.

## The three homes

Persistent state has exactly three homes, and every file below is in one of them:

| Home | What it holds | Travels with |
|---|---|---|
| **Beside the Map** — `<map>.fog.json`, `<map>.combat/` | What was authored *on* one Map: its Grid, Walls, Lights, Pawns, their Stat Blocks, and every fight fought on it | The Map image, wherever it is moved |
| **The Workspace** — `.mapforge/` at the Workspace root | What the game knows that is not about a Map: Parties, settings, and every Session | The Workspace folder (ADR-0011, ADR-0012) |
| **The machine** — `UserDefaults` | What only this Mac can know: which Workspaces it has opened | Nothing; stays on the Mac |

The rule that decides where a new thing goes is ADR-0012's: *`.mapforge/` holds what the game
knows, `UserDefaults` holds what the machine knows.* A Workspace copied to another Mac carries
its whole game and none of the first Mac's hardware.

### Layout

```
MyGame/                              ← the Workspace (any folder the DM adopted)
├── .mapforge/
│   ├── workspace.json               ← the Manifest: what makes this folder a Workspace
│   ├── parties.json                 ← every Party and its Characters
│   ├── preferences.json             ← active Party, chosen Player Display (app-written)
│   ├── config.json                  ← no longer read (ADR-0023); left alone if present
│   └── sessions/
│       ├── 2026-09-09T183000Z.jsonl ← one Session Log per evening
│       └── 2026-09-16T190000Z.jsonl
└── maps/
    └── crypt/
        ├── dungeon.png              ← the Map
        ├── dungeon.fog.json         ← Grid, Walls, Lights, Pawns
        └── dungeon.combat/
            ├── stats.json           ← Stat Blocks, keyed by Pawn
            ├── 2026-09-09T191200Z.jsonl ← one Combat Log per Encounter
            └── 2026-09-16T201500Z.jsonl

~/Library/Preferences/…MapForge.plist  ← UserDefaults: recentWorkspaces, recentWorkspaceBookmarks
```

Maps may sit anywhere inside the Workspace, in whatever subfolders the DM likes. A Map opened
from *outside* the Workspace still works — its fog and combat files sit beside it as usual —
but its Session Lines name it by bare file name, and the Log View cannot resolve its Combat
Logs (see *Session Log*, `map`).

## Beside the Map

### `<map>.fog.json` — the Map's own authoring

Written by `FogStore`, pretty-printed with sorted keys, atomically. Despite the name it holds
the **Grid** as well as the fog (ADR-0003): a Light's radii are in Grid squares, so the file
that holds the radii must hold the unit.

```json
{
  "version": 2,
  "squaresWide": 30,
  "walls": [
    { "id": "…", "from": { "imagePixels": { "x": 100, "y": 200 } },
                 "to":   { "imagePixels": { "x": 400, "y": 200 } } }
  ],
  "lights": [
    { "id": "…", "name": "brazier", "at": { "imagePixels": { "x": 250, "y": 300 } },
      "brightSquares": 4, "dimSquares": 8, "isOn": true }
  ],
  "pawns": [
    { "id": "…", "label": "Thorin", "colorHex": "#D0342C", "kind": "player",
      "isHidden": false, "isBig": false, "characterID": "…",
      "light": { "id": "…", "at": { "imagePixels": { "x": 120, "y": 340 } },
                 "brightSquares": 6, "dimSquares": 7, "isOn": true } },
    { "id": "…", "label": "GG1", "colorHex": "#5A5A5A", "kind": "creature",
      "isHidden": false, "isBig": false, "monsterName": "Gnoll Guerriero",
      "light": { "…": "…" } }
  ]
}
```

| Field | Meaning |
|---|---|
| `version` | Always stamped as the version the app writes (currently 2), never echoed from what was read. Version 1 files (no `squaresWide`) still open. |
| `squaresWide` | The Map's declared Grid width in squares. **Absent when the DM never ran Grid Fit** — the default 30 is a guess and is never written. |
| `walls[].from/to` | Endpoints in **image pixels**, so a Wall stays welded to the artwork when the Grid changes. Every point in the file is nested under `imagePixels` so the unit is never guessed. The four implicit Walls at the image edge are not stored. |
| `lights[]` | `brightSquares` / `dimSquares` are in **Grid squares**; `isOn` is the switch; `name` is the DM's own and is omitted when unnamed. |
| `pawns[]` | `label` is the DM's bookkeeping (never shown to players); `colorHex` is what the table sees. `kind` is `player`, `creature` or `treasure`. |
| `pawns[].light` | A Pawn *is* a Light: `brightSquares` is its sight. `dimSquares` is on disk but **re-derived on load** as sight + 1 (the fade), so the stored value is cosmetic history. |
| `pawns[].characterID` | Which Character stamped this Pawn. Advisory only — counts on the Party panel — and omitted when absent (ADR-0007). |
| `pawns[].monsterName` | Which Monster this Creature was said to be. Advisory only — the reference view and *Add*'s "same as last" — and omitted when absent (ADR-0020). The numbers were **copied** into `stats.json`. |
| `isCreature` (legacy) | Read forever, never written: a file written before `kind` existed decodes `true` as `creature`. |

Rules:

- **No file for an empty document.** A Map with no Grid, Walls, Lights or Pawns gets no
  `.fog.json`; deleting the last of them deletes the file.
- **Debounced.** Every edit schedules a write 0.5 s later, last document wins; flushed when
  the Map is switched, the Control Window closes, a Pawn is added/removed/committed, or the
  app quits.
- **Unreadable is reported.** A `.fog.json` that exists but will not decode is shown as a
  warning in the Control Window with its path, and the Map opens with no Walls or Lights.
  Unlike `stats.json` and `parties.json`, writes are *not* refused: the warning says so —
  drawing on that Map replaces the file — so recover it by hand first.
- A Pawn found outside the image on load is clamped back to the edge.

### `<map>.combat/stats.json` — Stat Blocks

Written by `StatsStore` under the same rules as the fog file (pretty, sorted, atomic; absent
when empty; unreadable file latched so it is never written over). Kept **outside** the fog
file so a shared Map with its Walls traced does not carry a party's wounds (ADR-0009).

```json
{
  "version": 1,
  "blocks": [
    { "pawnID": "…",
      "block": { "initiativeBonus": 2, "armorClass": 16, "currentHP": 19, "maxHP": 27,
                 "temporaryHP": 0, "conditions": ["poisoned"], "exhaustion": 0,
                 "isConcentrating": false, "isInCombat": true } }
  ]
}
```

- Keyed by **Pawn ID**, as a sorted list of `{pawnID, block}` entries rather than a JSON
  object, so it reads and diffs. A block outlives its Pawn: a Creature deleted mid-fight
  keeps its numbers so the Combat Log still has something to describe.
- `currentHP` / `maxHP` are **optional**: absent means the DM has not typed them, which is
  not the same as 0 (0 is Unconscious). Absent keys are omitted, not `null`.
- `conditions` is the set of the fourteen 5.5e conditions by name (`blinded`, `charmed`,
  `deafened`, `frightened`, `grappled`, `incapacitated`, `invisible`, `paralyzed`,
  `petrified`, `poisoned`, `prone`, `restrained`, `stunned`, `unconscious`).
- `exhaustion` is 0–6 and is clamped on read, because this file can be hand-edited.
- `isInCombat` is the roster: whether this Pawn rolls when the *next* fight starts. Read only
  at that moment. Absent in older files, meaning `true`.
- Every field has a default, so any subset of keys decodes.

**When it is written.** Outside a fight, an edit goes straight here (debounced 0.5 s).
*During* a fight the Combat Log is authoritative: the tracker's numbers are folded from the
Log, and after every recorded Change the folded blocks are copied back here so the fight's
damage outlives the fight. Flushed when the fight stops, the Map is switched, or a Monster
is stamped.

### `<map>.combat/<timestamp>.jsonl` — one Combat Log per Encounter

Append-only JSON Lines, written by `CombatLogWriter`: one object per line, **appended and
fsynced on every call, never rewritten** (ADR-0008, ADR-0010). Named for the UTC second the
Encounter started — `2026-09-16T201500Z.jsonl` — so files sort as text.

Four kinds of line, tagged by `line`:

```jsonl
{"combatants":[{"block":{…},"id":"A…","initiative":17,"kind":"player","name":"Thorin"},{"block":{…},"id":"B…","initiative":12,"kind":"creature","name":"GG1"}],"line":"encounterStarted","order":["A…","B…"],"startedAt":"2026-09-16T20:15:00Z"}
{"changes":[{"combatantID":"B…","from":27,"to":19,"type":"hpChanged"},{"combatantID":"A…","distanceSquares":4,"from":{"imagePixels":{…}},"to":{"imagePixels":{…}},"type":"moved"}],"combatantID":"A…","endedAt":"2026-09-16T20:16:40Z","line":"turn","round":1}
{"changes":[{"combatantID":"B…","from":19,"to":21,"type":"hpChanged"}],"line":"correction","recordedAt":"2026-09-16T20:25:02Z","targetCombatantID":"A…","targetRound":1}
{"endedAt":"2026-09-16T20:41:10Z","line":"encounterEnded"}
```

| Line | Fields | Meaning |
|---|---|---|
| `encounterStarted` | `startedAt`, `order` (Combatant IDs), `combatants` (snapshots: `id`, `name`, `kind`, `initiative`, `block`) | Opens the file. This line alone reconstructs the state the fight began in. Treasure is never a Combatant. |
| `turn` | `round`, `combatantID`, `changes[]`, `endedAt` | Written when a Turn **ends**. Carries every Change made while it ran, including Changes to other Combatants. |
| `correction` | `targetRound`, `targetCombatantID`, `changes[]`, `recordedAt` | Appended later, naming the Turn it amends. The original Turn line is untouched. |
| `encounterEnded` | `endedAt` | Closes the file. A file without one is a fight still running. |

**Changes** (`type`) are externally tagged, and every mutation carries the value **before and
after**, never a delta, so a replay is exact and a Correction is unambiguous:

| `type` | Payload | Folded into state? |
|---|---|---|
| `hpChanged`, `maxHPChanged` | `combatantID`, `from?`, `to?` (optional ints; absent = untyped) | yes |
| `tempHPChanged`, `acChanged`, `exhaustionChanged`, `initiativeBonusChanged` | `combatantID`, `from`, `to` | yes |
| `initiativeChanged` | `combatantID`, `from`, `to` — the *rolled* number | yes (does not re-sort) |
| `conditionAdded`, `conditionRemoved` | `combatantID`, `condition` | yes |
| `concentrationChanged` | `combatantID`, `isConcentrating` | yes |
| `orderChanged` | `order[]` — the whole new Order, no `combatantID` | yes (ADR-0008: the Order is recorded, never recomputed) |
| `combatantJoined` | `combatantID`, `name`, `kind`, `initiative`, `block` | yes — also how a Benched Pawn returns |
| `combatantRemoved` | `combatantID` | yes — means **Benched**, not deleted; the wire name predates the term |
| `moved` | `combatantID`, `from`, `to` (image pixels), `distanceSquares` | **no** — where a Pawn stands is the Map's truth |
| `noteAdded` | `combatantID`, `text` | **no** — something to read |
| `savingThrow` | `combatantID`, `name`, `ability`, `d20`, `modifier`, `difficultyClass?` | **no** — a Roll is recorded, not resolved (ADR-0017) |
| `abilityCheck` | `combatantID`, `name`, `skill`, `d20`, `modifier`, `difficultyClass?` | **no** — the Skill's Ability is derived, never stored |

Notes on the format:

- Dropping to 0 HP appends `conditionAdded: unconscious` and, if concentrating,
  `concentrationChanged: false` as consequences in the same Turn.
- A `moved`, `savingThrow` or `abilityCheck` can never be a Correction; the app refuses to
  file one against a past Turn.
- `difficultyClass` is **absent** (not `null`) when the DM recorded no DC; `total` and
  `succeeded` are never on disk.
- A `type` this version does not know decodes as `unrecognised`, is skipped by the fold, and
  is never written back. A truncated final line (the crash case) is dropped on read, not an
  error. An absent file reads as "nobody has fought here".
- **Rounds are history**: re-rolling Initiative re-sorts the Order but never resets the Round.

**Reading it back.** `CombatLogFold` derives the whole tracker — Order, Round, whose Turn,
every Stat Block, the bench — from the lines. Corrections are applied at the Turn they target,
not where they sit in the file. The Round is the one *after* the last written Turn, so a Log
ending on the last Combatant of Round 2 resumes at the top of Round 3.

## The Workspace: `.mapforge/`

Every file here is pretty-printed, sorted-key, atomically written JSON, so a DM who keeps
their game in version control sees one-line diffs. Nothing here is gitignored: it is all the
DM's own data.

### `workspace.json` — the Manifest

The file whose presence makes a folder a Workspace. Written once, at adoption, by
`WorkspaceStore.adopt`; re-adopting an existing Workspace does not rewrite it.

```json
{ "version": 1, "createdAt": "2026-09-01T10:12:00Z", "createdBy": "1.0" }
```

Deliberately **no name**: the folder's name is the Workspace's name, so nothing can drift when
the DM renames it in Finder. `version` is a hard decode — a file without one is refused, and
a version newer than the app's is refused rather than guessed at. `createdBy` is the app
version, for diagnosis only.

### `parties.json` — the roster

```json
{
  "version": 1,
  "parties": [
    { "id": "…", "name": "Eroi delle Terre di Confine",
      "characters": [
        { "id": "…", "name": "Durga", "colorHex": "#D0342C", "sightSquares": 6,
          "noteName": "Durga Pietraferma" }
      ] }
  ]
}
```

A Character is a **definition**, never on a Map. It holds what the app owns of it — its
label, colour and sight — and `noteName`, the `name` of the note its numbers are read from,
absent while the DM has not linked one (ADR-0024). Stamping copies `name`, `colorHex`,
`sightSquares` and the note's size into a Pawn, and the note's `initiative`, `ac` and `hp`
into its Stat Block; a Character with no readable note stamps no Stat Block at all. The Pawn
then leads its own life (ADR-0007). `characters` is an array so the DM's order is kept. A
roster written before notes still opens with every Character unlinked: its `isBig`,
`initiativeBonus`, `armorClass` and `maxHP` are ignored and dropped at the next write.
Absent when there are no Parties; unreadable file latched.

### `preferences.json` — what the app chooses for this Workspace

```json
{ "activePartyID": "…", "playerDisplay": { "uuid": "…", "name": "LG TV" } }
```

Which Party the Control Window offers, and which screen is the Player Display, keyed by
Display Identity (the display's UUID, not its `CGDirectDisplayID`). Both are one-click
choices, so this store is *forgiving*: an unreadable file is replaced by defaults on the
next save rather than latched.

### `config.json` — no longer read

It once held `bestiaryStatBlockPath`, the one folder the Bestiary was read from (ADR-0020).
The Bestiary now reads the whole Workspace (ADR-0023), so the app reads nothing from this
file and never writes it. One left by an older build, or by DM Realm's Setup, is harmless.

### The Bestiary — never saved

The **Bestiary is never saved**: it is a reading of every markdown note in the Workspace,
hidden folders (`.git`, `.obsidian`, `.mapforge`) aside, taken when the Workspace opens and at
no other time. A note is a Monster when it contains a ```` ```statblock ```` YAML fence with
at least a `name`, unless the fence says `bestiary: false` or has a key only a
Character's has (`player`, `species`, `class`, `level`). A fence with `extends: <name>` is
that Monster with the fence's own keys laid over it, each replacing the base's value whole. The same walk reads every
Character's note (a fence with a Character-only key and no `bestiary: false`) for its `name`,
`ac`, `hp`, `initiative` and `size` (ADR-0024); those are never saved either. What a Monster stamps onto a Pawn
(`armorClass`, `hitPoints` → `maxHP`/`currentHP`, `initiativeBonus`, size → `isBig`) is
copied into `stats.json` and `.fog.json`; only the name is remembered in `monsterName`.

### `sessions/<timestamp>.jsonl` — one Session Log per evening

Append-only JSON Lines, written by `SessionLogWriter` with exactly the Combat Log's
discipline — one object per line, appended and fsynced, never rewritten — and deliberately
its own vocabulary (ADR-0014, ADR-0015). Named for the UTC second the Session started.
Held at the Workspace level because an evening outlives the Map it begins on.

```jsonl
{"line":"sessionStarted","startedAt":"2026-09-16T19:00:00Z"}
{"at":"2026-09-16T19:03:41Z","line":"comment","map":"maps/crypt/dungeon.png","text":"The party enters the crypt"}
{"at":"2026-09-16T19:05:12Z","distanceSquares":3.2,"from":{"imagePixels":{…}},"label":"Thorin","line":"pawnMoved","map":"maps/crypt/dungeon.png","pawnID":"A…","to":{"imagePixels":{…}}}
{"ability":"wisdom","at":"2026-09-16T19:09:30Z","d20":14,"difficultyClass":13,"label":"Thorin","line":"savingThrow","map":"maps/crypt/dungeon.png","modifier":1,"pawnID":"A…"}
{"at":"2026-09-16T20:15:00Z","line":"encounterStarted","logFile":"2026-09-16T201500Z.jsonl","map":"maps/crypt/dungeon.png"}
{"at":"2026-09-16T20:41:10Z","line":"encounterEnded","map":"maps/crypt/dungeon.png"}
{"endedAt":"2026-09-16T23:10:00Z","line":"sessionEnded"}
```

| `line` | Fields | Meaning |
|---|---|---|
| `sessionStarted` | `startedAt` | Opens the file. |
| `comment` | `text`, `map?`, `pawnID?`, `at` | The DM's own text from the Comment Bar. `pawnID` is what was selected when typing — beside the text, not its subject — and nothing fills it yet. |
| `pawnMoved` | `pawnID`, `label`, `map?`, `from`, `to`, `distanceSquares`, `at` | A completed drag outside a fight. `label` is a snapshot so the line reads without the fog file. |
| `savingThrow` | `pawnID`, `label`, `map?`, `ability`, `d20`, `modifier`, `difficultyClass?`, `at` | A Roll outside a fight; here `pawnID` *is* the subject. |
| `abilityCheck` | `pawnID`, `label`, `map?`, `skill`, `d20`, `modifier`, `difficultyClass?`, `at` | As above, by Skill. |
| `encounterStarted` | `map?`, `logFile`, `at` | **The pointer**: names the Combat Log (bare file name, inside `<map>.combat/`) that holds what happened next. The Session Log then falls silent. |
| `encounterEnded` | `map?`, `at` | Recording resumes here. |
| `sessionEnded` | `endedAt` | Closes the file. A file without one is an evening still running. |

`map` is the Map's path **relative to the Workspace root** (`maps/crypt/dungeon.png`), so two
`dungeon.png` in different folders are told apart and the name survives the folder moving to
another Mac (ADR-0016). A Map outside the Workspace is named by bare file name, and its
Encounters cannot then be resolved by the Log View. A Map *switch* writes no line; the Log
View infers one from consecutive lines disagreeing about `map`.

An unknown `line` decodes as `unrecognised` (kept, positionally, never written back); a
malformed final line is dropped on read.

## The machine: `UserDefaults`

`recentWorkspaces`: the paths of Workspaces this Mac has opened, most recent first,
capped at 20. It is the bootstrap pointer — the one thing that cannot live inside the
Workspace it points at — and it is the list the Workspace picker offers. Nothing is
removed automatically: an unplugged drive stays listed as unavailable until the DM forgets
it. UI tests run against a throwaway suite so they never touch this list.

`recentWorkspaceBookmarks`: a security-scoped bookmark for each of those entries, keyed by
its path, which is how a Workspace is reached on a later launch under the App Sandbox
(ADR-0025). Rewritten every time the Workspace opens, and dropped with its entry. An entry
with no bookmark — written before bookmarks existed — gets one made from its path the first
time the picker lists it, where that is allowed.

**Calibration** (the per-display True Scale correction) will live here too, keyed by Display
Identity, when it is built. It is not built; nothing is stored for it yet.

**Legacy, migrated once.** Before Workspaces existed the roster lived at
`~/Library/Application Support/MapForge/parties.json` and `activePartyID`,
`playerDisplayUUID`, `playerDisplayName` lived in `UserDefaults`. The first Workspace opened
while that file exists copies it in (copy, read back, compare, only then retire), carries the
three keys into `preferences.json`, renames the old file to `parties.json.migrated` and
deletes the three keys. A Workspace that already has a `parties.json` is never overwritten.

## One evening, end to end

How the files above point at each other while the DM plays. "Exactly one recorder is live at
any instant" (ADR-0014) is the rule every arrow below follows.

```
Workspace opened ──► resume newest sessions/*.jsonl if it has no sessionEnded
                     read parties.json, preferences.json; every note → Bestiary
Map opened ────────► read <map>.fog.json, <map>.combat/stats.json
                     resume newest <map>.combat/*.jsonl if it has no encounterEnded

Start Session ─────► sessions/T.jsonl        {sessionStarted}
  comment / move / roll ─────────────────────► appended to sessions/T.jsonl
  Start Encounter ─► <map>.combat/U.jsonl     {encounterStarted, order, combatants}
                     sessions/T.jsonl         {encounterStarted, logFile: "U.jsonl"}  ← pointer
                     sessions/T.jsonl is now SILENT
    every Change ──► buffered in memory; stats.json follows the fold (debounced)
    End Turn ──────► <map>.combat/U.jsonl     {turn, changes[…]}          ← fsync
    move / roll ───► go into the Turn's changes, not the Session Log
    step back + edit ► <map>.combat/U.jsonl   {correction, targetRound…}  ← fsync
  Stop Encounter ──► <map>.combat/U.jsonl     {turn (if pending)} {encounterEnded}
                     stats.json flushed
                     sessions/T.jsonl         {encounterEnded}            ← recording resumes
Stop Session ──────► sessions/T.jsonl         {sessionEnded}
```

What follows from the shape:

- **Starting a fight needs a running Session** — otherwise there would be a Combat Log no
  Session points at. A fight already running is not ended by the Session ending.
- **Stopping the Session mid-fight** writes `sessionEnded`; the Combat Log stays open and
  keeps recording until the DM stops the fight. Both files are kept; nothing is deleted.
- **Quitting the app ends nothing.** An unterminated Session or Encounter is honest — it
  records what was known — and is picked up on the next open of that Workspace or Map. No
  end line is ever invented.
- **Switching Map mid-fight** closes the Combat Log's file handle without ending the fight;
  reopening the Map resumes it from the Log. The Session stays suspended meanwhile, because
  no `encounterEnded` has been written — Comments are dropped, and a new fight started on
  the other Map opens its own Combat Log but writes **no pointer** into the Session Log, so
  the Log View cannot show it. Stop the fight on the first Map before starting another.
- **Switching or closing the Workspace** stops the Session on the record first, so its file
  never receives another Workspace's lines.
- **The Log View** reads the current Session file in order and splices each Combat Log in at
  its pointer; it never compares timestamps and never edits (ADR-0016). A pointer whose file
  cannot be found is drawn as unreadable rather than skipped. The running fight is read from
  memory, so a Turn appears the moment it ends.

## Durability, in one table

| File | Written when | How | On unreadable |
|---|---|---|---|
| `.fog.json` | every fog edit, 0.5 s debounce, last wins; flushed on Map switch, quit, Pawn add/remove | atomic replace, pretty | warned in UI; the next edit **replaces** it |
| `stats.json` | prep edits (debounced); every fold during a fight; flushed on fight stop, Map switch, Monster stamp | atomic replace, pretty | reported, **writes refused** |
| `<map>.combat/*.jsonl` | every Turn end, Correction, join/bench/reorder/re-roll, fight start/stop | append + fsync, one line | truncated tail dropped |
| `sessions/*.jsonl` | every Comment, move, Roll, pointer, start/stop | append + fsync, one line | truncated tail dropped |
| `parties.json` | every roster edit | atomic replace, pretty | reported, writes refused |
| `preferences.json` | Party or display chosen | atomic replace, pretty | replaced by defaults |
| `workspace.json` | adoption only | atomic, once | Workspace refused to open |
| `UserDefaults` | Workspace opened / forgotten | system | — |

Common to everything: UUIDs as strings, dates as ISO 8601 UTC, points as
`{"imagePixels": {"x", "y"}}`, distances and radii in Grid squares, colours as `#RRGGBB`.
Optional values are **omitted**, never `null`. A document with nothing in it deletes its file.
A version number is stamped on write, not echoed from the read.

## What is never saved

Live performance state that belongs to the moment, not the record:

- **Measurements** and **Pinned** Measurements — cleared with the Map they were taken on.
- **Solo Sight** — which Pawn the table is seeing through.
- **Viewport** position, **Magnifier**, **Blackout**, the **Fog Overlay** switch and the
  **Measurement visibility** switch.
- Map **rotation** and display scale (the Sidecar `CONTEXT.md` describes for them is not
  built).
- The **Bestiary** — re-read from the notes on every Workspace open, never cached.
- The current Turn's Changes until the Turn ends — at most one Turn is lost to a crash,
  which is the trade ADR-0008 makes.
- Anything about window positions or the last tool used.
