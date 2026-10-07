# Triage Labels

The skills speak in terms of five canonical triage roles. On this repo's Trello board each role is a **list**, not a label: a card's triage state is the list it sits in. See `issue-tracker.md` for the list ARIs.

| Label in mattpocock/skills | List on our board | Meaning                                  |
| -------------------------- | ----------------- | ---------------------------------------- |
| `needs-triage`             | Needs triage      | Maintainer needs to evaluate this issue  |
| `needs-info`               | Needs info        | Waiting on reporter for more information |
| `ready-for-agent`          | Ready for agent   | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | Ready for human   | Requires human implementation            |
| `wontfix`                  | Won't fix         | Will not be actioned                     |

When a skill says to apply a role (e.g. "apply the AFK-ready triage label"), move the card to the corresponding list. Don't create a Trello label for it.

The board also has **Specs**, **In progress** and **Done**, which aren't triage roles.
