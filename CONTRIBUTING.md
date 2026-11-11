# Contributing to MapForge

Thanks for taking a look. MapForge is a personal tool, shaped around one DM's table. It is
open so other DMs can use it and build on it, but not every idea will fit how that table
plays. Please don't take a "no" personally.

## Issues

Issues are welcome:

- **Bugs.** Something broke, or the Player Display showed what it shouldn't. The Bug template
  asks for what's needed to reproduce it.
- **Ideas.** Something you'd like at your table. The Feature template asks what's happening at
  the table and what you'd like MapForge to do.
- **Translation corrections.** If a word in your language reads wrong, open a blank issue and
  say which word, where you saw it, and what your table calls it. Rulebook terms should match
  the official edition in your language.

## Pull requests

- **Open an issue first.** Before you write a PR, open an issue and say what you'd like to
  change. It saves you work on something that might not fit.
- **Target `develop`.** The project uses git flow: work goes on a `feature/<slug>` branch off
  `develop`, and PRs go into `develop`. `main` holds releases only.

### The project's words and decisions

- **Words.** MapForge's vocabulary is in [`CONTEXT.md`](CONTEXT.md): a Map, a Player Display,
  the Control Window, a Workspace, and so on. Use those words in code, docs and the interface.
  A new concept gets its term there, in the same change.
- **Decisions.** Past decisions are in [`docs/adr/`](docs/adr/). A change that reverses one
  says so, and adds an ADR that explains why.
- **Translations.** Translated terms are chosen in
  [`docs/terminology.md`](docs/terminology.md), not straight in the string catalogue
  ([ADR-0022](docs/adr/0022-rulebook-terms-are-the-tables-not-ours.md)). Change the termbase
  first, then the catalogue.

## Building and testing

How to generate the Xcode project, build the app and run the unit tests is in the README's
[Building](README.md#building) section.

The test command there runs the UI tests too, and they need a real second display. To run only
the unit tests, add `-only-testing:MapForgeTests` to it. Those are the tests a PR is expected
to pass.
