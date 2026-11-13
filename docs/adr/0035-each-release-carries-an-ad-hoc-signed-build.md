# Each release carries an ad-hoc signed build

ADR-0034 dropped the App Store and said a DM who wants MapForge builds it: "there is no
download". That asks a DM to install Xcode and XcodeGen and run a terminal to get a map tool
for their table. Most DMs will not, and the ones MapForge is open for are DMs, not
developers.

From 2026-11-13, every GitHub Release carries a build: `MapForge-<version>.zip`, the app
**signed ad-hoc**, with its SHA-256 beside it. Building from source stays possible, as the
README's Building section says. It is no longer the only way in.

## The build is made by CI

`.github/workflows/release.yml` runs when a Release is published. It checks out the tag,
refuses a tag that does not match `MARKETING_VERSION` in `project.yml`, builds the Release
configuration for Apple silicon and Intel, verifies the signature, zips the app with `ditto`
and uploads it to the Release. It can also be run by hand for a tag that is already
released, which is how 2.0.0 gets its build.

This answers ADR-0034's objection that "every release would need a build made and uploaded
by hand". Publishing the Release is the last thing the author does, as before.

## What the DM goes through

macOS does not trust an ad-hoc signature from the internet. The first time the downloaded
app is opened, macOS refuses it, and the DM allows it once in **System Settings → Privacy &
Security → Open Anyway**. The README's Getting it section walks through this, and gives the
`xattr` command for a DM who prefers the terminal. The app is moved to Applications
**before** it is first opened, so macOS does not run it from a randomised read-only copy.

Every update is a new download, and asks for Open Anyway again. There is no updater.

## What stays

Everything ADR-0034 kept: the Workspace's bookmarks, Maps opened only from inside the
Workspace, MIT, the unlicensed name and icon, `PrivacyInfo.xcprivacy`. The build is the
author's own, so it carries the name and the icon.

## Consequences

Each ad-hoc build has a different signature from the last. Nothing in the app is keyed to
the signature: the app is not sandboxed, it holds no keychain items, and its settings are
keyed to its bundle identifier. The Workspace bookmarks are the one thing to watch. They are
security-scoped, made unsandboxed, and re-made every time a Workspace opens (ADR-0025). An
update that could not resolve one would show that recent as unavailable, as an unplugged
drive is (ADR-0012), and choosing the folder once more would store a new bookmark. Nothing
in the Workspace is lost either way. Whether this happens is checked by hand on the first
update from one build to the next.

## Considered Options

- **Keep "there is no download"** (ADR-0034) — rejected. It keeps out the DMs the project is
  open for.
- **A Developer ID build, notarised** — rejected again, for the same reason as in ADR-0034:
  a paid Apple Developer membership. It is the step to take if Open Anyway turns out to be
  more than DMs will put up with; the workflow would gain a signing and a notarising step,
  and nothing else would change.
- **Build on the author's Mac and upload by hand** — rejected. It is the step most likely to
  be skipped or done from the wrong branch, and CI already builds the app on every push.
- **Distribute through a Homebrew cask** — rejected. Homebrew no longer accepts casks that
  fail Gatekeeper, which an ad-hoc build does.
