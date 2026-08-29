# 09 — Viewport panning

Status: ready-for-agent
Blocked by: 01

Pan the Viewport from the Control Window: a dedicated Viewport mode shows the full map in the preview with a rectangle sized to exactly what the Player Display shows at True Scale; the DM drags it to choose the visible region. Outside the mode, the preview mirrors the Player Display — the exact portion players see, filling the preview. Pulls the pan half of issue 06 forward; rotation stays in 06.

Behavior:

- The Viewport's size in map inches is derived from the Player Display's physical metrics — never resizable. Resizing would zoom and break True Scale; an explicit off-scale presentation state, if ever wanted, is a separate feature.
- Mode availability: only with a Player Display connected and a Map that overflows it in at least one axis. The overflowing axis pans; an axis that fits stays centered.
- Dragging the rectangle pans the Player Display live. Done/Enter keeps the position; Cancel/Esc reverts to the position from before the mode.
- The rectangle is clamped to the Map's bounds — players never see past the map edge on a pannable axis.
- Initial position: centered on map load (today's behavior). In-memory only; the origin joins Sidecar/session-restore later (issues 03/07).
- With no Player Display connected, the preview falls back to the full map.
- Viewport mode and Grid Fit mode (issue 08) are mutually exclusive; both use the preview.

Acceptance: dragging the rectangle moves the map on the Player Display live and 1 map inch stays 1 physical inch throughout; exiting the mode, the preview matches what the Player Display shows — including black letterbox, never adjacent map content the players can't see; the rectangle can never leave the map bounds; with a map smaller than the Player Display the mode is unavailable and the map stays centered.

## Comments

- 2026-08-29 (implementation review): two-axis review applied. Fixed: the mirror aspect-fit the Viewport but drew the full image, leaking adjacent map into the preview whenever its aspect differed from the Player Display's — now masked to the mirrored region with black letterbox; disconnecting the Player Display mid-pan stranded the mode — now exits to normal. Known minor gaps, accepted: a display with unequal horizontal/vertical ppi renders slightly distorted on the glass but not in the mirror (region shown still matches); the squares-wide field stays editable during Viewport mode (a change just re-clamps the origin).
- 2026-08-29 (grilling session): designed in-session. Decisions: pan-only (resize = zoom = breaks True Scale, rejected); preview mirrors the Player Display outside the mode (trade-off accepted: whole-map overview only inside the mode); live panning while dragging (Blackout, issue 07, is the tool for hiding transitions); centered initial position, in-memory.
