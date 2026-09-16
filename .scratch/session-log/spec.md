# Session Log: record the evening, not just the fight

Status: closed 2026-09-16 — all five issues done; 889 unit tests and 7 UI tests green, no at-the-table check

MapForge records a fight in exhaustive detail and records nothing else. The Combat Log holds
every hit point, every Condition and every completed drag — but only between `startEncounter`
and `stopEncounter`. `recordChange` is a no-op without an Encounter (`AppState+Combat.swift:200`),
and `commitPawnMove` bails on the same guard (`:222`). The corridor the party walked to reach
the fight is remembered by nobody.

This feature adds a **Session**: the evening itself, enclosing the fights inside it. It records
Pawn movements and the DM's **Comments**, typed into a new **Comment Bar** beneath the Map.

See `CONTEXT.md` for the six terms this is written in — Session, Session Log, Comment, Comment
Bar, Setup Toolbar, Live Toolbar — and:

- `docs/adr/0014-the-session-log-falls-silent-during-an-encounter.md` — one recorder at a time
- `docs/adr/0015-a-session-belongs-to-the-workspace.md` — where the file lives, and why

## The shape of it

A **Start Session** button joins the Live Toolbar (the fog/measurement switch row). Pressing it
opens `.mapforge/sessions/<start>.jsonl` in the Workspace and enables the **Comment Bar**, a
full-width row of one text field and a send button beneath the Map.

While the Session runs, every completed Pawn drag writes a line. Every Comment writes a line.
Each line names the Map it happened on.

When an Encounter starts, the Session Log writes one line naming that Encounter's Combat Log
file and **falls silent** — the Comment Bar disables, and the Combat tab's note box is the live
one. When the Encounter stops, the Session Log resumes and the Comment Bar comes back.

## Rules worth stating once

- **Exactly one recorder is live at any instant.** The Session Log stops while an Encounter
  runs. It is not a subset-recorder, not a second copy: it writes a pointer and goes quiet.
  This is ADR-0014, and it is the rule the whole feature is shaped around.
- **A Session needs a Workspace and not a Map.** There is nowhere to write without a Workspace,
  so the button is disabled until one is open — the refusal `startEncounter` already makes for
  a missing Map. A Map is not required: lines written with none carry a null map, because a
  Comment typed before the crypt is opened is still part of the evening.
- **Every line names its Map**, rather than the Map being folded from switch lines. A single
  line is then readable on its own and the file is greppable. ADR-0015.
- **A Session ends only when the DM stops it.** Quitting leaves the log unterminated and the
  app finds it still running, exactly as `resumeEncounter` does for an unfinished fight.
- **The Comment Bar has three states and its placeholder says which.** Disabled before a
  Session ("Start the session to record"), enabled during one ("what happened"), disabled
  during a fight ("Note on Grix's turn — use the Combat tab"). The send button greys with the
  field rather than disappearing: it will work later, and a missing button says it does not
  exist.
- **A Comment has no target.** Unlike every `Change`, which is keyed on `combatantID`. The line
  format reserves a place for the selected Pawn — *beside* the text, so a later reader could
  see what the DM was looking at without the Comment claiming to be about it — but **nothing
  fills it**: the Live View has no Pawn selection to read, and the Combat tab's row selection
  is meaningful only during a fight, which is exactly when the bar is disabled. Wiring it needs
  a Live View selection this app does not have.
- **The Session Log gets its own vocabulary.** Not `Change` (keyed on `combatantID`, and a Pawn
  outside a fight has no Combatant), not `LogLine` (shaped around Rounds and Turns, which a
  Session has neither of). The JSONL *discipline* is shared; the types are not.
- **Nothing in the Setup Toolbar is disabled once a Session starts.** A DM sometimes must trace
  a wall mid-evening, because the party went somewhere never prepared. The Comment Bar's
  enabled state is the only enforcement of the boundary, deliberately.

## Files

```
Workspace/
├── .mapforge/
│   ├── workspace.json
│   ├── parties.json
│   └── sessions/
│       ├── 2026-09-16T190000Z.jsonl      ← one evening
│       └── 2026-09-17T193000Z.jsonl      ← another
└── maps/
    ├── dungeon.png
    ├── dungeon.fog.json                   ← untouched
    └── dungeon.combat/                    ← untouched
```

## Out of scope

Deliberately, so none of it reads as an omission:

- **Everything but movements and Comments.** Lights doused, Blackout, Solo Sight, Pawns added
  or deleted, Walls and Grid changes are not Session Log lines. This is a first cut, chosen
  knowingly: the Comment is the escape valve, and JSONL takes new line types additively.
  ADR-0014 records the trade.
- **A reading UI.** No timeline, no scrollback, no export. The bar is a write-only control and
  the file is human-readable JSONL — the same trade ADR-0008 made for the Combat Log.
- **Editing or deleting a Comment.** Append-only means append-only. If Corrections are ever
  wanted here, they are ADR-0010's shape, not a mutable field.
- **Blocking prep controls during a Session.** Q7 settled this as a soft boundary; making
  `PreviewMode` authoritative means lifting view-local `@State` into `AppState` and
  reconciling it with `fogEditingMapURL`. Separate work, if ever.
- **Per-campaign scoping of sessions.** ADR-0011 deferred a Campaign concept and nothing here
  revisits it. A DM running several campaigns gets interleaved evenings in one folder, as they
  already get one Party list.

## Issues

1. `01-the-session-log-format.md` — `SessionLine`, `SessionLogFile`, writer and reader. Pure model.
2. `02-the-session.md` — `Session`, start/stop/resume, the silence rule. Pure logic.
3. `03-wiring-the-session-to-appstate.md` — `AppState` holds it, movements and Encounter hand-off.
4. `04-the-comment-bar.md` — the view beneath the Map, its three states, the send button.
5. `05-the-live-toolbar-button.md` — Start/Stop Session in the switch row, and the toolbar names.

Sequential: 01 → 02 → 03, then 04 and 05 which both depend on 03 and can go in either order.
