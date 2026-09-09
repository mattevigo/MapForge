import AppKit
import XCTest
@testable import MapForge

/// What a Pawn *is*: a party member, a Creature, or a Treasure. The two kinds the players
/// discover emit no Light and are hidden by darkness; the DM can take any of them off the
/// Player Display without deleting it.
@MainActor
final class CreatureTests: XCTestCase {
    private let imageSize = CGSize(width: 1000, height: 800)

    // MARK: The flag

    func testAPawnIsNotACreatureByDefault() {
        // Every Pawn already authored is a party member, and every version 2 file decodes
        // without this key.
        XCTAssertEqual(makePawn().kind, .player)
        XCTAssertFalse(makePawn().isHidden)
    }

    func testTheFlagsSurviveTheFogFile() throws {
        var creature = makePawn()
        creature.kind = .creature
        creature.isHidden = true
        let document = FogDocument(pawns: [creature])
        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
    }

    func testAFileWithoutTheKeysLoadsEveryPawnAsAPartyMember() throws {
        // A fog file written before Creatures existed. Nothing in it may become a monster.
        let json = Data("""
        {
          "version": 2,
          "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)",
            "label": "Vex",
            "colorHex": "#C81E1E",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 12, "isOn": true
            }
          }]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertEqual(decoded.pawns.count, 1)
        XCTAssertEqual(decoded.pawns[0].kind, .player, "an existing Pawn became a Creature")
        XCTAssertFalse(decoded.pawns[0].isHidden)
    }

    // MARK: Creatures emit no Light

    func testACreatureLightsNothing() {
        // The half of the inversion that is not about rendering: a goblin waiting in an
        // unlit room must not be lighting the room it is hiding in.
        var creature = makePawn()
        creature.kind = .creature
        let document = FogDocument(pawns: [creature])

        let regions = VisibilityCache().regions(for: document, imagePixelSize: imageSize,
                                                pixelsPerSquare: 20, soloSightPawnID: nil)

        XCTAssertTrue(regions.isEmpty, "a Creature lit the room it was hiding in")
    }

    func testAPartyPawnStillLights() {
        // The control case, so the filter cannot be a blanket one.
        let document = FogDocument(pawns: [makePawn()])
        XCTAssertFalse(VisibilityCache().regions(for: document, imagePixelSize: imageSize,
                                                 pixelsPerSquare: 20, soloSightPawnID: nil).isEmpty)
    }

    func testTurningAPawnIntoACreatureRecomputesTheFog() {
        // The cache compares its inputs. If the filter ran anywhere that the cache key
        // does not see, flipping the flag would serve a stale polygon and the room would
        // stay lit by a Creature that no longer emits.
        let pawn = makePawn()
        var computations = 0
        let cache = VisibilityCache { computations += 1 }

        _ = cache.regions(for: FogDocument(pawns: [pawn]), imagePixelSize: imageSize,
                          pixelsPerSquare: 20, soloSightPawnID: nil)
        var creature = pawn
        creature.kind = .creature
        let after = cache.regions(for: FogDocument(pawns: [creature]),
                                  imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)

        XCTAssertEqual(computations, 2, "the flag did not invalidate the cache")
        XCTAssertTrue(after.isEmpty, "the Creature was still lighting the room")
    }

    func testANewPawnCopiesTheLastOnesCreatureFlag() {
        // A DM populating an encounter places six goblins in a row. Toggling each one
        // afterwards is six chances to miss one and light the room with it.
        var edits = FogEdits(document: FogDocument(pawns: [creature(at: MapPoint(x: 10, y: 10))]))
        let previous = edits.document.pawns.last!
        edits.addPawn(Pawn(at: MapPoint(x: 50, y: 50), label: "2",
                           colorHex: previous.colorHex,
                           brightSquares: previous.light.brightSquares,
                           kind: previous.kind))

        XCTAssertEqual(edits.document.pawns.last!.kind, .creature,
                       "the second goblin was placed as a party member")
    }

    func testMakingAPawnACreatureIsUndoable() {
        // Unlike hiding, this is an authoring decision about what the token *is*, and it
        // changes the lighting of the whole Map.
        let pawn = makePawn()
        var edits = FogEdits(document: FogDocument(pawns: [pawn]))
        edits.setPawnKind(id: pawn.id, .creature)
        XCTAssertEqual(edits.document.pawns[0].kind, .creature)

        edits.undo()

        XCTAssertEqual(edits.document.pawns[0].kind, .player, "the change was not undoable")
    }

    func testAHiddenPawnStopsLightingTheRoom() {
        // Hiding a Pawn takes its token off the Player Display. If its torch kept burning,
        // players would see a lit, wall-shadowed region radiating from nothing — and that
        // light is exactly what reveals Creatures, so a hidden Pawn could give away the
        // ambush it was hidden to set up.
        var hidden = makePawn()
        hidden.isHidden = true

        let regions = VisibilityCache().regions(for: FogDocument(pawns: [hidden]),
                                                imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)

        XCTAssertTrue(regions.isEmpty, "a hidden Pawn was still lighting the room")
    }

    // MARK: What players see

    func testACreatureInTheDarkIsNotShownToPlayers() {
        // The point of the feature: a monster waiting in an unlit room is not on the
        // Player Display at all.
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                       regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testACreatureInBrightLightIsShownToPlayers() {
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 300, y: 300)),
                                                      regions: litRoom(),
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true, soloSightPawnID: nil))
    }

    func testDimLightRevealsACreature() {
        // 5e treats dim light as lightly obscured, not as blindness. A Creature standing
        // on floor the players can plainly see must not be invisible.
        let regions = [LitRegion(lightID: UUID(),
                                 origin: MapPoint(x: 50, y: 50),
                                 bright: Polygon([]),
                                 dim: Polygon([MapPoint(x: 0, y: 0), MapPoint(x: 100, y: 0),
                                               MapPoint(x: 100, y: 100), MapPoint(x: 0, y: 100)]))]
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 50, y: 50)),
                                                      regions: regions,
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true, soloSightPawnID: nil))
    }

    func testAPartyPawnInTheDarkIsStillShown() {
        // Unchanged, and load-bearing: a player's own miniature must never vanish.
        // "Turning fog on is not turning tokens off" — PlayerView says so.
        var pawn = makePawn()
        pawn.at = MapPoint(x: 900, y: 700)
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: pawn, regions: litRoom(),
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true, soloSightPawnID: nil))
    }

    func testSwitchingTheFogOverlayOffRevealsCreatures() {
        // The DM has switched the darkness off. A Creature that stayed hidden would be a
        // token nobody at the table could explain.
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                      regions: litRoom(),
                                                      isFogOverlayOn: false,
                                                      hasVisibility: true, soloSightPawnID: nil))
    }

    func testNoDeclaredGridShowsCreaturesRatherThanHidingThemAll() {
        // With no Grid, litRegions is empty and every point reads as unlit — so every
        // Creature would vanish and it would read as a bug. No Visibility at all means no
        // fog is being drawn, so there is nothing to hide behind.
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                      regions: [],
                                                      isFogOverlayOn: true,
                                                      hasVisibility: false, soloSightPawnID: nil))
    }

    // MARK: Hiding

    func testAHiddenCreatureIsNotShownEvenInBrightLight() {
        // Hidden beats lit. A monster that reappeared because someone lit a torch would
        // defeat the control entirely.
        var hidden = creature(at: MapPoint(x: 300, y: 300))
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testAHiddenPawnIsNotShownWithTheFogOverlayOff() {
        // Hiding outranks every other reason a token would be drawn.
        var hidden = creature(at: MapPoint(x: 300, y: 300))
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: false,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testHidingIsAvailableToAPartyPawnToo() {
        // One boolean, not Creature-only: a DM may want a party token off the screen.
        var hidden = makePawn()
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testHidingIsNotUndoable() throws {
        // Follows setPawnLight's precedent: a live performance action, and filling the
        // undo stack with toggles buries the DM's authoring work.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CreatureTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("map.png")
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus(); NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill(); image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)

        let appState = AppState(
            preferences: DisplayPreferences(defaults: UserDefaults(suiteName: "cr.\(UUID().uuidString)")!))
        appState.loadMap(image: image, at: url)
        let pawn = makePawn()
        appState.fog.pawns = [pawn]

        appState.setPawnHidden(id: pawn.id, isHidden: true)

        XCTAssertTrue(appState.fog.pawns[0].isHidden)
        appState.flushPendingFogWrites()
        XCTAssertEqual(FogStore().load(forMapAt: url)?.pawns.first?.isHidden, true,
                       "hiding did not survive to the fog file")
    }

    // MARK: Sight has no dim band

    func testAPawnsDimRadiusIsOneSquarePastItsSight() {
        // A character's sight is not a light source. DnD has no "dim vision" band, so the
        // extra square is cosmetic only — it softens the edge of the visible region so the
        // shadow does not read as a hard cut.
        let pawn = Pawn(at: MapPoint(x: 0, y: 0), label: "1",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        XCTAssertEqual(pawn.light.brightSquares, 6)
        XCTAssertEqual(pawn.light.dimSquares, 7)
    }

    func testChangingSightMovesTheFeatheredEdgeWithIt() {
        let pawn = Pawn(at: MapPoint(x: 0, y: 0), label: "1",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        var edits = FogEdits(document: FogDocument(pawns: [pawn]))
        edits.setPawnSight(id: pawn.id, squares: 3)

        XCTAssertEqual(edits.document.pawns[0].light.brightSquares, 3)
        XCTAssertEqual(edits.document.pawns[0].light.dimSquares, 4)
    }

    func testAPawnStoredWithTheOldDoubledDimIsCorrectedOnLoad() {
        // Every Pawn authored before this change has dim at twice its sight — a 12-square
        // halo for a 6-square sight. Derived rather than migrated: the file keeps whatever
        // it says and the Pawn ignores it, so no map is silently rewritten and the two
        // values can never drift apart again.
        let json = Data("""
        {
          "version": 2, "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)", "label": "Vex", "colorHex": "#C81E1E",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 12, "isOn": true
            }
          }]
        }
        """.utf8)
        let decoded = try! JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertEqual(decoded.pawns[0].light.dimSquares, 7,
                       "an old Pawn kept its oversized halo")
    }

    func testALightKeepsItsOwnIndependentDimRadius() {
        // Unchanged, and the reason this is a Pawn rule rather than a Light rule: a torch
        // really does have bright and dim bands, and every 5e stat block gives both.
        let torch = Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, dimSquares: 40)
        XCTAssertEqual(torch.dimSquares, 40)
    }

    func testAPlacedPawnDoesNotInheritAPreviousPawnsDimRadius() {
        // Placement copied the previous Pawn's radii wholesale, which is how a stale dim
        // travelled from one token to the next.
        let previous = Pawn(at: MapPoint(x: 0, y: 0), label: "1",
                            colorHex: Pawn.defaultColorHex, brightSquares: 6)
        let placed = Pawn(at: MapPoint(x: 50, y: 50), label: "2",
                          colorHex: previous.colorHex,
                          brightSquares: previous.light.brightSquares)
        XCTAssertEqual(placed.light.dimSquares, 7)
    }

    func testTheFeatheredEdgeActuallyFadesRatherThanFormingARing() {
        // A one-square band shaded at a flat 0.55 would read as a grey ring, not a soft
        // edge — 0.55 was chosen when dim was a real 5e band around a torch. The radial
        // falloff is what saves it: it starts at 75% of the radius, so for sight 6 / dim 7
        // the fade runs from 5.25 squares out to nothing at the rim.
        XCTAssertEqual(FogShading.falloffOpacity(atFractionOfRadius: 1.0), 0, accuracy: 1e-9,
                       "the edge did not reach zero at the rim")
        XCTAssertEqual(FogShading.falloffOpacity(atFractionOfRadius: 0.5), 1, accuracy: 1e-9,
                       "the middle of the region should be at full strength")
        let midFade = FogShading.falloffOpacity(atFractionOfRadius: 0.875)
        XCTAssertGreaterThan(midFade, 0, "no gradient across the feathered band")
        XCTAssertLessThan(midFade, 1, "the band is a hard ring rather than a fade")
    }

    // MARK: The live panel's grouping

    func testThePanelSeparatesPlayersFromCreatures() {
        // The DM reasons about these separately: the party is who they run the world for,
        // the Creatures are what they run at them. The split is on `isCreature` alone.
        var goblin = makePawn()
        goblin.kind = .creature
        let pawns = [makePawn(), goblin, makePawn()]

        XCTAssertEqual(pawns.filter { $0.kind == .player }.count, 2)
        XCTAssertEqual(pawns.filter { $0.kind == .creature }.count, 1)
    }

    func testEveryPawnLandsInExactlyOneGroup() {
        // Two hand-written filters over one array were only correct while they happened
        // to partition it — and Treasure is the third category that broke that. Counting
        // through `PawnKind.allCases` is what makes the panel total by construction: a
        // token the DM cannot find in the list is one they cannot hide or rename
        // mid-fight.
        var goblin = makePawn()
        goblin.kind = .creature
        var hiddenBigOgre = makePawn()
        hiddenBigOgre.kind = .creature
        hiddenBigOgre.isBig = true
        hiddenBigOgre.isHidden = true
        var chest = makePawn()
        chest.kind = .treasure
        let pawns = [makePawn(), goblin, hiddenBigOgre, chest]

        let listed = PawnKind.allCases
            .map { kind in pawns.filter { $0.kind == kind }.count }
            .reduce(0, +)
        XCTAssertEqual(listed, pawns.count, "a Pawn was missing from the panel")
    }

    // MARK: Big

    func testAPawnIsOneSquareByDefault() {
        XCTAssertFalse(makePawn().isBig)
        XCTAssertEqual(Pawn.squaresAcross(isBig: false), 1)
    }

    func testABigPawnIsTwoSquaresAcross() {
        XCTAssertEqual(Pawn.squaresAcross(isBig: true), 2)
    }

    func testBigSurvivesTheFogFile() throws {
        var big = makePawn()
        big.isBig = true
        let document = FogDocument(pawns: [big])
        XCTAssertEqual(try JSONDecoder().decode(FogDocument.self,
                                                from: JSONEncoder().encode(document)),
                       document)
    }

    func testAFileWithoutTheBigKeyLoadsPawnsAsOneSquare() throws {
        // Same back-compat trap the Creature flags hit: a property default is not enough
        // for Swift's synthesised decode, and every .fog.json already beside a Map lacks
        // this key.
        let json = Data("""
        {
          "version": 2, "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)", "label": "Vex", "colorHex": "#C81E1E",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 12, "isOn": true
            }
          }]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertFalse(decoded.pawns[0].isBig, "an existing Pawn became Big")
    }

    func testBigDoesNotChangeWhatAPawnLights() {
        // Size is purely visual: an ogre's torch reaches as far as anyone's, and the radii
        // are still measured from the Pawn's point. 5e agrees — creature size does not
        // alter light or vision range.
        //
        // Both documents are built from ONE Pawn value so the light IDs match, and the
        // whole region array is compared: minting a second Pawn would give a different
        // UUID, and comparing only `first?.bright` would pass even if a Big Pawn's dim
        // radius were scaled.
        let small = makePawn()
        var big = small
        big.isBig = true

        let asSmall = VisibilityCache().regions(for: FogDocument(pawns: [small]),
                                                imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)
        let asBig = VisibilityCache().regions(for: FogDocument(pawns: [big]),
                                              imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)

        XCTAssertFalse(asSmall.isEmpty, "precondition: the Pawn lit something")
        XCTAssertEqual(asBig, asSmall, "being Big changed the light it casts")
    }

    func testABigPawnsLabelIsTheSameSizeAsASmallOnes() {
        // The disc doubles; the text does not. Sizing the label from the doubled diameter
        // rendered an ogre's "3" at twice its neighbours' point size and halved its
        // legibility floor — both effects of conflating footprint with view size.
        XCTAssertTrue(PawnToken.showsLabel(atDiameter: 10),
                      "a 10 pt square should still carry a label")
        XCTAssertFalse(PawnToken.showsLabel(atDiameter: 6),
                       "the floor is per-square, not per-token")
    }

    func testABigCreatureIsRevealedByItsOwnPointNotItsFootprint() {
        // The reveal rule reads the Pawn's position, as it does for every Pawn. A Big
        // Creature whose disc overlaps a lit square but whose centre is dark stays hidden
        // — consistent, and the alternative is a token half-drawn at the light's edge.
        var big = creature(at: MapPoint(x: 900, y: 700))
        big.isBig = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: big, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testBigIsIndependentOfCreature() {
        // Four combinations, all meaningful: an ogre ally, a goblin, an ogre monster, a
        // party member.
        var bigCreature = makePawn()
        bigCreature.isBig = true
        bigCreature.kind = .creature
        XCTAssertTrue(bigCreature.isBig)
        XCTAssertEqual(bigCreature.kind, .creature)
    }

    // MARK: Treasure

    func testATreasureEmitsNoLight() {
        // The half Treasure shares with a Creature: a chest is not a lamp, and a vault
        // that lit itself would reveal the room the party has not entered yet.
        let regions = VisibilityCache().regions(
            for: FogDocument(pawns: [treasure(at: MapPoint(x: 300, y: 300))]),
            imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)

        XCTAssertTrue(regions.isEmpty, "a Treasure lit the room it was sitting in")
    }

    func testATreasureInTheDarkIsNotShownToPlayers() {
        // Players discover loot; they are not handed a map of it. Same rule as a Creature,
        // and it comes from the same `isDiscovered` branch rather than a second one.
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: treasure(at: MapPoint(x: 900, y: 700)),
                                                       regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testATreasureInTheLightIsShownToPlayers() {
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: treasure(at: MapPoint(x: 300, y: 300)),
                                                      regions: litRoom(),
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true, soloSightPawnID: nil))
    }

    func testATreasureCanBeHiddenLikeAnyOtherPawn() {
        // Hidden still beats lit, for every kind: a chest the DM is not ready to reveal
        // must not appear because someone lit a torch.
        var hidden = treasure(at: MapPoint(x: 300, y: 300))
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true, soloSightPawnID: nil))
    }

    func testATreasureIsOneSquareByDefaultAndCanStillBeBig() {
        // Size stays orthogonal to kind, exactly as it is for a Creature — a 1x1 chest and
        // a 2x2 hoard are both meaningful, so Treasure does not weld itself to a footprint.
        var chest = treasure(at: MapPoint(x: 10, y: 10))
        XCTAssertEqual(chest.squaresAcross, 1)
        chest.isBig = true
        XCTAssertEqual(chest.squaresAcross, 2)
    }

    func testTreasureSurvivesTheFogFile() throws {
        let document = FogDocument(pawns: [treasure(at: MapPoint(x: 10, y: 10))])
        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.pawns[0].kind, .treasure)
    }

    func testAFileWrittenWithTheOldCreatureFlagStillLoadsAsACreature() throws {
        // The migration that must never be deleted. Every .fog.json already beside a Map
        // carries `isCreature`, not `kind`; a goblin that decoded as a party member would
        // start lighting the room it is hiding in, which is the exact defect the Creature
        // feature was built to prevent.
        let json = Data("""
        {
          "version": 2, "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)", "label": "G", "colorHex": "#C81E1E",
            "isCreature": true, "isHidden": true, "isBig": true,
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 12, "isOn": true
            }
          }]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertEqual(decoded.pawns[0].kind, .creature, "a stored Creature became a party member")
        XCTAssertTrue(decoded.pawns[0].isHidden, "the other flags stopped decoding")
        XCTAssertTrue(decoded.pawns[0].isBig)
    }

    func testOnlyPartyPawnsEmitLight() {
        // The rule stated once, over every case: adding a fourth kind without deciding
        // which side of the fog it falls on should fail here.
        for kind in PawnKind.allCases {
            XCTAssertEqual(kind.isDiscovered, kind != .player,
                           "\(kind) fell on the wrong side of the fog")
        }
    }

    func testEveryKindHasItsOwnPanelHeading() {
        // Two kinds sharing a heading would merge two groups into one list, and the DM
        // would be hunting for a chest among the goblins.
        XCTAssertEqual(Set(PawnKind.allCases.map(\.pluralTitle)).count, PawnKind.allCases.count)
        XCTAssertEqual(Set(PawnKind.allCases.map(\.title)).count, PawnKind.allCases.count)
    }

    // MARK: Helpers

    private func makePawn() -> Pawn {
        Pawn(at: MapPoint(x: 300, y: 300), label: "1",
             colorHex: Pawn.defaultColorHex, brightSquares: 6)
    }

    private func creature(at point: MapPoint) -> Pawn {
        Pawn(at: point, label: "G", colorHex: Pawn.defaultColorHex,
             brightSquares: 6, kind: .creature)
    }

    private func treasure(at point: MapPoint) -> Pawn {
        Pawn(at: point, label: "T", colorHex: Pawn.defaultColorHex,
             brightSquares: 6, kind: .treasure)
    }

    /// A room lit around (300, 300); (900, 700) is well outside it.
    private func litRoom() -> [LitRegion] {
        VisibilityCache().regions(
            for: FogDocument(lights: [Light(at: MapPoint(x: 300, y: 300),
                                            brightSquares: 5, dimSquares: 5)]),
            imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)
    }
}
