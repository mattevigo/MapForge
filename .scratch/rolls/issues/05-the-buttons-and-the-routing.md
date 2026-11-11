# 05 — The buttons and the routing

Status: ready-for-agent
Blocked by: 02, 03, 04

Four buttons, one presentation, and the rule that picks the Log.

## Live View

`ControlView.pawnLiveRow` (`ControlView.swift:1370-1427`). Two 16 pt icon toggles after the
existing trailing icons. Match the row's idioms exactly:
- `.frame(width: 16)`
- `.help(...)` interpolating the Pawn's label, as `combatRosterToggle` does at `:1452`
- **Omitted for `kind == .treasure`** via `@ViewBuilder`, as `combatRosterToggle` is — the
  comment there notes conditional visibility costs width, not height

These are actions, not state, so they are `Button`s — the row's existing controls are all
`Toggle`s because they show state, and the comment at `:1399-1401` is explicit that the
symbol reflects state rather than the action. A Roll button has no state to reflect.

Pick two distinct SF Symbols. `shield.lefthalf.filled` is taken by the combat roster toggle
and `dice.fill` by reroll; choose something unambiguous against both and note the choice in
`LiveRowSymbolTests`, which already pins this row's symbols.

## Combat View

`CombatPanel.row(_:id:)` (`CombatPanel.swift:269-321`). Two buttons in the order row, styled
as `bench` is: `.font(.system(size: 9))`, `.buttonStyle(.borderless)`. No Treasure handling —
it never reaches the Order.

Their identifiers will be swallowed by `.accessibilityElement(children: .combine)` at `:314`.
That is accepted and must not be "fixed" — `.contain` is what the comment at `:315-317` says
breaks row-counting UI tests.

## Width

`livePanelWidth` 320 → 364. Separately, `minimumMapColumnWidth` 420 → 584 per
`docs/adr/0018-the-control-window-has-a-thousand-point-floor.md`, putting the derived
`minimumWindowWidth` at exactly 1000. Do not type 1000 anywhere — the derivation at
`ControlView.swift:1745-1746` stays, and its doc comment explains why a hand-picked total is
the bug this guards against. Update that comment to reflect the new inputs.

## Routing — the part to get right

One sheet, and **the call site does not branch**. Record calls both recorders
unconditionally:

- the Combat Log recorder (issue 02) writes only when `appState.encounter != nil`
- the Session Log recorder (issue 03) drops itself when `session.isRecordingSuspended`

This is precisely `commitPawnMove` (`AppState+Combat.swift:229-241`), and ADR-0014's "exactly
one recorder is live at any instant" is what makes it safe. Do not add an `if` at the button.

A Roll may be made for a Pawn that is **not** a Combatant while a fight runs — the NPC in the
corner — which is why the Live View's buttons stay live during an Encounter rather than being
disabled the way `combatRosterToggle` is.

Presentation follows `EditTarget`: an `Identifiable` enum case on `ControlView`, a `@State`
holding it, `.sheet(item:)` at `ControlView.swift:250`.

## Tests

`StatEditingTests` / `EncounterAppStateTests` — a Roll during a fight produces exactly one
`Change` in the open Turn and no Session line; outside a fight, exactly one Session line and
no Turn. A Roll for a non-Combatant during a fight still records.

`SetupToolbarWidthTests` — must still pass unchanged; it is the guard that the widened panel
and the window minimum agree.

`LiveRowSymbolTests` — the new symbols, and that Treasure rows omit them.

## Done when

Pressing either button in either view, inside or outside a fight, writes one line to exactly
one Log, and the Log View shows it.
