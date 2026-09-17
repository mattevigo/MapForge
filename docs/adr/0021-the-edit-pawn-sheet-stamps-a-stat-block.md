# The Edit Pawn sheet's OK stamps a Stat Block

`EditDraft.swift` is emphatic that the Edit Pawn sheet does not touch a Stat Block: "it lives
in its own file and has its own editor (ADR-0009), and one OK button writing two persistence
layers is where save semantics get murky." The Bestiary (ADR-0020) puts a Monster search box
in that sheet, beside the Kind picker, and picking a Monster must reach
`<map>.combat/stats.json`. So OK now writes both files. The rule is narrowed, not dropped.

## A stamp is not an edit

What the old rule guards against is *editing* Stat Block fields in the sheet: a half-typed
hit point total meeting Cancel, two editors for one number. None of that arrives. The sheet
still exposes no Stat Block field. It names a Monster, and on OK the app performs one
whole-value **stamp** — armour class, initiative bonus, maximum hit points, and current hit
points set to that maximum — the same act a Character's Stamp already performs. Temporary hit
points, Conditions, exhaustion and concentration belong to the fight and are left alone.

The semantics stay one sentence: **OK commits everything the sheet shows, Cancel commits
nothing.** The glossary's "the Edit Pawn sheet's Cancel is the escape" holds. ADR-0009
already accepted the mechanics — "two files must be written for one user action… independent
writes with independent failure."

## It stamps only when the Monster changed

OK with the Monster untouched leaves the Stat Block untouched. Otherwise opening a wounded
gnoll to change its colour would heal it.

## Healing asks first

Becoming a Monster means arriving at full hit points, so a stamp over a current hit point
total that already exists — from an earlier Monster or from the DM's own typing — destroys
information. That case, and only that case, is confirmed on OK, in words that name the loss
("12/27 → 45/45"); declining returns to the open sheet. A first stamp onto a Pawn with no
hit points asks nothing, and neither does **Add**'s inherited stamp, because a dialog that
appears when nothing can be lost is one the DM learns to click through.

During a live Encounter the stamp goes through the same path as any Stat Block edit, so the
Combat Log records it as Changes with before and after (ADR-0008). Initiative is not
re-rolled: changing a bonus does not by itself move anyone.

## Considered Options

- **Picking applies immediately, outside OK/Cancel** — rejected: it makes Cancel lie.
- **The sheet records only the Monster's name; numbers are copied when an Encounter starts**
  — rejected: that is a link wearing a copy's clothes, dependent on the note still existing
  later, and it leaves the DM unable to see or adjust the numbers during prep.
- **A stamp never touches current hit points once set** — considered, and rejected by the DM:
  changing what a Pawn *is* means it is a fresh one of those, and a half-wounded hybrid
  (12/45) is a state nobody meant. The confirmation is what makes the blunt rule safe.
