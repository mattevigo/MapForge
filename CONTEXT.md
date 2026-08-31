# MapForge

A macOS tool for a DM to present DnD battle maps on an HDMI-attached screen at true physical scale, controlled from a separate window on the Mac's own display.

## Language

**Map**:
A raster image (PNG/JPEG/WebP) with known physical dimensions, shown to players. Physical size derives from its Grid, or from a directly entered real-world size for gridless maps.
_Avoid_: image, battle map, scene

**Grid**:
The square lattice a Map is drawn on. One square is 1 inch physical (the DnD convention for 5 ft). Declaring a Map's size in squares pins its physical dimensions.
_Avoid_: mesh, tiles

**True Scale**:
Rendering a Map so its physical dimensions on the Player Display match its declared real-world dimensions exactly (1 inch of map = 1 inch of screen).
_Avoid_: 1:1, actual size, life size

**Player Display**:
The external (HDMI) screen showing only the Map, fullscreen, with no controls. Auto-selected when exactly one external display is connected.
_Avoid_: TV, second screen, presentation screen

**Control Window**:
The DM-facing window on the Mac's own display: map selection, viewport control, blackout, rotation.
_Avoid_: dashboard, admin window, DM screen

**Library**:
A user-chosen watched folder of Maps. Per-Map settings persist in sidecar metadata so a Map is configured once.
_Avoid_: collection, catalog

**Grid Fit**:
Declaring a Map's Grid by dragging a square over a single grid square of the artwork in the Control Window; the Map's size in squares derives from it. Adjusts the Map's declared size, not the display — that is Calibration.
_Avoid_: calibration, grid detection, auto-grid

**Calibration**:
The per-display correction factor for True Scale. EDID physical size is the default; a measured ruler check overrides it, saved per display.
_Avoid_: DPI setting, scaling

**Viewport**:
The region of a Map currently visible on the Player Display. At True Scale most Maps exceed the screen, so the DM pans the Viewport from the Control Window.
_Avoid_: camera, crop, window

**Sidecar**:
The per-Map metadata file (`<map>.mapforge.json`) stored next to the image, holding its Grid, rotation, and scale settings.
_Avoid_: config file, manifest

**Blackout**:
Instantly replacing the Player Display's content with a blank screen, hiding the Map from players.
_Avoid_: curtain, screen off
