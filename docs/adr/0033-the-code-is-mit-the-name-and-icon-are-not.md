# The code is MIT, the name and the icon are not

MapForge is published on GitHub under the **MIT licence**, © 2026 Matteo Vigoni. The licence
covers the source. It does not cover the name "MapForge" or the app icon: a build someone
else redistributes must be renamed and carry its own icon.

## Why MIT

MapForge is headed to the Mac App Store (ADR-0025). A copyleft licence would not stop its
author from shipping there, but the App Store's terms are widely held to be incompatible
with the GPL, so contributed code under the GPL would be code the author could not ship.
MPL-2.0 has the same problem, one file at a time. MIT keeps every contribution shippable.
It is also the licence of Yams, the only dependency (ADR-0019), so the repo carries one
kind of licence throughout. What MIT gives up is that anyone may take the code into a
closed app. For a tool shaped around one DM's table, that is an acceptable cost.

## Why the name and the icon are kept back

A licence file that covered the icon would let anyone ship a fork to the App Store that
looks identical to MapForge. MIT grants no trademark rights in any case. Saying so
explicitly, in `NOTICE` and the README, is the common practice for open-source apps that
are also sold in a store.

## Consequences

- The SRD 5.2.1 material the app reckons with (the Encounter Difficulty bands and XP
  budgets of ADR-0032, and the Italian, German, French and Spanish rulebook terms of
  ADR-0022, from WotC's translated SRD 5.2.1) is CC-BY-4.0, not MIT. `NOTICE` carries the
  attribution that licence requires. The Brazilian Portuguese terms come from the
  Galápagos/Asmodee *Livro do Jogador*, not the SRD, and Greek keeps the English terms.
- Changing the licence later needs the agreement of everyone who has contributed code.
  Until there are outside contributions, that is only the author.
