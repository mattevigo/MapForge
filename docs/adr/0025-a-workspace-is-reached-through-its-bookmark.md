# A Workspace is reached through its bookmark

ADR-0011 put the DM's game in a Workspace folder and claimed the cost ADR-0007 feared was not
real: "the app does not need" security-scoped bookmarks, because it is not sandboxed. That
was true of an ad-hoc signed build. On 2026-10-08 MapForge was set on the Mac App Store, and
every app there runs in the **App Sandbox**. Inside the sandbox, a folder the DM chose is
reachable only for the launch it was chosen in. A recents list of paths would come back the
next morning listing every campaign, none of them openable.

The Workspace stays where ADR-0011 put it. What changes is how the app gets back to it.

## A bookmark beside every recent

Each entry in the recents list carries a **security-scoped bookmark** to its folder, made from
the URL the folder was handed over by: the open panel's the first time, the resolved
bookmark's after that. Opening a recent Workspace resolves its bookmark, so a folder the DM has
renamed or moved in Finder is still found, and the entry follows it to the new path.

A fresh bookmark is stored **every time a Workspace opens**. That is the refresh Apple asks for
when a bookmark goes stale, done whether or not it was asked for, so staleness never needs to
be noticed.

The bookmarks sit **beside** the list of paths, keyed by path, rather than replacing it. The
list keeps the shape every earlier version wrote. A downgrade still finds its recents, and an
entry from before bookmarks is simply a path with nothing beside it.

## One Workspace holds access at a time

The open Workspace holds security-scoped access to its folder for as long as it is open, and
gives it back when another Workspace opens or this one closes. Everything inside it — `.mapforge/`,
the Maps, the DM's notes — is reached under that one grant, so nothing below the Workspace
needs a bookmark of its own.

The picker checks whether a recent is available **under that folder's own access**, taken
for the check and given straight back. Under the sandbox, a path the app holds no grant for
reads as missing. A plain existence check would mark every recent unavailable, the drive that
really is unplugged and the folder that is fine alike.

## Old entries are upgraded quietly

An entry with a path and no bookmark gets one made from its path the first time the picker
lists it. Unsandboxed, that always works for a folder that exists, so a DM updating the zip
build sees their recents exactly as before. Under the sandbox it never works, since there is no
grant for a path the DM did not choose this launch. The entry then reads as unavailable, as an
unplugged drive does (ADR-0012), and choosing the folder once more stores its bookmark.

## Consequences

This lands **before** the sandbox is switched on. Bookmarks are made and resolved the same way
unsandboxed, so the app reaches its Workspaces by one route whether or not the sandbox is on.
Signing, entitlements and the sandbox itself are separate work.

ADR-0011's paragraph on Maps — "Open Map… still opens a file from anywhere on disk" — does not
survive the sandbox. Picking one image grants that image, not the folder beside it, so its
`<map>.fog.json` and `<map>.combat/` could not be written. Keeping Maps inside the Workspace is
its own change (ADR-0026). This ADR only records that the Workspace's access is what a Map will
rely on.

Switching Workspaces gives the old folder's access back. A Map still open from the old
Workspace loses its access with it under the sandbox, and so does any fog write still
waiting to be saved.

## Considered Options

- **Replace the paths with bookmarks** — rejected. It breaks every earlier version's reading of
  the list, and a bookmark is not something to show the DM: the path is still needed to
  display the entry.
- **Keep the bookmarks in `.mapforge/`** — rejected. The recents list is the bootstrap pointer,
  and it cannot live in the thing it points at (ADR-0012).
- **Show entries without a bookmark as unavailable** — rejected. In the unsandboxed build,
  which ships this first, every campaign a DM had already opened would read as unavailable
  for no reason.
- **Hold access to every recent Workspace** — rejected. Only one Workspace is open, and access
  held for folders the app is not using is a grant outliving its use.
- **Bookmark each Map as it is opened** — rejected for now. The Workspace's grant already
  reaches every Map inside it, and Maps outside it are a question of what a Workspace is, not
  of bookmarks.
