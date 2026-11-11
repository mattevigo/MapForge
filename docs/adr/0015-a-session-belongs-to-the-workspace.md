# A Session belongs to the Workspace, not to a Map

Every per-Map artefact in MapForge sits beside its image: `dungeon.fog.json` (ADR-0003),
`dungeon.combat/` (ADR-0009). A **Session** does not. It lives at
`.mapforge/sessions/<start>.jsonl` in the Workspace, and each line names the Map it happened
on.

## An evening outlives a Map

The party leaves the tavern and walks to the crypt. That is one evening and two Maps, and
every per-Map answer breaks on it:

**One file per Map touched** splits a continuous evening into fragments whose only relationship
is that their timestamps interleave. The walk between them — the thing that connects the two
halves — belongs to neither file.

**Switching Maps ends the Session** makes a bookkeeping act into a narrative boundary, and
makes the DM choose between opening the crypt and keeping the record.

`CONTEXT.md` already contained this argument, written before the word Session existed. The
**Party** entry says Parties belong to a Workspace "so they outlive the Map a session happens
to be run on". The reasoning that put the roster in the Workspace puts the evening there too,
and for the same reason: neither is about a Map.

## Every line names its Map

The Map could have been a property of the Session — recorded on the switch lines only, and
carried forward by a reader folding the file from the top.

It is on every line instead. A single line is then readable on its own: `grep` finds every
movement on the crypt Map without a fold, and a line torn out of context still says where it
happened. The cost is a repeated field in a file that is already one JSON object per line and
never pretty-printed.

A Session therefore needs no Map at all. It can start before one is opened and continue after
one is closed, and those lines carry no Map — a Comment typed while the party is still deciding
where to go is part of the evening. This is the opposite of an Encounter, which `startEncounter`
refuses without a `mapURL`, and the difference is the point: a fight happens *on* a Map, an
evening merely crosses some.

## Consequences

Starting a Session requires a Workspace and nothing else. There is nowhere to write without
one, so the control is disabled until a Workspace is open — the same refusal `startEncounter`
already makes for a missing Map, rather than a file picker appearing when the DM presses Start
in front of the players.

A Session ends only when the DM stops it. Quitting mid-evening leaves the log unterminated,
and the app finds it still running when it returns, exactly as `resumeEncounter`
(`AppState+Combat.swift:333-343`) already does for an unfinished Combat Log. An unterminated
file is honest: it records what was known.

`.mapforge/` gains its second inhabitant. ADR-0011 chose a Workspace folder precisely so that
the next thing the app stores about a DM would have somewhere to go without a new decision, and
this is that next thing arriving as predicted.

The Workspace becomes the unit a DM's history accumulates in. A DM running several campaigns
from one Workspace gets their evenings interleaved in one `sessions/` folder, as they already
get their Parties in one list. ADR-0011 accepted that trade knowingly and deferred a Campaign
concept; nothing here changes it.

## Considered Options

- **`<map>.sessions/` beside the image, one file per Map** — rejected: an evening across two
  Maps becomes two fragments, and the walk between them belongs to neither.
- **Per-Map, with a Map switch ending the Session** — rejected: it makes opening a file into a
  narrative boundary and forces the DM to choose between the crypt and the record.
- **Application Support, keyed by Workspace path** — rejected for the reason ADR-0009 and
  ADR-0011 both rejected it: it breaks when the DM moves the folder, and it separates the data
  from the thing it is about.
- **The Map as a Session-level property, folded from switch lines** — rejected: it makes a
  single line unreadable on its own, to save a repeated string in a format that is already
  line-oriented and greppable.
