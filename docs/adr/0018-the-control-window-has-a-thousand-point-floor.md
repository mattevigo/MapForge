# The Control Window has a thousand-point floor

The Control Window's minimum width was 792 pt: `minimumMapColumnWidth` 420, plus a 320 pt
live panel, plus 12 pt of seam and 40 pt of padding. It is now 1000 pt, and
`minimumMapColumnWidth` rises to 584 to make that sum.

This is not a consequence of any feature. It was noticed while widening the live panel for
the Roll buttons and is recorded separately, because a future reader finding 584 should not
be told that a saving-throw button needed it.

## 792 pt described the layout, not the job

The derivation is sound and ADR-era-correct: `minimumWindowWidth` is built from what the Map
column needs plus the panel beside it, and `SetupToolbarWidthTests` pins the two together so
they cannot drift. That machinery is kept exactly as it is.

What was wrong is the input. `minimumMapColumnWidth = 420` is the width at which the Live
Toolbar's labels stop wrapping — a floor derived from *one row not breaking*, which is the
narrowest possible reading of what the Map column is for. The Map column also holds the Map.
A 420 pt Map column with a 1000 pt Map in it is a window that satisfies its own test and
cannot be run from.

The panel widening made this visible rather than causing it: 320 → 364 pt moves the derived
minimum to 836 pt, still under a thousand, and still a window nobody wants to be in.

## The floor is a claim about the table

1000 pt is not derived from a control. It is the width below which the Control Window stops
being usable for the thing it exists for — reading a Map, a live panel and a toolbar at once,
on the Mac's own display, while a session runs. That makes it a judgement, which is why it is
in an ADR rather than in a comment.

`minimumMapColumnWidth = 584` is the number that makes the sum land there with a 364 pt panel
(584 + 364 + 12 + 40 = 1000). The Map column keeps being the term that absorbs the change,
because it is the term that was under-specified.

## Consequences

`SetupToolbarWidthTests.testTheWindowMinimumLeavesTheMapColumnWideEnoughForItsToolbars`
keeps passing by construction — the column grew. The toolbar-fitting tests measure rows at a
column width that is now larger, so they pass with more headroom, not less. Nothing in the
derivation changes; one input does.

The cost is real and accepted: on a small laptop display the Control Window now claims more
room, and a DM who liked it narrow cannot have it. That is the point — the narrow window was
not a size anyone chose, it was a number left over from a row-fitting test.

Should the panel widen again, the floor does not automatically follow. 1000 is a decision
about the window, not a formula; a later panel change spends the Map column's headroom until
584 is reached and then asks this question again.

## Considered Options

- **Leave it at 792, or let it drift to 836** — rejected: it satisfies a test about toolbar
  labels while describing no window a DM would work in.
- **Give the extra width to the live panel** (528 pt rather than 364) — rejected: the two new
  buttons need 44 pt, not 208, and a live panel that wide steals from the Map for nothing.
- **Type `minimumWindowWidth = 1000` directly** — rejected: a hand-picked total is exactly
  what let the panel and the toolbars disagree about how much room there was. The sum stays
  derived; the judgement goes into the term it is about.
