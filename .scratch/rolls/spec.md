# Rolls: Saving Throws and Ability Checks

Status: ready-for-agent

A DM records what the dice showed at the table, so the Log can be read back next week. Two
new Roll kinds, two new buttons in each of two views, one sheet, two new record types in each
of the two Logs.

Settled in a grilling session; the decisions and their rejected alternatives are in
`docs/adr/0017-a-roll-is-recorded-not-resolved.md`. Vocabulary is in `CONTEXT.md` under
**Roll**, **Saving Throw**, **Ability Check**, **Ability**, **Skill**, **Difficulty Class**,
**Modifier**.

## What it is

A **Roll** is a record, never a resolution. The app does not generate the d20, does not
compute the Modifier, and does not apply what the result implies. It remembers.

- **Saving Throw** — carries an **Ability** (one of six)
- **Ability Check** — carries a **Skill** (one of eighteen); the Ability is derived from the
  Skill and never stored

Both carry: an optional **Difficulty Class**, the **d20** face, and a typed **Modifier**.
Success is `d20 + modifier >= DC`, computed on read, never stored. With no DC there is no
verdict, only a total.

## Where the buttons go

**Live View** — `ControlView.pawnLiveRow`, `ControlView.swift:1370-1427`. Two 16 pt icon
toggles joining the existing trailing icons (hide, Solo Sight, combat roster). Omitted for
`kind == .treasure` via `@ViewBuilder`, matching `combatRosterToggle` — conditional
visibility costs width, not height. Every control carries a `.help(...)` interpolating the
Pawn's label, as its neighbours do.

**Combat View** — `CombatPanel.row(_:id:)`, `CombatPanel.swift:269-321`. Two buttons in the
order row itself, styled as `bench` is: `.font(.system(size: 9))`, `.buttonStyle(.borderless)`.
Treasure needs no handling — it is refused as an `Entrant` and never appears in the Order.

The row is `.accessibilityElement(children: .combine)`, so these buttons are not addressable
from UI tests. Accepted: `bench` already lives under the same constraint, and the behaviour
worth testing is that pressing one records the right line, which is a model test.

## The sheet

One sheet, both entry points, both views. The destination is chosen by whether an Encounter
is live and **the call site does not branch** — `SessionControl` drops the Session write
during a fight, exactly as `commitPawnMove` relies on (`AppState+Combat.swift:229-241`).

Follows `EditPawnSheet` (`EditSheets.swift:20-94`): `.sheet(item:)` off an `Identifiable`
enum on `ControlView`, a buffered draft, `.keyboardShortcut(.cancelAction)` on Cancel and
`.defaultAction` on Record. No `NSEvent` monitors. No popover — it dismisses on outside click.

Layout follows the attached designs: a DC segmented control (5/10/15/20) with a free field
beside it, the Ability or Skill grid, a 20-face d20 grid in two rows of ten, a Modifier
stepper, and a summary strip showing the total, the arithmetic and the verdict. Record is
disabled until a d20 face is chosen — the DC is optional and does not gate it.

The sheet writes to a Log and **never** to a `StatBlock`. It does not call `editStatBlock`.
A failed save implying half damage is the DM's to apply with the existing Hit field.

## Strings

English, using the DnD 5.5e terms the rules use: "Saving Throw", "Ability Check", "DC",
"Record roll", "Succeeded"/"Failed". Abilities and Skills named in full, abbreviated only
where a control is too narrow. Domain display names go in `title` computed properties on the
new enums, beside `symbolName`, as `Condition` and `PawnKind` do.

The designs are in Italian; they are layout, not copy. The app is English throughout
(`developmentRegion = en`, no `.xcstrings` anywhere) and the glossary and every ADR are
English, so an Italian island would break the ubiquitous language.

## Window width

`livePanelWidth` 320 → 364 to fit the two buttons without shrinking the name column.

Separately and for its own reasons, `minimumMapColumnWidth` 420 → 584, putting the derived
`minimumWindowWidth` at 1000. See `docs/adr/0018-the-control-window-has-a-thousand-point-floor.md`.
The derivation at `ControlView.swift:1745-1746` is unchanged — only its input.

## Out of scope, deliberately

- **Ability scores on `StatBlock`.** The Modifier is typed. Remembering the last Modifier per
  Pawn is the cheaper next step if typing proves tiresome.
- **Advantage / disadvantage.** Record the die that counted. Safe to add later:
  `Change.unrecognised` means older builds keep reading.
- **Applying consequences.** One control, one action.
- **The app rolling the d20.** There is no RNG in this feature.
