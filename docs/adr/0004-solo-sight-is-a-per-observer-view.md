# Solo Sight makes one Pawn's sight decide what the table sees

`FogDocument.swift` records that a Pawn's sight and a Pawn's illumination are one number,
and gives the reason: "with no per-observer masks and one shared Player Display, a Pawn
that sees 30 ft and a Pawn that lights 30 ft are indistinguishable." `CONTEXT.md` says the
same in the **Pawn** entry, and the `creatures` spec leans on it again to justify revealing
a Creature by the fog rather than by line of sight. It has been the load-bearing
simplification of the whole fog engine.

Solo Sight distinguishes them. While it is on, the selected Pawn's radius decides not only
what is *lit* but who is *drawn* — a party member around a corner is absent from the Player
Display. That is a per-observer rule, on a shared screen, and it is the first one in the
app.

The invariant is not being deleted. It still holds in normal play, which is where the app
spends nearly all its time, and every structure that depends on it — one `[LitRegion]`
array, one `VisibilityCache`, one shared Player Display — is untouched. What changes is
that "no per-observer masks" becomes "no per-observer masks *by default*". Solo Sight is a
mode the DM enters deliberately, for a question that has no answer without it: what does
this character actually see, with the rest of the party's torches taken out of the picture.

## It is shown to the table, not just to the DM

The obvious safe version is a DM-only diagnostic: the Control Window shows the isolated
view, the Player Display carries on as normal. That was rejected. A DM who can see the
answer cannot *show* it, and showing it is the point — a scout goes ahead, and the table
sees what the scout sees, with the rest of the party's light gone from the screen. Keeping
it off the Player Display would make it a debugging tool for a question players are the
ones asking.

The cost is that Solo Sight is now a presentation mode with a live audience, so its failure
modes are on the big screen. That is why the mode clears itself on a Map switch, on the
isolated Pawn being deleted, and on entering fog editing, and why the isolated Pawn is
always drawn: an isolated view whose subject can vanish leaves a table staring at a black
screen with no way to read what went wrong.

## Tokens follow the light, exactly as Creatures already do

Under Solo Sight a party Pawn is drawn only where the remaining light reaches it. That is
not a new rule — it is the rule Creatures have followed since the `creatures` feature, and
`PlayerVisibility` already implements it. Solo Sight widens its domain rather than adding a
second mechanism: for the duration of the mode, party Pawns are discovered by light like
everything else.

The consequence is worth stating plainly, because it is easy to misread the mode's name.
The Map's own Lights stay lit (a brazier is the room, not another character's influence), so
a party member standing in a lit room *is* visible to the table even if the isolated Pawn is
nowhere near. Solo Sight therefore does not show "what Ilyana sees". It shows what is
visible when the only carried light is Ilyana's. The fog engine has no eyes, and pretending
otherwise would mean real line-of-sight per observer — a different feature, an order of
magnitude larger, and one this decision deliberately does not start.

## Consequences

`PlayerVisibility.showsToPlayers` stops being a pure function of a Pawn and takes the solo
state and the lit regions as well. There remains exactly **one** function answering "does
this show to players" — a second one is how the two screens drift apart, which is the
divergence `PawnToken` exists to prevent.

`VisibilityCache.Inputs` gains the isolated Pawn's ID, so the memoisation that already
answers "did the lighting inputs change" answers this too. One array, one cache; toggling
the mode invalidates it once.

The eye (`isHidden`) keeps its guarantee. "Hidden beats lighting" is the DM's one reliable
way to take something off the table's screen, and Solo Sight neither overrides it nor
mutates it: the mode is purely derived, filtering at render time and writing nothing.
Solo Sight is therefore unavailable *on* a hidden Pawn, rather than silently un-hiding it.

Nothing is persisted. Like the Fog Overlay switch, and unlike the eye, the mode resets on
launch — nobody wants to reopen a Map tomorrow and find the table still looking through one
character's eyes.

The Control Window is unaffected in the way that matters: it keeps its readable tint and
still draws every Pawn, dimming the ones the table has lost. "A DM as blind as the players
cannot run the game" survives intact, and gains a use — the DM can see the party member
standing just outside the isolated Pawn's reach, and knows the table cannot.

## Considered Options

- **A DM-only diagnostic, Player Display untouched** — rejected above: it answers the
  question for the one person who could already work it out, and not for the table.
- **Isolate the light but keep every token drawn** — the smaller change, and it preserves
  the invariant completely: only the fog would shrink. Rejected because a party member
  visible through a wall while their light is off is precisely the influence the mode is
  supposed to remove; the tokens are half the picture.
- **Isolate everything, including the Map's own Lights** — rejected: it answers "what would
  this character see in a world with no fire in it", which is nobody's question. A wall
  sconce is not another player's influence.
- **Mutate `isHidden` on the other Pawns on entry and restore on exit** — rejected: it
  writes to the sidecar to achieve a view effect, fights the `liveEdits` bookkeeping that
  exists to preserve live hide/show decisions, and loses the DM's real intentions outright
  if the app dies mid-mode.
- **Multi-select isolation ("what do the two scouts see between them?")** — deferred, not
  rejected. One `Pawn.ID?` is a strict subset of a set of IDs and upgrades cleanly if a real
  use case appears; paying for the general case now buys nothing today.
- **Real per-observer line of sight** — rejected as out of scope. It needs a `LitRegion` set
  per observer, a rendering path per observer, and an answer to what the shared Player
  Display shows when the party is split. Solo Sight gets most of the value for one extra
  field on a cache key.
