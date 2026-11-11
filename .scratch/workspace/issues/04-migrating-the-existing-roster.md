# 04 — Migrating the existing roster

Status: done

Depends on 03. Moves `~/Library/Application Support/MapForge/parties.json` into the first
Workspace opened, then removes it and the three stale `UserDefaults` keys.

## What is actually being moved

Exactly four things, verified on the developer's machine:

- `~/Library/Application Support/MapForge/parties.json` — the roster. Real: 2122 bytes, one
  Party, "Lost Boys".
- `activePartyID`, `playerDisplayUUID`, `playerDisplayName` in
  `~/Library/Preferences/com.mattevigo.MapForge.plist`.

Nothing else. No fog, no combat, no Map ever lived outside its own folder.

## Two hazards that decide the design

**`PartyStore.save` deletes the file when the book is empty** (`PartyStore.swift:62-65`). So
the migration must **never** be `load()` then `save()`. A decode that silently yields an empty
book — a schema surprise, a truncated file — would destroy the source while "succeeding".

**`partyLoadFailure` is a sticky, session-wide latch.** `writeParties` refuses every write for
the rest of the run once it is set (`AppState.swift:629-631`), silently. If migration lands
bytes the decoder then rejects, the DM gets a session where roster edits vanish with no
message. Issue 05 fixes the silence; this issue must not rely on that fix existing.

Together they force: **copy the bytes, verify the copy, then delete.**

## Build

`WorkspaceMigration`, run once from `AppState.open` when `workspace` goes from nil to non-nil:

1. If `~/Library/Application Support/MapForge/parties.json` does not exist — **stop, silently.**
   Its absence is the entire guard. No flag in `UserDefaults`, none in the Manifest: the guard
   and the outcome are the same fact, so they cannot fall out of step, and a DM who restores
   the file from a backup gets it picked up next launch, which is what they would want.
2. If the destination `<workspace>/.mapforge/parties.json` already exists — stop. Never
   overwrite a roster that is already there.
3. Load the source through `PartyStore` to get a `PartyBook` in hand. If it fails
   (`lastLoadFailure`), go to the failure path.
4. **Copy the bytes** with `FileManager.copyItem`. Not encode-and-write: a byte copy cannot
   lose a field the current model does not know about.
5. **Verify**: decode the destination with a fresh `PartyStore` and assert the resulting
   `PartyBook` equals the one from step 3. `PartyBook` is `Equatable` (`Party.swift:94`), so
   this is one comparison, and it is the check that makes the deletion safe.
6. Carry `activePartyID` into the Workspace's `WorkspacePreferences`, and the two display keys
   with it.
7. **Only now**: rename `parties.json` to `parties.json.migrated` and remove the three
   `UserDefaults` keys. The rename rather than a delete is the one departure from the brief:
   "removed" is satisfied — nothing reads it, it never reappears — and this is the one file in
   the app that is hours of someone's typing. The directory stays, since it holds the retired
   file. Leave the prefs plist; it still holds the recents list.
8. Show the alert.

Steps 4–7 are ordered so that every prefix of them is safe to stop at. Nothing is deleted
until the copy has been read back and matched.

## The alert

One alert, OK to dismiss, shown once ever:

> **Your parties have moved**
>
> "Lost Boys" is now stored in this workspace, in *Eroi_delle_Terre_di_Confine*. Parties live
> in a workspace now rather than on this Mac, so another workspace starts with an empty
> roster.

Name the destination folder and the Parties by name. The second sentence is the one doing real
work: it is rare for a DM to keep more than one Workspace, but the DM who does must not open
their second one, find no cast, and conclude the app ate it.

## The failure path

Any failure in steps 3–6: **the Workspace opens normally**, a warning is shown, and **nothing
is deleted.**

> **Couldn't move your parties**
>
> Your existing parties are still stored on this Mac and weren't changed. MapForge will try
> again next time you open a workspace. *(reason)*

The DM runs tonight's session regardless — a file-copy problem must not block the app. The
retry needs no bookkeeping, because step 1's guard is the source file still being there.

## Tests

- A source roster migrates into the Workspace; the source is gone afterwards; the three
  `UserDefaults` keys are cleared; the recents list survives.
- **The copy is verified before deletion**: inject a `FileManager` whose copy silently produces
  different bytes, assert the source **survives** and the warning fires.
- An unreadable source leaves it on disk, opens the Workspace, warns, and retries on the next
  open.
- A destination that already has `parties.json` is never overwritten.
- No source file → no alert, no warning, nothing written.
- Migration runs at most once: opening a second Workspace after a successful migration does
  nothing, because the source is gone.
- Round-trip fidelity: a `PartyCharacter` with `maxHP` nil (omitted on disk — "Drusilla" in the
  real file) survives byte-for-byte.
