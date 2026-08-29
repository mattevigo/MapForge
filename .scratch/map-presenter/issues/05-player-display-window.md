# 05 — Player Display window lifecycle

Status: ready-for-agent
Blocked by: 04

Borderless fullscreen window (no menu bar/dock, black background) on the external display showing only the Map at True Scale. Exactly one external display → auto-present there; 2+ → picker. Observe display connect/disconnect: on unplug keep all state in the app model and show a "no player display" badge in the Control Window; on replug restore the window with identical Map/Viewport/rotation/Blackout state.

Acceptance: plug in HDMI → map appears fullscreen; yank the cable and reconnect → same view returns; Mac's own display never shows the player window.
