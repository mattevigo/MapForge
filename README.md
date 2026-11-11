# MapForge

MapForge is a virtual tabletop (VTT) for macOS, made for fifth-edition games played in person.
It shows your Map on a second display, a TV or monitor at the table, at True Scale: one inch
of Map is one inch of screen, so the players' miniatures fit the Grid. You run it from the Control
Window on the Mac's own screen. The players see only the Map.

What it does:

- **Player Display.** The Map fills the Player Display, with no controls on it. You choose
  which part of a large Map the table sees, or show the whole Map with Map Fit. Blackout hides
  it in one click.
- **Fog Overlay.** Trace Walls and place Lights, and the Player Display hides what no light
  reaches. The Control Window always shows you the whole Map.
- **Pawns and Lights.** Pawns are the tokens on the Map. A player's Pawn carries its own light.
  A Creature or a Treasure stays hidden until light falls on it. Solo Sight shows the Map as
  one character alone lights it.
- **Measurements.** Measure a Cone, Square, Circle or Line on the Map. The table sees the
  shape and its distance.
- **Encounters and Initiative.** Start an Encounter, roll Initiative, and step through Turns
  and Rounds while you track hit points and Conditions. Every Turn goes into a Combat Log. The
  Encounter Difficulty shows how hard the Encounter is for the Party.
- **Bestiary and Characters, read from your notes.** MapForge reads Monsters and Characters
  from the markdown notes in your Workspace. You keep writing them where you already do, and
  the app never changes them.
- **Rolls and the Session Log.** Record a Saving Throw or an Ability Check as the dice fell.
  Outside an Encounter, Pawn moves, Rolls and your Comments go into the evening's Session
  Log. During one, Pawn moves and Rolls go into the Combat Log.
- **Interface Language.** The app speaks English, Italian, German, French, Spanish, Brazilian
  Portuguese and Greek. Rulebook terms use the words of the official edition in that
  language, and stay in English where there is none.

Capitalised words such as Map, Pawn and Workspace have exact meanings. They are defined in
[CONTEXT.md](CONTEXT.md).

## What you need

- A Mac with macOS 15 or later.
- A second display for the Player Display: a TV or monitor connected over HDMI.
- A Workspace: a folder you choose, where your Maps live (PNG, JPEG or WebP images).
- Optional: markdown notes in that folder, for the Bestiary and Characters. MapForge reads
  Monsters and Characters from `statblock` code blocks, in the format of the Obsidian
  Fantasy Statblocks plugin.

## With DM Realm

[DM Realm](https://github.com/mattevigo/DM-Realm) is a Claude Code plugin that keeps a
fifth-edition campaign as markdown notes for Obsidian. It works in the same Workspace as
MapForge. After a Session, it brings MapForge's record of the evening, the Session Log and
each Encounter's Combat Log, into that Session's notes.

To start with DM Realm, follow its guide at
[mattevigo.github.io/DM-Realm](https://mattevigo.github.io/DM-Realm/guide/). Its
[At the table](https://mattevigo.github.io/DM-Realm/guide/play/) lesson shows how MapForge's
record joins a Session's notes.

## Getting it

MapForge is coming to the Mac App Store.

> **Mac App Store link:** _not available yet._

Until then, build it from source.

## Building

The Xcode project is generated from `project.yml` and is not checked in. You need Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open MapForge.xcodeproj           # or build and test from the command line:
xcodebuild -scheme MapForge -destination 'platform=macOS' build
xcodebuild -scheme MapForge -destination 'platform=macOS' test
```

The `test` command runs the UI tests too. They launch the app and drive it on screen, so they
are slow and need the Mac to yourself while they run. To run only the unit tests, add
`-only-testing:MapForgeTests`:

```sh
xcodebuild -scheme MapForge -destination 'platform=macOS' test -only-testing:MapForgeTests
```

## Releasing

Releases follow git flow:

1. Start a `release/<version>` branch off `develop`.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Add the version's entry to [CHANGELOG.md](CHANGELOG.md).
4. Finish the release: merge it into `main` and back into `develop`.
5. Tag the release commit on `main` as `v<version>`.
6. Publish a GitHub Release for that tag. Its notes are the version's CHANGELOG entry.

No build is attached to the release.

## Learn more

- [CONTEXT.md](CONTEXT.md): the project's vocabulary.
- [docs/adr/](docs/adr/): the decisions behind the design, and why.
- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to report a problem or propose a change.
- [.scratch/](.scratch/): the archive of earlier feature specs.

## Licence

The source code is licensed under the MIT License. See [LICENSE](LICENSE).

The name "MapForge" and the app icon are not licensed. A build that anyone else distributes
must be given a different name and a different icon.

MapForge uses material from the System Reference Document 5.2.1, credited in
[NOTICE](NOTICE).

## Unofficial content

MapForge is unofficial and is not affiliated with or endorsed by Wizards of the Coast LLC.
