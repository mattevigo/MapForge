# Yams is the first dependency

The app has shipped with no Swift packages at all: `project.yml` has no `packages:` section
and everything on disk is JSON through `Codable`. The Bestiary ends that. A **Monster** is
read out of a ```` ```statblock ```` fence in the DM's own markdown notes, and what is inside
that fence is YAML. We parse it with [Yams](https://github.com/jpsim/Yams).

## The files were written for a real YAML parser

The notation is the Obsidian Fantasy Statblocks plugin's, and the DM's notes are authored
against *its* parser, not ours. A survey of the 37 files this was designed against found
quoted strings containing `*`, `:` and `[[wikilinks]]`, inline arrays (`stats: [14, 12, …]`),
lists of maps (`actions:`), lists of single-key maps (`saves:`, `skillsaves:`), unquoted
fractions (`cr: 1/2`), and `desc` values that run to several paragraphs. That is not a
subset anyone chose; it is whatever YAML the DM happened to type and Obsidian happened to
accept. A hand-written reader would be correct for the files surveyed and wrong for the next
one, and the way it would be wrong is a Monster that silently fails to appear in a search.

## What decided it was the reference view

Had the feature stopped at stamping armour class, hit points and an initiative bonus, a
line reader for five scalar keys would have been defensible, and the app would have stayed
dependency-free. It does not stop there: the Combat tab shows the Monster's traits and
actions while it fights, and those are exactly the long quoted `desc` strings that a line
reader cannot read. Parsing them by hand means rebuilding YAML's quoting and block-scalar
rules badly.

## Consequences

Yams is the only place YAML is known about. It turns a fence's text into a tree; everything
about what a Monster *is* — the leading integer taken from `hp: 67 (9d8 + 27)`, the Unicode
minus in `"−1 (9)"`, which sizes make a Pawn Big — is the app's own code on top of that tree,
and is tested without Yams' help.

Nothing the app **writes** becomes YAML. `.mapforge/` stays JSON, `bestiary.json` included.

This is not a precedent for taking packages freely. The bar it cleared is that the format is
someone else's, is a published standard, and is authored by a tool whose parser we must
agree with.

## Considered Options

- **A hand-written parser for the plugin's subset** — rejected above: the subset is not
  defined anywhere, and the failure is silent.
- **A scalar-only line reader, ignoring `actions` and the rest** — rejected because the
  reference view is in scope. It is the right answer to a smaller feature.
- **Ask the DM to keep Monsters in JSON** — rejected: the notes already exist, in Obsidian,
  where the DM reads them. A second copy in our format is a second thing to keep in step.
