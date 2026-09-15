# 01 — The Workspace and its Manifest

Status: ready-for-agent

The value, the store and the on-disk folder, alone. No UI, no preferences changes, no
migration. Everything else in this feature depends on this.

## The problem

There is no type for a folder the DM has chosen, because the app has never remembered one.
`PartyStore` owns a fixed directory (`PartyStore.swift:30-36`) and every other path in the app
is derived from `mapURL`.

## Build

**`struct Workspace`** — a value, not a manager. It is a `URL` (the root folder) and nothing
else; the folder name is the display name (`url.lastPathComponent`), per ADR-0011's "no name
to drift". Give it the derived paths as computed properties, so nothing else in the app
concatenates `.mapforge`:

```swift
var supportDirectory: URL   // <root>/.mapforge
var manifestURL: URL        // <root>/.mapforge/workspace.json
var partiesURL: URL         // <root>/.mapforge/parties.json
```

`Equatable` and `Hashable` on the URL, so the recents list in 02 can deduplicate.

**`struct WorkspaceManifest: Codable`** — `version: Int` (`static let current = 1`),
`createdAt: Date`, `createdBy: String` (the app's `CFBundleShortVersionString`).

Follow `PartyBook`'s hand-written coding (`Party.swift:111-121`) with **one deliberate
difference**: `PartyBook` defaults a missing `version` to `current` (`Party.swift:113`), which
makes a version-less file indistinguishable from a v1 one. Here, `version` is a **hard
`decode`** — a Manifest without a version is not a Manifest this app wrote, and guessing is
exactly what the picker must not do.

**Something must actually read `version`.** `PartyBook.version` is stamped on save and never
inspected by anything, which makes it decoration. `WorkspaceStore.open` must branch on it:
`version > current` is a refusal ("made by a newer version of MapForge"), not a silent open.
This is the app's first real use of a version number; if it is written and never read, say so
in a comment rather than leaving the next reader to discover it.

**`final class WorkspaceStore`** — `PartyStore`'s shape exactly: `final class`, no protocol,
`init(fileManager: FileManager = .default)` for the test seam (the house style — `FogStore`,
`PartyStore`, `StatsStore` and `CombatLogStore` are all concrete with default-argument
injection; do not introduce the app's first protocol here).

```swift
enum OpenFailure: Error {
    case notAWorkspace(URL)       // folder exists, no .mapforge/workspace.json
    case unreachable(URL)         // folder is gone or unreadable
    case unreadableManifest(URL, underlying: Error)
    case newerVersion(URL, found: Int)
}

func open(_ url: URL) -> Result<Workspace, OpenFailure>
func adopt(_ url: URL) throws -> Workspace
func isWorkspace(_ url: URL) -> Bool
```

`adopt` creates `.mapforge/` and writes a fresh Manifest. It **must not** touch anything else
in the folder — no Map, no `.fog.json`, no `.combat/`. Adopting a folder that is already a
Workspace returns the existing one rather than overwriting the Manifest, so a DM who re-adopts
does not reset `createdAt`.

Write with `.prettyPrinted, .sortedKeys` and `.atomic`, matching `PartyStore.swift:70-72`.

## Distinguish "not a Workspace" from "not there"

`notAWorkspace` and `unreachable` are separate cases because 03 shows different things for
each: an adoption offer for the first, "the drive is unplugged" for the second. Do not collapse
them into one error — the distinction is the whole reason Q5 has the answer it has.

## Tests

- `adopt` on a temp dir creates `.mapforge/workspace.json`; `open` then succeeds.
- `adopt` twice preserves the original `createdAt`.
- `adopt` leaves sibling files untouched — create a fake `map.png` and `map.fog.json`, adopt,
  assert both unchanged.
- `open` on a plain directory returns `.notAWorkspace`.
- `open` on a nonexistent path returns `.unreachable`.
- `open` on a manifest with `"version": 999` returns `.newerVersion` — this is the test that
  proves the version is read, and it is the point of having one.
- `open` on a manifest with no `version` key throws rather than defaulting, unlike `PartyBook`.
- `open` on malformed JSON returns `.unreadableManifest` and **leaves the bytes on disk**.
