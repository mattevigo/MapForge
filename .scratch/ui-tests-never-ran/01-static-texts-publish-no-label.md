# 01 — Every static text in the Control Window publishes an empty label

Status: needs-triage

`MapForgeUITests` runs now. It had never run before: the app was launching with
no window, because `--test-map /path` passed the path as a *bare* argument and
AppKit reads a bare argument as a document to open. Welding the value on with
`=` fixed that (see the commit "Spell the test launch arguments so the app
actually opens a window"). Twenty-four tests execute in ~160s.

Twelve fail. Eleven of them are blocked by one thing.

## What was observed

With the Wall Editor demonstrably open — `app.buttons["Done"].exists` is true —
every element in `app.windows["control"].staticTexts` reports `label == ""`.
Seven of them, all empty. The window is real, the buttons are addressable and
clickable, and only the text is invisible to the query.

So `app.staticTexts["0 Walls, 0 Lights, 0 Pawns"]` can never match, whatever the
clicks do. Six `FogEditingUITests` assert on that summary; the five
`InitiativeTrackerUITests` are the fixture behind them.

This is not caused by the `live-authoring` branch.
`testClickingPlacesVerticesAndDoubleClickCommitsTheChain` fails identically with
that branch's UI-test edits reverted, against Wall-tracing code the feature
never touched.

## Worth doing, and why

Nobody has ever seen these tests pass, so nothing here is a regression — but
nothing here is trustworthy either. The `fog-of-war` spec records **three**
defects found by hand during that feature that lived in exactly the layer these
tests cover, and that no unit test could reach. The suite is the only automated
thing that reaches it.

## Where to start

Whether SwiftUI `Text` publishes its string as the element's `label` on this
macOS, or only as its `value`. If it is `value`, the fix is a query change. If
`Text` needs an explicit `.accessibilityLabel` or `.accessibilityIdentifier`,
the fix is in the app — and the same question then applies to every label-based
query in the suite, not only the fog summary. The identifier-based queries
(`fog-overlay-switch`, `light-toggle-1`, `pawn-light-toggle`) already work,
which is a hint at the answer and a template for it.

## Resolved since

`ModeButtonsUITests.testScrollZoomChangesThePreview` passes. It was not a defect
in the test: the Live View genuinely had no zoom, and the test had been asserting
one for months without ever running. The `live-authoring` branch built it.

The eleven stale tests are fixed too — they drove the fog editor's tool picker
and "Pan Viewport…", both of which that branch replaced.

## Still open

- `WorkspacePickerUITests.testTheRecentsListNamesTheWorkspaceByItsFolder`, the
  last failure of twenty-eight. Untouched by `live-authoring`, which changes no
  Workspace code at all — visible now only because the suite runs.

## Also noticed, not fixed

`DisplayPreferences.forThisLaunch` creates a `UserDefaults` suite per run and
never removes it: ~1,673 leaked plists in `~/Library/Preferences`, about 9.6 MB.
Harmless, untidy; a `removePersistentDomain(forName:)` in test teardown closes
it.
