# 04 — The Roll sheet

Status: ready-for-agent
Blocked by: 01

One sheet, both Roll kinds, both entry points. UI only — the recorders are issues 02 and 03,
and wiring the buttons is issue 05.

## What to add

`MapForge/RollSheet.swift`, following `EditPawnSheet` (`EditSheets.swift:20-94`) — the
canonical modal, and its doc comment explains why a popover was rejected ("dismisses on
outside click, hostile in the middle of a text field"). That reasoning holds here twice over.

**Shape**, from the attached designs:

- Title: "Saving Throw" / "Ability Check". Subtitle is the live selection — "Choose the
  ability" before one is picked, "Dexterity Saving Throw" / "Stealth · Dexterity" after.
- **DC row** — a segmented 5/10/15/20 plus a free numeric field. Optional: it may be cleared,
  and clearing it is not an error.
- **Ability grid** (six, one row) or **Skill grid** (eighteen, 3 columns × 6 rows, each
  showing its Ability abbreviation on the right, as the design does). The grid is deliberate:
  it shows which Skill uses which Ability, which is the thing people forget.
- **d20 grid** — twenty faces, two rows of ten.
- **Modifier** — a stepper, signed display (`+0`, `+5`, `-1`), with the design's hint text.
- **Summary strip** — total, the arithmetic (`21 (16 + 5)`), `vs DC 15` when there is one,
  and a verdict pill: "Pending" until a face is chosen, then "Succeeded"/"Failed", or no
  verdict at all when there is no DC.

**Gating**: Record is enabled on a **d20 face alone**. Not on the DC, which is optional, and
not on the Ability/Skill — decide whether that is required and say so in the draft; the
design implies it is (the subtitle prompts for it), so require it.

**Keyboard**: `.keyboardShortcut(.cancelAction)` on Cancel, `.defaultAction` on Record. That
is the whole mechanism — no `NSEvent` monitors in a sheet.

**Draft**: a buffered `RollDraft`, as `EditPawnDraft` is. It carries the Pawn's id and label,
the kind, and the in-progress selection. It does **not** carry a `StatBlock` and must never
touch one — `EditDraft.swift:13-14` states the boundary and the ADR restates it.

Use `StatEditor`'s `NumberField` (`StatEditor.swift:206-259`) for the DC and Modifier rather
than binding directly — it commits on Return and on focus loss and guards against
re-committing unchanged text.

## Tests

`RollDraftTests` — Record gating (face only; face + DC; face + no DC; no face); the verdict
is absent with no DC; the draft produces the right `Roll` value.

## Done when

The sheet can be previewed and driven, and produces a `Roll` nothing yet consumes.
