# 05 — The Party load-failure latch loses edits silently

Status: done

Independent of 01–04 and can be done at any point, including first. It is a pre-existing bug,
not something this feature introduces — but the feature makes it considerably likelier to fire,
which is how it was found.

## The bug

`writeParties` refuses to write when the roster failed to load (`AppState.swift:627-633`):

```swift
guard partyLoadFailure == nil else { return }
```

The refusal is right, and its comment explains why: never write over a roster we could not
read. `FogStore` holds the same rule.

What is wrong is everything around it:

1. **The latch is set once at init and never cleared** (`AppState.swift:146`). There is no path
   that resets it for the life of the process.
2. **It is silent.** The DM adds a Character, sees it appear in the panel, and it is never
   written. Nothing in the UI says so. `partyLoadFailure` is `@Published` and, as far as the
   panel is concerned, unread.
3. **It is total.** Every subsequent edit is discarded, including edits to Parties that loaded
   fine, because the latch is one flag for the whole book.

So: a DM with a corrupted `parties.json` launches, sees an empty roster, retypes their party
over the course of a session, and loses all of it at quit. The guard exists precisely to
protect that DM's file, and the protection is invisible to them.

## Why the Workspace makes it worse

Today a process sees exactly one roster, so "set at init" and "for this process" coincide.
After issue 02 a process opens several Workspaces, and a failure carried in from one would
suppress writes in a healthy one. Issue 02 already requires clearing the latch on open; this
issue is the other half — telling the DM.

## Build

**Surface it.** When `partyLoadFailure != nil`, the Party group in `ControlView`
(`ControlView.swift:1327-1395`) shows a warning in place of the roster, not above it:

> **Your party roster couldn't be read**
>
> The file at *(path)* is damaged. MapForge hasn't changed it. Changes made here won't be
> saved until it's fixed or moved.

The path matters: `PartyStore.UnreadableFile` already carries `url` and `underlying`
(`PartyStore.swift:16-19`), and the DM's recovery is to open that file or move it aside.

**Disable roster editing while it is set**, rather than accepting edits that go nowhere. An
"Add Character" button that works and then discards is worse than one that is disabled with a
reason next to it.

**Offer the one safe recovery**: a "Start a New Roster" button that moves the damaged file to
`parties.json.damaged` and clears the latch. That is the only action that both preserves the
bytes and lets the DM work — and it is the DM's choice to make, never the app's.

## Tests

- A malformed `parties.json` leaves the file byte-identical after a session of roster edits.
- The warning appears with the path in it; the add/edit controls are disabled.
- "Start a New Roster" renames to `.damaged`, clears the latch, and the next edit writes.
- After 02: opening a healthy Workspace after a broken one clears the warning and writes.

## Comments

Found while grilling the Workspace design. `PartyStore` is written with real care about never
destroying a roster — the unreadable-file rule, the atomic write, the delete-on-empty — and
this is the one gap in it: the file is protected, and the DM's *replacement* for it is not.
