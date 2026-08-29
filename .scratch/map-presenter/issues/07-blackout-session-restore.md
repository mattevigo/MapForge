# 07 — Blackout and session restore

Status: ready-for-agent
Blocked by: 06

Blackout toggle in the Control Window: instantly replaces Player Display content with plain black (map switching stays live underneath — un-blackout reveals current state). Persist session state (Map path, Viewport, rotation, Blackout) on change; on relaunch restore it with Blackout engaged regardless of how the app quit.

Acceptance: toggle hides/reveals instantly; force-quit and relaunch restores the same Map/Viewport blacked out.
