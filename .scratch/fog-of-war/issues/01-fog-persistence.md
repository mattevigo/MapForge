# 01 — Fog persistence file

Status: ready-for-human

Per-Map fog data persists to `<map>.fog.json` beside the image: the Walls, Lights and Pawns the DM authored. This is the first user-authored data MapForge has ever saved — `DisplayPreferences` (two `UserDefaults` strings) is the only persistence that exists today — so it lands first and everything else writes through it.

Shape:

- A `Codable` document holding `walls`, `lights` and `pawns`, plus a schema `version` integer so a later format change has somewhere to branch. Implicit boundary Walls are derived at load, never stored.
- Coordinates are **image pixels** for positions and Wall endpoints; radii are **Grid squares**. Both are stated in the file so a reader is never guessing at units.
- Loaded when a Map is opened (`AppState.openMap()` and the `--test-map` launch path both set `mapURL`), written on change with a short debounce — Wall drawing produces a burst of edits and must not produce a burst of writes.
- A missing file is the normal case, not an error: it means a Map with no fog yet. A malformed file must not take the app down or silently discard the DM's work — surface it and leave the file alone.
- No file is written for a Map that has no Walls, Lights or Pawns; MapForge must not litter the user's map folder.

Scope:

- The app is ad-hoc signed with no App Sandbox, so writing beside a user-picked image needs no security-scoped bookmarks. Revisit if sandboxing is ever turned on.
- Not the Sidecar. `CONTEXT.md` names `<map>.mapforge.json` as the home for per-Map metadata, but its issue (`map-presenter/03`) is `wontfix`; a fog-specific file was chosen deliberately. `squaresWide` therefore stays in-memory only, and Light radii in squares have no physical meaning until the DM re-enters the Grid after a relaunch. Accepted — see the spec's "Known tension".

Acceptance: draw Walls and place a Light on a Map, quit, relaunch, reopen the same Map — the Walls and Light come back exactly where they were. Moving the image and its `.fog.json` to another folder together preserves them. A Map with no fog produces no file.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. Persistence choice was a live decision — reopening `map-presenter/03` (the Sidecar) was recommended and declined in favour of a fog-specific file.

- 2026-09-01 (implemented): `FogDocument`, `FogStore` and `FogAutosave`, wired into `AppState` on both map-open paths. 20 unit tests.

  Two shapes worth knowing. `MapPoint` wraps `CGPoint` purely so the file names its units — `CGPoint` encodes as an anonymous `[x, y]`, which would have left `"from": [100, 200]` for a reader to guess at while Walls are pixels and Light radii are squares. And debouncing lives in `FogAutosave`, apart from `FogStore`, so the store stays a seam tests call with no clock involved.

  Deferred deliberately: implicit boundary Walls are specified here as "derived at load, never stored", but nothing derives them yet because nothing consumes Walls until issue 05. The document is the right place for that derivation when it lands.

  Not verified: the `MapForgeUITests` target hangs in this environment — on `develop` as well as on this branch, so it is pre-existing and unrelated. Needs a human run on a real desktop session.
