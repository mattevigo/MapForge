# The scrolling log

Status: done
Blocked by: 02, 03, 04

The list itself: issue 02's rows, rendered by issue 03, in the pane issue 04 cleared.

## Layout

Follow the house pattern — there is no `List` and no `Table` anywhere in this app.
`ScrollView(.vertical)` → `VStack(alignment: .leading, spacing: N)` → `ForEach`, each row a
hand-built `HStack`. `CombatPanel.swift:157-167` (the Order) is the closest template. Panel chrome
matches `scenePanel` and `CombatPanel`: `.background(Color(nsColor: .textBackgroundColor), in:
RoundedRectangle(cornerRadius: 6))` with a `separatorColor` stroke.

Indentation carries the grouping: Round heading, Turns beneath, Changes beneath those, Corrections
beneath their Turn and visibly marked. Round headings and map separators follow the existing
in-list section pattern — `Divider().padding(.vertical, 4)` plus a small semibold secondary label
(`CombatPanel.swift:182-186`).

Marked rows — unreadable Lines, unresolvable Encounters, orphan Corrections — must read as
*problems*, not as content. Secondary colour and a symbol, not silence.

## Scrolling

Opens at the **bottom**. Follows the bottom as Lines arrive, **until the DM scrolls up** — then
stops following until they scroll back down. Chat-app behaviour, and the reason for it is
concrete: a DM scrolled up reading Round 2 must not be yanked away by a pawn drag, and a DM at the
bottom must always see the newest.

`ScrollViewReader` plus a scroll-position observer. If following-release proves unreasonably
fiddly in SwiftUI on macOS, scroll-to-bottom-on-open-only is the agreed fallback — say so rather
than shipping a half-working follow.

## Live updates

Re-read the file on **every append**. The `Session` holds only `startedAt` and
`isRecordingSuspended` — it does not keep its Lines in memory the way `Encounter` does — so the
file is the truth. The app knows when it writes; re-read there.

This matters because the Comment Bar stays visible beneath the Log View: a comment typed while
reading must appear. Appends are rare and the files are kilobytes. Do **not** add a cache; ADR-0016
records that as a later optimisation that changes no design.

## A live Encounter

Mark it in progress in its group header, with the current Round and Combatant visible at the
bottom. Its Turns arrive beneath as they end. Do not also explain that Comments are paused — the
Comment Bar directly below already says so in its own words, and saying it twice in two
vocabularies is worse than saying it once.

## Done when

- A Session with a finished fight and a live one renders both, the live one marked.
- A comment typed while the Log is open appears without reopening it.
- Scrolled up, a new Line does not move the view; scrolled to the bottom, it does.
- UI test covers open → scroll up → append → assert position held.
