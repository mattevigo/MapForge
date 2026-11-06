# Map Fit is a live departure from True Scale, chosen by the DM

ADR-0001 calls True Scale MapForge's "defining requirement": a Map rendered at its exact
physical dimensions on the Player Display, one inch of map to one inch of glass. Map Fit draws
the same Map with no regard for inches at all. It stretches the whole image over the whole
Player Display, edge to edge, with no letterbox and no crop. The Map's declared size and its
Grid are ignored, and a Map whose shape differs from the screen's comes out distorted. That
reads like a contradiction of 0001, so this records why it is not one.

The DM asked for it (the Map Fit spec, 2026-11-06). Sometimes the table needs the whole Map
more than it needs true inches: the overview before the party goes in, a world map, a room
the miniatures are not standing in. At True Scale most Maps exceed the screen, and the only
way to show all of one is to pan across it.

## What makes it a departure and not a mode

- **The DM switches it on, live.** It is a toggle in the Live Toolbar beside the Viewport
  toggle, and nothing switches it on for them.
- **It is never saved.** Not per Map, not per display, not across launches. Every launch
  starts at True Scale, and so does every new Player Display: unplugging the screen switches
  Map Fit off (`MapFitToggle`).
- **It changes nothing it would have to restore.** The Grid stays declared, the Map's size
  stays declared, and the Viewport's origin is untouched. Turning Map Fit off returns the
  table to True Scale exactly where it was.
- **Everything placed on the Map stays in Map space.** Pawns, Lights, Fog and Measurements
  follow the stretched frame, and a Measurement still reads its true distance in squares. The
  distortion is the artwork's, never the game's.

## Why 0001 stands

0001 is about what MapForge must be *able* to do, and why that ruled out the web and Electron:
only native APIs know a display's physical size. Map Fit takes nothing away from that. True
Scale is still the default, still the state every launch returns to, and still the only way
the app ever draws a Map unless the DM has asked otherwise, this minute. Map Fit does not even
need the physical size that 0001 chose a platform to get, which is why it still draws on a
screen that reports none (`ScaleMath.playerFrame`).

What changes is that True Scale is no longer the *only* way a Map reaches the table. The DM
can trade it away for the whole Map, knowingly, for as long as they hold the switch.

## Consequences

- `ScaleMath.playerFrame` and `playerViewport` answer for both: the True Scale frame and
  Viewport, or the whole screen and the whole Map. The Live View's green rectangle covers the
  whole Map while fitted, and the Viewport toggle is unavailable, since there is nothing to pan.
- Everything drawn in Map space has to scale x and y separately (`PlayerPlacement`). Anything
  that took a single scale from the frame's width, such as a Light's falloff radius or a
  perpendicular offset, is wrong under Map Fit's stretch even though it is right at True Scale.
- Pawn tokens stay sized in Grid squares measured across the frame's width. Under a
  non-uniform stretch they are not stretched to match the artwork. Ticket 01 of the Map Fit
  spec accepted this.

## Considered Options

- **Fit without distortion (letterbox to the Map's aspect ratio)**: rejected by the DM. The
  request was the whole Map on the whole screen, and bars waste the screen it is meant to fill.
- **Fit by cropping (fill and cut the overflow)**: rejected. It hides part of the Map, which is
  the problem Map Fit exists to solve.
- **A per-Map or remembered setting**: rejected. A remembered fit would bring a Map back
  distorted in a later session without anyone choosing it, and True Scale would stop being
  what the table can rely on seeing.
