# MapForge

Presents DnD Maps on an HDMI-attached Player Display at True Scale (1 map inch = 1 physical inch), controlled from a Control Window on the Mac's own display.

Fog of War: trace Walls, place Lights and Pawns, and the Player Display shows the darkness they imply — while the Control Window keeps the whole Map visible to the DM.

Vocabulary: [CONTEXT.md](CONTEXT.md) · Decisions: [docs/adr/](docs/adr/) · Releases: [CHANGELOG.md](CHANGELOG.md) · Specs: `.scratch/<feature>/spec.md`

## Building

The Xcode project is generated (not checked in):

```sh
xcodegen generate                 # needs: brew install xcodegen
open MapForge.xcodeproj           # or:
xcodebuild -scheme MapForge -destination 'platform=macOS' build
xcodebuild -scheme MapForge -destination 'platform=macOS' test
```

Personal build — ad-hoc signed, no App Store. Deployment target macOS 15.

## Releasing

The version lives in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
Bump it, add the entry to `CHANGELOG.md`, then build the app in Release and zip it:

```sh
xcodegen generate
xcodebuild -scheme MapForge -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
ditto -c -k --keepParent build/DerivedData/Build/Products/Release/MapForge.app \
  build/MapForge-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml).zip
```

`build/` is ignored by git. Tag the release commit `v<version>` once it is on `master`.
