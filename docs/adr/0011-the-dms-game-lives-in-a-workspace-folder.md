# The DM's game lives in a Workspace folder

ADR-0007 put the Party in Application Support and rejected the alternative outright:

> **The Party lives next to the campaign folder the DM chose** — rejected: it needs a file
> picker and a persisted security-scoped bookmark, the same machinery that made the Library
> issue `wontfix`.

We are reversing that. The DM picks a **Workspace** folder, and `.mapforge/` inside it holds
the Parties.

## The cost that killed it was never real

The rejection rests on security-scoped bookmarks, and the app does not need them. There is no
`.entitlements` file in the source tree, `project.yml` sets ad-hoc signing with no sandbox
key, and `grep -rn "bookmarkData\|startAccessingSecurityScopedResource"` over the repo returns
nothing. Both stores that write outside the app already say so in their own doc comments —
`FogStore.swift:11`, "Ad-hoc signed with no App Sandbox, so writing next to a user-picked image
needs no security-scoped bookmarks", and `PartyStore.swift:27` in the same words.

So persisting the DM's chosen folder is a string in `UserDefaults`, and reading it back is
`FileManager`. The same is true of the Library issue that this reasoning leaned on, which was
`wontfix` for the same cost. That reasoning was inherited rather than checked, and it was
wrong in both places.

`FogStore` has been writing `<map>.fog.json` next to arbitrary user-picked images since the
first release. Writing `.mapforge/` next to a user-picked *folder* is the same act with the
same permissions.

## What forced the question

Application Support holds one `parties.json` for the machine. That was right when a Party was
the only thing the app stored about a DM, and it stops being right the moment the app stores
anything else — notes, NPCs, handouts, the things "the app is evolving" means. Each of those
arrives with the same question, and Application Support answers it the same unhelpful way:
one copy, for the machine, wherever the DM's actual material happens to be.

A folder answers it better, and it is a folder the DM already has: a directory of map images
with `.fog.json` and `.combat/` beside them, arranged however they arrange it. Naming that
folder makes the Party's home obvious rather than arbitrary, and gives everything added later
somewhere to go without a new decision each time. It also puts the DM's data where the DM
can see it — backed up, synced or committed by whatever they already use, rather than in a
Library folder they will never open.

**A Workspace is not a campaign.** A DM may keep one campaign in it or a dozen, and the app
draws no line between them: the Parties in one Workspace are one list, as they are today. The
DM already separates campaigns with folders, and a second notion of separation inside the app
would be a second thing to keep in step with the first. If per-campaign scoping is ever
wanted, it is a concept added inside a Workspace, not a reason to make the Workspace smaller.

## Consequences

`Library` leaves `CONTEXT.md`. It described a watched folder of Maps that was never built, and
the Workspace now stands on that ground. The watching and the Map list it promised are still
unbuilt — a Workspace in this first version is a folder the DM picks whose only visible effect
is where Parties are stored. That is deliberate: the vocabulary is settled now so the Map list
is an addition rather than a second reversal.

The app gains a launch gate. Until a Workspace is chosen there is nothing to open, so the
Control Window comes up behind a picker sheet. Every UI test must get past it — the same
problem `loadMapFromLaunchArgumentsIfPresent` (`AppState.swift:188-215`) solves for
`NSOpenPanel`, and it takes the same kind of seam.

Maps are untouched. `<map>.fog.json` and `<map>.combat/` stay beside the image wherever it
lives, per ADR-0003 and ADR-0009, and "Open Map…" still opens a file from anywhere on disk. A
Map inside the Workspace and a Map outside it behave identically; the Workspace is where the
DM's *other* material is kept, not a jurisdiction over files. **Reversed by ADR-0026**: under
the App Sandbox only the Workspace's grant reaches a Map's folder, so "Open Map…" now opens
Maps from inside the Workspace and refuses the rest.

## Considered Options

- **Keep Parties in Application Support, add a Workspace for everything else** — rejected: it
  splits the DM's material across two homes and keeps the roster in the one place they cannot
  back up, sync or find.
- **Application Support, keyed by Workspace path** — rejected for the reason ADR-0009 rejected
  it for combat state: it breaks when the DM moves the folder, and it separates the data from
  the thing it is about.
- **A Campaign concept inside the Workspace, scoping Parties to one** — rejected for now. It
  is the shape a DM with four campaigns may eventually want, but it adds a second selection to
  every launch and a second thing to migrate into, to solve a longer Party picker. Additive
  later; not a founding constraint.
- **A single-file document (`.mapforge` bundle) the DM opens** — rejected: the Maps are already
  loose files in a folder the DM manages in Finder, and a document would either swallow them
  or sit beside them pretending to be the whole of it.
- **Turn on the App Sandbox and do it properly with bookmarks** — deferred, not rejected. It is
  a prerequisite for distribution outside ad-hoc signing and it will make this decision cost
  what ADR-0007 thought it cost. It is a separate piece of work, and doing it first would block
  a storage change on a signing change. **Taken up in ADR-0025**: the app is headed for the
  Mac App Store, and the Workspace is now reached through a security-scoped bookmark. The
  decision above stands; its claim that bookmarks are not needed does not.
