# Issue tracker: Trello

Issues and specs for this repo live on the Trello board **MapForge Development**: https://trello.com/b/73ALJwqf/mapforge-development

Use the `trello` MCP server (`mcp__trello__*` tools). If those tools are missing, the server isn't connected in this session: say so and stop. Don't fall back to writing issue files in `.scratch/`.

`.scratch/` is the archive of everything tracked before 2026-10-07. Read it for history, and don't add to it. Its `Status:` lines are unreliable: many say `ready-for-*` for work that has long since merged.

## GitHub Issues

GitHub Issues is the public front door: outsiders can't open the Trello board, so they report bugs and ideas there, using the templates in `.github/ISSUE_TEMPLATE/`. The Trello board is still the tracker, and triage still happens on it.

- When a GitHub issue is worth doing, make a card for it in **Needs triage**, with the issue's URL in the description. Then give the GitHub issue a link to the card, or a reply saying it's been picked up. The board is private, so the reporter can't open the link: a reply tells them more.
- When it isn't worth doing, reply on the GitHub issue with the reason and close it. No card is needed.
- `CONTRIBUTING.md` and the issue templates never link to the board.

## The board

The list a card sits in *is* its state. There are no state labels to keep in sync.

| List | Holds | ARI |
|---|---|---|
| Specs | One card per feature: its spec | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea252b1d4a1b581bf36` |
| Needs triage | New, unevaluated tickets | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea38d8e094999407935` |
| Needs info | Waiting on more information | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea3de3919874c018dd8` |
| Ready for agent | Fully specified, an agent can take it | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea4862bae3554e3cc16` |
| Ready for human | Needs a person: judgement, hardware, a check at the table | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea4ca6d3be1b83bdc83` |
| In progress | Claimed, or built on a branch that hasn't merged | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea4ff4d30900af3afb7` |
| Done | Merged into `develop` (and checked, where the ticket asked for a check) | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea50e77f59654a62be7` |
| Won't fix | Decided against; the reason is in a comment | `ari:cloud:trello::list/workspace/60d3afb18e9c90173f526fb8/6ac64ea517bf1ca606e0c524` |

Board ARI: `ari:cloud:trello::board/workspace/60d3afb18e9c90173f526fb8/6ac6491b93c3baee07cc5450`.

## Conventions

- **Every card name starts with its feature slug in brackets:** `[support-bar] 01 — The bar reserves its height`. The slug is the kebab-case name that used to be a `.scratch/` folder. It groups a feature's cards and is what you search on. The Trello connector can't create labels, so the slug goes in the name instead.
- **A spec is a card in Specs**, named `[<slug>] Spec — <title>`. The card description is the spec. A checklist named **Tickets** on the spec card holds one item per ticket, each item being that ticket card's URL.
- **A ticket is a card**, named `[<slug>] NN — <title>`, numbered from `01` within its feature. Its description is the ticket body. One card per ticket; never one combined card.
- **Descriptions are Markdown**, at most 16,384 characters. Leave out the old `Status:` line and an empty `## Comments` heading: the list is the status, and comments are Trello comments.
- **Discussion goes in card comments** (`trelloWriteCard` `add_comment`), not appended to the description.
- **Reference repo files by repo-relative path** (`ControlView.swift:141`, `docs/adr/0011-…`). Relative Markdown links don't resolve on a card.

## When a skill says "publish to the issue tracker"

1. Find the feature's spec card, by `[<slug>]`, with `trelloSearch` or by reading the Specs list. If there isn't one and you're publishing a spec, create it in **Specs**.
2. Create each ticket card in the list matching its triage role (usually **Needs triage**, or **Ready for agent** when it's fully specified). Set `pos` to the ticket number so the cards keep their order.
3. Add each new card's URL to the spec card's **Tickets** checklist.

## When a skill says "fetch the relevant ticket"

The user normally passes a card URL, or a feature slug and number. Read it with `trelloReadCard` `get`, which returns the description, comments, checklists and the list it's in. Read the feature's spec card too, if the ticket refers to it.

## Changing state

Move the card with `trelloWriteCard` `move` to the destination list's ARI. When a ticket reaches **Done**, also tick its item on the spec card's **Tickets** checklist. When a spec's tickets are all done, add a closing comment to the spec card and leave it in **Specs**. When a whole feature is dropped, comment why on the spec card and move it to **Won't fix** along with its tickets.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a card with one **child** card per ticket.

- **Map**: a card in **Specs**, named `[<effort>] Map — <title>`. Its description holds the Notes / Decisions-so-far / Fog body.
- **Child ticket**: a card named `[<effort>] NN — <question>`, numbered from `01`, with the question in the description. The first line of the description is `Type: research|prototype|grilling|task`.
- **Blocking**: a `Blocked by: <card URL>, <card URL>` line near the top of the description. A ticket is unblocked when every card it lists is in **Done**.
- **Frontier**: the `[<effort>]` cards in **Ready for agent** or **Ready for human** that are unblocked. The lowest number wins.
- **Claim**: move the card to **In progress** before doing any work.
- **Resolve**: post the answer as a card comment headed `## Answer`, then move the card to **Done**. Append a context pointer (the gist plus the card URL) to Decisions-so-far in the map card's description.
