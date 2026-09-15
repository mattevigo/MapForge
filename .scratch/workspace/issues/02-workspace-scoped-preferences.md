# 02 — Preferences split, and a roster that arrives late

Status: ready-for-agent

Depends on 01. Moves the Party roster and two preferences into the Workspace, and — the part
that is more work than it sounds — makes `AppState` able to load a roster it does not have at
init.

## The problem

`AppState.init` reads the roster eagerly (`AppState.swift:145-147`):

```swift
partyBook = partyStore.load()
partyLoadFailure = partyStore.lastLoadFailure
activePartyID = preferences.activePartyID
```

That works because `PartyStore` knows its directory at compile time. With a Workspace, none of
these three values exist until the DM has picked a folder, which happens after the window is
on screen. **This, not the file paths, is the real change in this issue.**

## Build

**`PartyStore` keeps its shape and loses its default directory.** It already takes
`init(directory:fileManager:)` (`PartyStore.swift:38`) and `PartyStoreTests` already passes a
temp dir, so the type barely changes: delete `defaultDirectory` (`PartyStore.swift:30-36`) and
construct it with `workspace.supportDirectory`. The load/save rules — missing file is normal,
unreadable file is reported and never overwritten, empty book deletes — are unchanged and must
stay unchanged.

**`WorkspacePreferences`** — the per-Workspace settings, `.mapforge/preferences.json`. Holds
`activePartyID: UUID?` and the Player Display (`playerDisplayUUID`, `playerDisplayName`).
Same store shape as `PartyStore`: concrete class, `init(directory:)`, atomic pretty-printed
write, a missing file meaning "nothing chosen yet".

**`DisplayPreferences` keeps its name and loses three keys.** Delete `activePartyID`
(`DisplayPreferences.swift:62-68`) and the two player-display keys
(`DisplayPreferences.swift:15-16, 42-54`). What remains is machine state: the recents list
added below, and later Calibration. The class comment (`DisplayPreferences.swift:9-12`) already
apologises for the name — update it rather than renaming the type, for the reason it gives.

**The recents list** — `[URL]` in `UserDefaults`, most-recent-first, deduplicated, capped
(20 is plenty). Store as an array of path strings. Opening a Workspace moves it to the front;
nothing removes an entry automatically, because 03 needs unavailable entries to stay listed.

**`AppState` opens a Workspace instead of being born with one.**

```swift
private(set) var workspace: Workspace?
func open(_ workspace: Workspace)   // builds the stores, loads the roster, sets activePartyID
func closeWorkspace()               // clears roster and activePartyID
```

`init` no longer loads anything party-related. `partyBook` starts empty, `partyStore` becomes
`private var partyStore: PartyStore?`, and every party mutation
(`AppState.swift:580-624`) plus `writeParties` (`AppState.swift:627`) must tolerate its
absence — the app is fully alive between launch and the DM picking a folder.

Keep `preferences: DisplayPreferences` injected as it is, and inject `WorkspaceStore` by the
same default-argument pattern (`AppState.swift:140-143`).

**Clear `partyLoadFailure` on open.** Today it is set once at init and never cleared
(`AppState.swift:146`), which is safe when a process sees one roster. Now a process sees
several, and a failure carried from a previous Workspace would silently suppress writes in a
healthy one — see issue 05, which is the same latch from the other side. Set it from the new
store's `lastLoadFailure` on every `open`, failure or not.

## Tests

- `open` loads the roster from `<workspace>/.mapforge/parties.json`, not Application Support.
- Editing a Party writes into the Workspace; a second `open` of the same folder reads it back.
- Opening Workspace A, then B, leaves A's Parties out of B.
- Opening a Workspace whose `parties.json` is malformed sets `partyLoadFailure`; opening a
  healthy one afterwards **clears** it and writes succeed. (This is the regression the latch
  would otherwise cause.)
- Party mutations before any Workspace is open do not crash and write nothing.
- The active Party round-trips through `.mapforge/preferences.json`, and a `UserDefaults` with
  a stale `activePartyID` has no effect.
- Recents: opening moves to front, no duplicates, cap enforced, a missing folder stays listed.
