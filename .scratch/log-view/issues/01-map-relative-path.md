# `SessionLine.map` becomes a Workspace-relative path

Status: done

Every `SessionLine` carries `map: String?`, today a `lastPathComponent` computed at
`AppState+Session.swift:16`. A bare file name cannot identify a Map — two `dungeon.png` in
different folders are indistinguishable — which makes resolving an Encounter's Combat Log
ambiguous, and a wrong answer looks exactly like a right one.

Make it a path relative to the Workspace root. Relative, not absolute: ADR-0012 keeps the
Workspace portable and an absolute path dies the moment it is opened on another Mac.

## Scope

- Compute the Map's path relative to `workspace.root` at the point `map` is set.
- A Map outside the Workspace, if that is reachable, keeps its bare file name — it has no
  relative path to give.
- `logFile` stays a bare file name. It is already unambiguous *given* an unambiguous Map, and the
  combat directory is derived from the Map path exactly as it is today
  (`StatsStore.combatDirectory(forMapAt:)`).

## No migration

Deliberate, per ADR-0016. The Session Log shipped 2026-09-16, no `.jsonl` written by it exists on
disk, and the Log View reads only the current Session. A pre-change Line reads as unresolvable.
Do **not** add a "does it contain a separator" fallback — it was considered and declined, because
the compatibility it buys is compatibility with nothing.

## Done when

- A Session Line written with a Map in a subfolder carries the subfolder in `map`.
- A Session Line written with no Map still carries `null`.
- Round-trip tests updated; `SessionLogTests` and `AppStateSessionTests` green.
