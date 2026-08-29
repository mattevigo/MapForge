# 01 — Xcode project scaffolding

Status: ready-for-human

Create the MapForge Xcode project at the repo root: SwiftUI app lifecycle, deployment target macOS 15, app name **MapForge**. No App Store/notarization setup — personal Xcode build. Add a `.gitignore` for Xcode (xcuserdata, DerivedData, etc.).

Acceptance: `xcodebuild build` succeeds; launching shows an empty Control Window.

## Comments

**2026-08-29 (agent)** — Done in `feature/project-scaffolding` (plus a POC slice of True Scale presentation). Deviation from the letter of the acceptance: the `.xcodeproj` is generated from a checked-in `project.yml` via xcodegen (installed via Homebrew) and is gitignored, so a fresh clone needs `xcodegen generate` before `xcodebuild build` — documented in README. Status set to ready-for-human: True Scale needs verification with a real ruler on the actual HDMI screen. Deferred from review: introduce a proper `Map` type (image + url + scale — currently loose fields in AppState); issues 02/03 should create it.
