# 04 — True Scale rendering and Calibration

Status: ready-for-agent
Blocked by: 03

Compute pixels-per-inch of a display from `CGDisplayScreenSize` (EDID mm) and its pixel resolution; render the Map so 1 map-inch = 1 physical inch on that display. Calibration flow: show a bar of nominal length (e.g. 20 cm) on the target display; user measures with a ruler and enters the actual length in centimeters; store the correction factor in app preferences keyed by display identity (prefer `NSScreen` UUID / vendor+model+serial over transient display ID).

Acceptance: on a calibrated display, a 1-inch grid square measures 2.54 cm with a physical ruler.
