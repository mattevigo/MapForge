# 03 — The picker sheet, and getting the tests past it

Status: done

Depends on 02. The launch gate, adoption, switching, and the UI-test seam that every existing
UI test now needs.

## The problem

`MapForgeApp` is fifteen lines: one `Window` scene showing `ControlView`
(`MapForgeApp.swift:6-13`). Closing it terminates the app (`AppState.swift:169-182`). There is
no second scene and there should not be one — the picker is a **sheet over the Control
Window**, not a launch window, because the same sheet must also serve mid-session switching
(ADR-0012's Workspace is switchable) and a second scene has nowhere to go for that.

## Build

**`WorkspacePickerView`**, presented as a sheet from `ControlView` whenever
`appState.workspace == nil`, and on demand from a "Switch Workspace…" command.

Contents: the recents list, and a "Choose Workspace…" button. Each recent row shows the folder
name over its path in grey. A row whose folder is `.unreachable` stays listed, **dimmed and
non-selectable**, with "not available" — this is the whole answer to "the external drive is
unplugged": the DM sees their campaign is fine and the drive is not. Do not remove it.

**One gesture.** "Choose Workspace…" is an `NSOpenPanel` with `canChooseDirectories = true`,
`canChooseFiles = false`. On return:

- `isWorkspace` → open it.
- `.notAWorkspace` → a confirm: "*Eroi* isn't a MapForge workspace yet. MapForge will create a
  `.mapforge` folder inside it for your parties and settings. Your maps won't be changed." →
  Cancel / Set Up. On Set Up, `adopt` then open.
- `.newerVersion` → refuse with the version message from 01. Do not offer to adopt over it.
- `.unreadableManifest` → refuse; the bytes stay on disk. Adoption would overwrite a file the
  app could not read, which is the rule `PartyStore` and `FogStore` both hold.

**Switching** closes the Player Display first, then ends any live Encounter, then opens the new
Workspace. If an Encounter is running, confirm first — naming the Map and saying the log is
kept:

> An encounter is running on **Goblin Ambush**. Switching workspaces will end it.
> The combat log is kept.

Nothing is lost by stopping (ADR-0008 writes the log per Turn, ADR-0009 keeps it beside the
Map), but the Order and the Round in progress are the DM's to rebuild, which is what the
confirm is protecting.

**The sheet must not be dismissible when no Workspace is open.** There is nothing behind it.

## The test seam — this blocks every existing UI test

Until now every UI test launched straight into `ControlView`. They now all hit a modal sheet.
`loadMapFromLaunchArgumentsIfPresent` (`AppState.swift:188-215`) exists because "NSOpenPanel
can't be driven from XCUITest" (`AppState.swift:186`); this is the same problem one level up,
and takes the same shape. Two arguments, because the tests split in two:

- **`--test-workspace <path>`** — open exactly this Workspace, adopting it first if needed.
  For tests that care: migration, switching, the unavailable state.
- **`--test-fresh-preferences`** — already exists (`DisplayPreferences.swift:34-39`) and
  already swaps in a throwaway `UserDefaults` suite. Extend it to also adopt and open a
  throwaway Workspace in a temp directory, so the many tests that do not care about Workspaces
  simply never see the sheet.

Neither may touch the real recents list. `forThisLaunch`'s existing comment explains why this
matters — the first version of that flag existed because a developer's remembered Player
Display leaked into the suite and made every control "not hittable". A remembered *Workspace*
leaking in would be the same class of failure with the DM's real roster attached.

Audit every test in `MapForgeUITests/` for the launch arguments it passes and add the flag.

## Tests

- UI: launching with no recents shows the sheet; the Control Window is unusable behind it.
- UI: `--test-workspace` opens straight into the Control Window, no sheet.
- UI: choosing a plain folder shows the adoption confirm; Cancel leaves no `.mapforge/`.
- UI: switching Workspaces mid-Encounter shows the confirm; Cancel keeps the Encounter running.
- Unit: a recent whose folder was deleted resolves `.unreachable` and stays in the list.
