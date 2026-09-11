# 01 — The Party model and its store

Status: ready-for-agent

The pure, testable core: what a Character and a Party *are*, and where they live on disk. No
views, no drag-and-drop.

## Build

**`Character`.** `id: UUID`, `name: String`, `colorHex: String`, `sightSquares: CGFloat`,
`isBig: Bool`. `Codable, Equatable, Identifiable`. Deliberately *not* stored: `kind` (always
`.player` — see the spec's out-of-scope list) and `isHidden` (a table state, never a
definition). No portrait.

Defaults for a new Character should match what click-to-place already gives a Pawn:
`Pawn.defaultColorHex` and a sight of 6 squares (`PawnToken.swift:117`, `FogOverlay.swift:349`).

**`Party`.** `id: UUID`, `name: String`, `characters: [Character]`. Order is the DM's, so it
is an array and reordering is meaningful later — do not make it a Set or sort it for display.

**`PartyBook`.** The whole roster: `version` plus `parties: [Party]`. Stamp the version on
encode rather than echoing what was read, the way `FogDocument.encode(to:)` does
(`FogDocument.swift:72-120`) — this file will outlive its first shape.

**`PartyStore`.** Load and save the `PartyBook` at
`~/Library/Application Support/MapForge/parties.json`. Model it on `FogStore.swift`, which is
the established pattern here and is only 60 lines: `JSONEncoder` with
`[.prettyPrinted, .sortedKeys]`, written `.atomic`, a missing file is normal and returns an
empty book, and an unreadable file surfaces a failure rather than being silently overwritten.

Unlike `FogStore` this one must create its directory (`FileManager`'s
`.applicationSupportDirectory`, `create: true`). The app is unsandboxed
(`FogStore.swift:11-12`) so there is no bookmark machinery to worry about.

**Active-Party preference.** The active `Party.ID`, remembered across launches. Extend
`DisplayPreferences.swift` or add a sibling of the same shape — a hand-written wrapper over
`UserDefaults`, honouring the `--test-fresh-preferences` throwaway suite it already supports
(`DisplayPreferences.swift:19`). An active ID naming a Party that no longer exists must
resolve to "no active Party", not crash.

## Tests

Unit tests, no UI:

- A `PartyBook` round-trips through the store: write, read, equal.
- A missing file loads as an empty book, not an error.
- An unreadable file reports failure and is **not** overwritten — the `FogStore` guarantee,
  which matters more here because this file is the DM's whole roster.
- Saving creates the Application Support directory when it is absent.
- The active-Party ID survives a store round-trip, and a dangling ID resolves to nil.

## Done when

Parties persist across launches and the model is covered by tests. Nothing yet shows them.
