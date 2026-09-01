# MapForge

Presents DnD Maps on an HDMI-attached Player Display at True Scale (1 map inch = 1 physical inch), controlled from a Control Window on the Mac's own display.

Vocabulary: [CONTEXT.md](CONTEXT.md) · Decisions: [docs/adr/](docs/adr/) · Specs: `.scratch/map-presenter/spec.md`, `.scratch/fog-of-war/spec.md`

## Building

The Xcode project is generated (not checked in):

```sh
xcodegen generate                 # needs: brew install xcodegen
open MapForge.xcodeproj           # or:
xcodebuild -scheme MapForge -destination 'platform=macOS' build
xcodebuild -scheme MapForge -destination 'platform=macOS' test
```

Personal build — ad-hoc signed, no App Store. Deployment target macOS 15.
