# The Grid is stored in the fog file, not in a Sidecar

`CONTEXT.md` names `<map>.mapforge.json` — the **Sidecar** — as the home for per-Map metadata, and `FogDocument.swift` recorded a deliberate decision that `<map>.fog.json` is *not* that file: fog was given its own format, and `squaresWide` staying in memory was written down as an accepted consequence. We are reversing that. The Grid (`squaresWide` and whether it was actually declared) goes into `<map>.fog.json`, which becomes version 2.

The reasoning that separated them had a hole. A `Light`'s bright and dim radii are stored in **Grid squares**, not pixels — and so is a Pawn's range. The Grid itself was stored nowhere. So the fog file already persisted a measurement in a unit it did not carry the definition of: a relaunch restored a DM's Lights with radii that meant nothing until the Grid was re-declared by hand, which is why `AppState.litRegions` returns empty without a declared Grid and why the Control Window has an undeclared-Grid warning at all. The two halves of one measurement were already split — not across two files, but across a file and a process lifetime.

Rejoining them in one file makes that measurement whole. A separate Sidecar would instead put the number and its unit in two files that can be copied, moved, or deleted independently of each other.

## Consequences

`FogDocument.version` goes to 2. Version 1 files decode with the Grid absent, which is exactly today's behaviour, so no existing `.fog.json` is invalidated. `FogStore`'s debounced autosave, atomic write and delete-when-empty are reused as they are — though "empty" now has to account for a document that carries a Grid and nothing else, which is a real state: a DM who fits the Grid and stops.

The file's name is now a misnomer. It holds fog *and* the Grid, and `.fog.json` says only the first. Renaming it would strand every file already written beside a Map, so the name stays and this ADR is the explanation.

`map-presenter` issue 03 stays `wontfix`. Rotation and gridless direct physical width — the rest of what the Sidecar was to hold — remain unbuilt, and this decision does not build them. If they are ever wanted, they join this file too, and the Sidecar concept is retired for good rather than half-implemented.

Calibration does **not** belong here. It is per-display, not per-Map, and its home is `DisplayPreferences` keyed by `DisplayIdentity`.

## Considered Options

- **Build `<map>.mapforge.json` as originally specified** — rejected: architecturally tidier and genuinely the documented plan, but it splits one measurement across two files for a boundary that stopped being real the moment Light radii were denominated in Grid squares. It also means a second format, a second store and a second autosave path, for two scalars.
- **Persist the Grid in `UserDefaults`, keyed by Map path** — rejected: it breaks the property that a Map and its authored data travel together, which is the entire reason fog is a sidecar file rather than app state. Moving or renaming a Map would silently orphan its Grid.
- **Leave it in memory and let the DM re-fit each session** — rejected: this is the status quo, and it is the complaint that started the feature.
