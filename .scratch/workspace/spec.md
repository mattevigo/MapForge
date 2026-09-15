# Workspace: the folder a DM keeps their game in

Everything the app stores that is not about a Map lives in one file in Application Support:
`parties.json`, plus three keys in `UserDefaults`. That was fine while the roster was the only
such thing. It stops being fine the moment there is a second thing — and "the app is evolving"
is exactly the claim that there will be.

This feature gives that data a folder the DM owns. The DM picks a **Workspace**; `.mapforge/`
inside it holds the Parties, the active-Party pointer and the Player Display choice; the next
feature that needs to store something puts it there without a new decision. The existing
roster is migrated in and the old file removed.

See `docs/adr/0011-the-dms-game-lives-in-a-workspace-folder.md` for the reversal this rests on,
`docs/adr/0012-the-workspace-travels-the-machine-stays.md` for the rule that decides where any
future state goes, and `CONTEXT.md` for **Workspace** and **Manifest**.

## The shape of it

A **Workspace** is a folder the DM already has: their maps, in whatever subfolders they keep
them in — one campaign or a shelf of them. The app adds `.mapforge/` at its root, containing
`workspace.json` — the **Manifest**, whose presence is what makes the folder a Workspace — and
`parties.json` beside it. Flat, no subfolders, no generated `.gitignore`.

A Workspace draws no line between the campaigns inside it. Its Parties are one list, exactly as
they are today; the DM separates campaigns with folders, and the app does not learn a second
way to do it.

The Workspace is named by its folder. No name is stored anywhere, so there is nothing to drift
out of step when the DM renames it in Finder.

At launch the Control Window comes up behind a **picker sheet**: the recents list, and one
"Choose Workspace…" button. Pick a folder — if it has a Manifest it opens; if not, the app
offers to adopt it. The last Workspace opened is reopened by default, so the sheet is only
seen on the first launch, after a switch, or when the remembered folder is gone.

Switching Workspaces re-presents the same sheet. It stops presenting and ends any live
Encounter, after a confirm that names the Map and says the Combat Log is kept.

## Rules worth stating once

- **The Workspace travels, the machine stays.** Parties, the active Party and the Player
  Display choice go in `.mapforge/`. The recents list and (when it exists) Calibration stay in
  `UserDefaults`. ADR-0012 is the long version.
- **Maps are untouched.** `<map>.fog.json` and `<map>.combat/` stay beside the image, and
  "Open Map…" still opens a file from anywhere on disk — inside the Workspace or not. A Map
  outside the Workspace behaves exactly like one inside it.
- **Adoption is non-destructive.** Adopting a folder writes `.mapforge/` and nothing else. It
  never moves, renames or touches a Map, a `.fog.json` or a `.combat/`.
- **Migration is copy, verify, then delete.** Never load-and-save: `PartyStore.save` deletes
  the file when the book is empty (`PartyStore.swift:62-65`), so a transient empty book would
  destroy the source. Byte copy, decode the copy, compare to what was loaded, and only then
  remove the original and the three `UserDefaults` keys.
- **Migration failure is not fatal.** The Workspace opens, a warning explains, nothing is
  deleted, and the next Workspace opened tries again. The absence of `parties.json` is the
  only guard needed — no flag, nothing to fall out of step.
- **A second Workspace starts empty.** Rare, since one Workspace holds everything a DM has,
  but true: the roster moved into the first Workspace opened and does not follow. Worth a line
  in the migration notice, not a feature.

## Out of scope

Deliberately, so it is not read as an omission:

- **The Map list.** A Workspace that shows its Maps — the thumbnail grid, the recursive scan,
  the file watching — is what `Library` promised and what makes a Workspace visible rather
  than merely chosen. It is the next feature. This one ships the vocabulary and the storage so
  that one is an addition and not a second reversal. **A Workspace in v1 has no visible effect
  beyond where Parties are stored**, and that is worth saying plainly before anyone is
  surprised by it.
- **Constraining "Open Map…" to the Workspace.** Follows from the above: with no Map list
  there is no alternative way in, so restricting the panel would remove function and add none.
- **A Campaign concept** scoping Parties within a Workspace. ADR-0011 records why it is
  additive later rather than founding.
- **Calibration.** Named in ADR-0012 so its home is settled, not built here.
- **The App Sandbox and security-scoped bookmarks.** ADR-0011 explains why they are not needed
  today and why turning the sandbox on is its own piece of work.
- **Moving a Workspace's Maps, or importing one Workspace into another.** Both are Finder
  operations today and a feature later, if ever.
- **Multiple Workspaces open at once.** One at a time.

## Issues

1. `01-the-workspace-and-its-manifest.md` — the `Workspace` value, `WorkspaceStore`, the
   Manifest, adoption. Model and disk only, no UI.
2. `02-workspace-scoped-preferences.md` — splitting `DisplayPreferences`; `PartyStore` and the
   active Party moving into a Workspace; the recents list.
3. `03-the-picker-sheet.md` — the launch gate, the recents list, adoption prompt, the
   unavailable state, switching, and the UI-test seam.
4. `04-migrating-the-existing-roster.md` — copy, verify, delete; the alert; the failure path.
5. `05-the-sticky-party-load-failure-latch.md` — a pre-existing silent-data-loss bug this
   feature makes likelier to fire.

1 → 2 → 3 → 4 is sequential. 5 is independent and can be done at any point.
