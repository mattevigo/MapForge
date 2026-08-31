# 03 — Sidecar metadata and Grid entry

Status: ready-for-agent
Blocked by: 02

Define the Sidecar format `<map>.mapforge.json` (Codable): grid squares-wide OR direct physical width (gridless fallback), rotation (0/90/180/270). Read on Map load, write on change. Control Window UI: numeric squares-wide field (1 square = 1 inch), toggleable grid overlay drawn over the map to verify alignment, and a gridless mode taking physical width directly.

Acceptance: setting squares-wide writes the Sidecar; relaunch reads it back; overlay lines up with a known VTT map's printed grid.

## Comments

- 2026-08-29: part of grid declaration lands early as **Grid Fit** (issue 08) — drag a square over one artwork grid square in the Control Window preview to derive squares-wide, in-memory only. This issue should persist Grid Fit's derived value (pixels-per-square or squares-wide) in the Sidecar alongside the manually entered path.
