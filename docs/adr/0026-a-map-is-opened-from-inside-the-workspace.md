# A Map is opened from inside the Workspace

ADR-0011 made the Workspace the home of the DM's game and left Maps out of it on purpose:
"Open Map… still opens a file from anywhere on disk", and a Map inside the Workspace and one
outside it "behave identically". The Workspace was where the DM's *other* material lived, not
a jurisdiction over files.

The App Sandbox makes it one. A Map is never just the image. `<map>.fog.json` holds its Walls,
Lights and Pawns, `<map>.combat/` its Stat Blocks and Combat Logs, and both are written
**beside** the image (ADR-0003, ADR-0009). Picking an image in the open panel grants that one
file, not the folder it sits in. The only grant that reaches a Map's folder is the
Workspace's (ADR-0025). A Map opened from elsewhere would show on screen, and then fail every
write: the first Wall traced, the first hit point taken.

## Inside, or refused

**Open Map…** opens images inside the open Workspace, at any depth, in whatever subfolders the
DM keeps. The panel starts in the open Map's folder when there is one in this Workspace, and
in the Workspace otherwise.

An image from outside is **refused**, and the DM is told why and what to do: the Map has to be
in their Workspace, named by folder, so they move it there in Finder and open it again. The
reason is given in the DM's terms, the files kept beside a Map, never in the sandbox's.

"Inside" is judged by where the Map's **folder** really is, with symlinks resolved, because
that folder is where the app writes and the sandbox judges access by the real path. A Map
reached through a link into the Workspace is inside. A Map behind a link inside the Workspace
that points elsewhere is not.

This is what `CONTEXT.md` already said a Workspace was: the folder whose Maps sit inside it.
The app now holds the DM to it.

## Consequences

Unsandboxed, the rule costs something it does not have to: the zip build could write beside
any image. It applies there anyway. Two builds disagreeing about which Maps open would be
worse than either rule, and the store build is the one being shipped.

A Session Line written before this rule, naming a Map that was outside the Workspace by its
bare file name, still reads as it did (`docs/data-on-disk.md`, *Session Log*). Nothing new is
written that way.

The test seam that loads a Map from the command line (`--test-map`) is not a DM's path and is
not held to the rule.

## Considered Options

- **Bookmark each Map's folder when it is opened** — rejected. The DM would be asked, by an
  open panel, for a folder they have already chosen once: the Workspace is that folder, or
  holds it.
- **Open the outside Map read-only** — rejected. A Map whose Walls cannot be saved looks
  exactly like one whose Walls can, until the next launch shows the work gone.
- **Copy the Map into the Workspace** — rejected. It silently makes a second copy of the DM's
  file, in a place the app chose, and the two drift.
