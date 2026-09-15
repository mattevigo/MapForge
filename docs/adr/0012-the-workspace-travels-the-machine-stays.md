# The Workspace travels, the machine stays

Now that a Workspace exists (ADR-0011), every piece of persistent state has two possible
homes, and the question will be asked again for every feature that stores anything. The rule:

**`.mapforge/` holds what the game knows. `UserDefaults` holds what the machine knows.**

A DM who copies a Workspace folder to another Mac should get their game, and should not get
the first Mac's hardware.

## Where the line falls

The Parties are the Workspace's — they are most of what a Workspace is for. So is the active
Party pointer, which moves out of `UserDefaults` into the Workspace with the roster it names:
left behind, it would point at a Party another Workspace does not have.

The **Player Display** choice goes into the Workspace too, which is the less obvious half, and
the weaker of the two calls. A DM who keeps one Workspace on a laptop they carry between two
tables gets one remembered screen for both, and will re-pick; a DM with a Workspace per room
gets each remembered correctly. Both are one click. It goes in the Workspace because that is
where everything the app chooses about presenting goes, and splitting the display choice from
the Calibration below it was judged less confusing than splitting it from the rest of the
Workspace — but it is the one item here that could move later without embarrassment.

**Calibration stays on the machine**, keyed by `DisplayIdentity`, exactly where ADR-0003 said
it belongs. It is not a preference. It is a ruler held against a physical screen and a number
read off it — a fact about hardware, and the same fact whichever campaign is open. Stored per
Workspace, two Workspaces could hold contradictory measurements of one television with nothing
able to say which is wrong, and a Workspace copied to a second Mac would carry a measurement
of a screen that is not there. It is not built yet, which is the reason to settle it now:
after DMs have measurements on disk this is a migration, and today it is a sentence.

The **recents list** — which Workspaces this Mac has opened, most recent first — is machine
state by necessity. It is the bootstrap pointer, and it cannot live in the thing it points at.
It is also what lets a Workspace whose folder is gone stay listed as unavailable rather than
silently disappearing, so the DM sees an unplugged drive for what it is.

## Consequences

`DisplayPreferences` keeps its name and loses most of its contents. After migration it holds
the recents list, and later the Calibration table; `activePartyID`, `playerDisplayUUID` and
`playerDisplayName` are deleted from it. The name was already acknowledged as a holdover
(`DisplayPreferences.swift:9-12`) and is now closer to true than it has been since.

`.mapforge/` is flat and generates no `.gitignore`. Everything in it is the DM's own data, so
everything in it is shareable, committable and syncable by construction — which is the point
of drawing the line here rather than inside the folder. `PartyStore` already writes
`.prettyPrinted, .sortedKeys` so a rename is a one-line diff; that now applies to the whole
folder rather than to one file that happened to be thoughtful about it.

Anything added later inherits the question with an answer already given. Notes, NPCs and
handouts are the Workspace's. Window positions, the last-used tool and anything measured off
this Mac's hardware are the machine's.

## Considered Options

- **Everything in the Workspace, including Calibration** — rejected above: it makes one
  physical measurement folder-scoped, which permits two contradictory answers about one
  screen.
- **Everything on the machine except Parties** — rejected: it is the status quo with one
  exception, and it leaves the next feature with the same undecided question.
- **A `local/` subfolder inside `.mapforge/` for machine state, gitignored** — rejected. It
  keeps the Workspace self-contained and was genuinely attractive, but it means the app
  generates Git files for a DM who may not use Git, and it puts machine state one directory
  away from the data it must never be confused with. `UserDefaults` is further away,
  which is the property wanted.
