# 01 — A Light has a name

Status: done

The model and the file format, alone, with the compatibility test that guards them. 02 and 03
depend on this.

## The problem

`Light` (`FogDocument.swift:128-144`) has `id`, `at`, `brightSquares`, `dimSquares` and
`isOn`. No name, no label, no title.

Its `Codable` conformance is **fully synthesised** — no `CodingKeys`, no `init(from:)`, no
`encode(to:)`. `Wall` is the same; only `MapPoint`, `FogDocument` and `Pawn` are hand-written.
That matters more than it looks, and `Pawn` already paid for the lesson
(`FogDocument.swift:222-231`):

> A property default is not enough: Swift's synthesised `decode` requires every key unless the
> property is optional, so adding these flags to the synthesised conformance made every
> `.fog.json` written before Creatures existed fail to load outright … Caught by a test that
> decodes a file with the keys absent; **keep that test**.

There is currently **no equivalent test for `Light`**. The closest,
`FogDocumentTests.testAVersionOneFileDecodesWithNoGrid` (`:76-91`), decodes raw JSON with
`"lights": []` — an empty array, so it would not catch a `Light` decode break at all. The
existing round-trip tests go `JSONEncoder` → `JSONDecoder` on a freshly-built document, which
also cannot catch it.

## Build

**`var name: String?` on `Light`.** Optional, so the synthesised decoder tolerates its absence
in every `.fog.json` ever written. Do **not** use a defaulted non-optional `String` — that
breaks every existing file, per the comment above.

**Add it to the memberwise `init`** (`FogDocument.swift:136-144`) with a `nil` default, so the
many test fixtures constructing `Light(at:brightSquares:)` keep compiling —
`VisibilityTests`, `VisibilityCacheTests`, `WallChainTests`, `WallSnapTests`, `SoloSightTests`,
`CreatureTests`, `FogOverlayAcceptanceTests`, `AppStateFogTests` and `FogEditsTests` all build
Lights.

**If a non-optional `String` is wanted later**, it means hand-writing both `init(from:)` with
`decodeIfPresent(...) ?? ""` and `encode(to:)`, mirroring `Pawn` (`:232-247`, `:256-268`). Not
now: the optional is correct here because "unnamed" is a real state at the model level even
though 02 makes it rare in practice.

**No `FogDocument.version` bump.** Version 2 (`:current`) is about the Grid
(`docs/adr/0003-grid-in-the-fog-file.md`). An additive optional field needs no version gate,
and bumping would imply old files need migrating when they do not.

**Encode with `encodeIfPresent`** if the encoder is hand-written; if left synthesised, confirm
what Swift emits for a `nil` optional and whether a `"name": null` in every entry is
acceptable. The precedent is `Pawn.encode(to:)`'s `characterID` (`:265-268`), which goes out
of its way to avoid exactly that.

## Tests

In `MapForgeTests/FogDocumentTests.swift`:

- **The missing-key test, which is the point of this issue.** Decode a raw JSON `FogDocument`
  containing a real `Light` object with no `name` key, and assert it decodes with `name == nil`.
  Model it on `testAVersionOneFileDecodesWithNoGrid` (`:76-91`) but with an actual Light in the
  array. Keep this test — write the same instruction in a comment that `Pawn`'s carries.
- Extend `testRoundTripPreservesLightsAndPawns` (`:34-42`) to carry a named Light.
- A named Light and an unnamed one round-trip distinguishably.
- A file written with a name loads in a build that has the field; assert the encoder does not
  emit the key for an unnamed Light if `encodeIfPresent` is used.

`FogStoreTests.testFogSurvivesARelaunch` (`:21`) should also exercise a named Light, since it is
the only test that goes through the real file on disk.

## Done when

`Light` has an optional name, every `.fog.json` written before today still loads, and a test
would fail loudly if that stopped being true.

## Comments

**Built.** `var name: String?` on `Light`, optional exactly as the issue required.

**The missing-key test was verified to bite.** Making `name` a defaulted non-optional `String`
— the mistake — fails `testALightWithNoNameKeyStillDecodes` immediately, which is the
`FogDocument.swift:222-231` break reproduced on purpose before being ruled out. A second test
covers a **Pawn's nested Light**, which the issue did not ask for: a break there would take
every Pawn with it rather than only the Map's own Lights.

**`encode(to:)` is hand-written, `init(from:)` is not.** `encodeIfPresent` is the whole reason
— an unnamed Light writes no `name` key rather than `"name": null` in every entry, following
`Pawn.encode(to:)`'s `characterID`. Decoding stays synthesised because an optional key is
precisely what it handles correctly, and a hand-written decoder would add a second place for
the halves to disagree.

**`Light.nextName(after:)` landed here rather than in issue 02**, beside the type it names,
mirroring `Pawn.nextLabel(after:)`. It scans for the lowest unused number rather than counting,
which is the after-delete defect this feature exists to fix.

No version bump, as the issue specified.

- 2026-09-14: closed on a green suite. Not checked by hand at the table.
