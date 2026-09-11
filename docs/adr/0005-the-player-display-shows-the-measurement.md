# A Measurement is shown to the table, number included

`CONTEXT.md` said, until this decision, that a Light Marker was "the only thing besides a
Pawn that the Player Display draws over the Map." That sentence held through fog, Creatures,
Solo Sight and Light Markers, and it encoded something real: the Player Display shows the
*world*, and everything a DM needs in order to run the world stays on the Control Window. A
Measurement breaks it. The shape and its distance readout — "9 m" in a chrome capsule — are
both drawn on the Player Display, and the readout is the first piece of DM instrumentation
the table has ever seen.

It follows ADR-0004's argument rather than contradicting it. Solo Sight was put on the
Player Display because "a DM who can see the answer cannot *show* it, and showing it is the
point." The same holds harder here: a Measurement exists to settle a question the players
are the ones asking — is the dragon in range, does the fireball catch the rogue — and a
measurement only the DM can see answers it for the one person at the table who could already
estimate it.

## The number, specifically

Drawing the *shape* on both screens is uncontroversial; it is a region of the world, in the
same class as a lit region. The number is the part that is instrumentation, and it was the
part most tempting to withhold.

It is shown because a shape without its number moves the argument rather than ending it. A
cone on the screen still invites "is that 9 m or 12?", and the DM answering from the Control
Window is exactly the appeal-to-authority the shape was drawn to avoid. It is also the half
that survives a bad projection: if the Grid is fitted slightly wrong the shape is subtly
wrong everywhere, and the number is the thing that lets somebody at the table notice.

## Consequences

The Player Display now draws three kinds of thing over the Map, and the rule that kept it to
two is gone rather than bent. The replacement rule is narrower and worth stating: the Player
Display may draw what the table is *entitled to know*. A Measurement qualifies because the DM
created it in order to tell them. Hidden Creatures, the fog tint, the DM's own reading of
Visibility do not, and none of them become admissible by this decision.

The readout is fixed-size chrome — `GridFitOverlay`'s `.thinMaterial` capsule pattern, not
`PawnToken`'s map-scaled text. A distance is a fact about the world, not an object in it, and
map-scaled text on a True Scale display is illegible on a large Map and enormous on a small
one.

Because the Measurement is transient and never persisted, the blast radius of getting this
wrong is one right-click. That is the main reason this is acceptable as a first breach: it
cannot be left on the table's screen across sessions the way an authored mistake can.

## Considered Options

- **Shape on both screens, number on the Control Window only** — the conservative version,
  and genuinely close. Players still see the cone's reach; only the digits stay with the DM.
  Rejected because it preserves the letter of the old rule while losing the thing that ends
  the argument, and because the DM reading the number aloud re-introduces the authority the
  shape removed.
- **Both, but only while the DM holds the mouse down** — rejected as a worse version of
  transience: it makes the table's evidence disappear at the moment they want to discuss it,
  and it is a second dismissal mechanism competing with right-click.
- **DM-only, Control Window entirely** — rejected for the reason ADR-0004 rejected the same
  option for Solo Sight: it is a diagnostic for the person who needed it least.
