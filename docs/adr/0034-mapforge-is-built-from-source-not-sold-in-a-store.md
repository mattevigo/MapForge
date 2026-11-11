# MapForge is built from source, not sold in a store

Three decisions leaned on the Mac App Store:
- the Workspace reached through a security-scoped bookmark (ADR-0025);
- Maps opened only from inside the Workspace (ADR-0026);
- the MIT licence, chosen so that every contribution could ship there (ADR-0033).

On 2026-11-11 the App Store was dropped. MapForge is published as source on GitHub, and
there is no download. A DM who wants it builds it, as the README's Building section says.

## What a release is

A release is a tag on `main`, `v<version>`, and a GitHub Release whose notes are that
version's CHANGELOG entry. No build is attached to it.

## What stays

- **The Workspace and its bookmarks.** Bookmarks are made and resolved the same way without
  the sandbox (ADR-0025), and they still find a Workspace the DM has renamed or moved in
  Finder.
- **Maps open only from inside the Workspace.** ADR-0026's reason was the sandbox, and that
  reason is gone. But 2.0.0 shipped with the rule, and a Map's files are still written
  beside it, in the folder the DM keeps their game in. Lifting the rule would be a decision
  of its own, not a side effect of this one.
- **MIT.** The App Store argument is gone, but the others hold. MIT is the licence of Yams,
  the only dependency, so the repo carries one kind of licence throughout. Changing it now
  would need the agreement of everyone who has contributed code (ADR-0033).
- **The name and the icon stay unlicensed.** A fork published under them would still pass
  for MapForge.
- **`PrivacyInfo.xcprivacy` stays.** It says what is true of the app, and nothing reads it
  outside the App Store.

## Considered Options

- **Attach an ad-hoc signed build to each Release** — rejected. macOS stops a downloaded
  ad-hoc build on first launch until the DM allows it in System Settings, and every release
  would need a build made and uploaded by hand.
- **A Developer ID build, notarised** — rejected. It needs a paid Apple Developer membership,
  and a build notarised by Apple for every release.
- **Lift ADR-0026's rule now that there is no sandbox** — deferred. It would be a change to
  the app and a later release, decided on its own.
