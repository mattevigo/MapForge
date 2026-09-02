import AppKit
import XCTest
@testable import MapForge

/// A Creature: a Pawn the players discover. It emits no Light, it is hidden by darkness,
/// and the DM can take it off the Player Display without deleting it.
@MainActor
final class CreatureTests: XCTestCase {
    private let imageSize = CGSize(width: 1000, height: 800)

    // MARK: The flag

    func testAPawnIsNotACreatureByDefault() {
        // Every Pawn already authored is a party member, and every version 2 file decodes
        // without this key.
        XCTAssertFalse(makePawn().isCreature)
        XCTAssertFalse(makePawn().isHidden)
    }

    func testTheFlagsSurviveTheFogFile() throws {
        var creature = makePawn()
        creature.isCreature = true
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
        XCTAssertFalse(decoded.pawns[0].isCreature, "an existing Pawn became a Creature")
        XCTAssertFalse(decoded.pawns[0].isHidden)
    }

    // MARK: Creatures emit no Light

    func testACreatureLightsNothing() {
        // The half of the inversion that is not about rendering: a goblin waiting in an
        // unlit room must not be lighting the room it is hiding in.
        var creature = makePawn()
        creature.isCreature = true
        let document = FogDocument(pawns: [creature])

        let regions = VisibilityCache().regions(for: document, imagePixelSize: imageSize,
                                                pixelsPerSquare: 20)

        XCTAssertTrue(regions.isEmpty, "a Creature lit the room it was hiding in")
    }

    func testAPartyPawnStillLights() {
        // The control case, so the filter cannot be a blanket one.
        let document = FogDocument(pawns: [makePawn()])
        XCTAssertFalse(VisibilityCache().regions(for: document, imagePixelSize: imageSize,
                                                 pixelsPerSquare: 20).isEmpty)
    }

    func testTurningAPawnIntoACreatureRecomputesTheFog() {
        // The cache compares its inputs. If the filter ran anywhere that the cache key
        // does not see, flipping the flag would serve a stale polygon and the room would
        // stay lit by a Creature that no longer emits.
        let pawn = makePawn()
        var computations = 0
        let cache = VisibilityCache { computations += 1 }

        _ = cache.regions(for: FogDocument(pawns: [pawn]), imagePixelSize: imageSize,
                          pixelsPerSquare: 20)
        var creature = pawn
        creature.isCreature = true
        let after = cache.regions(for: FogDocument(pawns: [creature]),
                                  imagePixelSize: imageSize, pixelsPerSquare: 20)

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
                           isCreature: previous.isCreature))

        XCTAssertTrue(edits.document.pawns.last!.isCreature,
                      "the second goblin was placed as a party member")
    }

    func testMakingAPawnACreatureIsUndoable() {
        // Unlike hiding, this is an authoring decision about what the token *is*, and it
        // changes the lighting of the whole Map.
        let pawn = makePawn()
        var edits = FogEdits(document: FogDocument(pawns: [pawn]))
        edits.setPawnIsCreature(id: pawn.id, true)
        XCTAssertTrue(edits.document.pawns[0].isCreature)

        edits.undo()

        XCTAssertFalse(edits.document.pawns[0].isCreature, "the change was not undoable")
    }

    func testAHiddenPawnStopsLightingTheRoom() {
        // Hiding a Pawn takes its token off the Player Display. If its torch kept burning,
        // players would see a lit, wall-shadowed region radiating from nothing — and that
        // light is exactly what reveals Creatures, so a hidden Pawn could give away the
        // ambush it was hidden to set up.
        var hidden = makePawn()
        hidden.isHidden = true

        let regions = VisibilityCache().regions(for: FogDocument(pawns: [hidden]),
                                                imagePixelSize: imageSize, pixelsPerSquare: 20)

        XCTAssertTrue(regions.isEmpty, "a hidden Pawn was still lighting the room")
    }

    // MARK: What players see

    func testACreatureInTheDarkIsNotShownToPlayers() {
        // The point of the feature: a monster waiting in an unlit room is not on the
        // Player Display at all.
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                       regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true))
    }

    func testACreatureInBrightLightIsShownToPlayers() {
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 300, y: 300)),
                                                      regions: litRoom(),
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true))
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
                                                      hasVisibility: true))
    }

    func testAPartyPawnInTheDarkIsStillShown() {
        // Unchanged, and load-bearing: a player's own miniature must never vanish.
        // "Turning fog on is not turning tokens off" — PlayerView says so.
        var pawn = makePawn()
        pawn.at = MapPoint(x: 900, y: 700)
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: pawn, regions: litRoom(),
                                                      isFogOverlayOn: true,
                                                      hasVisibility: true))
    }

    func testSwitchingTheFogOverlayOffRevealsCreatures() {
        // The DM has switched the darkness off. A Creature that stayed hidden would be a
        // token nobody at the table could explain.
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                      regions: litRoom(),
                                                      isFogOverlayOn: false,
                                                      hasVisibility: true))
    }

    func testNoDeclaredGridShowsCreaturesRatherThanHidingThemAll() {
        // With no Grid, litRegions is empty and every point reads as unlit — so every
        // Creature would vanish and it would read as a bug. No Visibility at all means no
        // fog is being drawn, so there is nothing to hide behind.
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: creature(at: MapPoint(x: 900, y: 700)),
                                                      regions: [],
                                                      isFogOverlayOn: true,
                                                      hasVisibility: false))
    }

    // MARK: Hiding

    func testAHiddenCreatureIsNotShownEvenInBrightLight() {
        // Hidden beats lit. A monster that reappeared because someone lit a torch would
        // defeat the control entirely.
        var hidden = creature(at: MapPoint(x: 300, y: 300))
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true))
    }

    func testAHiddenPawnIsNotShownWithTheFogOverlayOff() {
        // Hiding outranks every other reason a token would be drawn.
        var hidden = creature(at: MapPoint(x: 300, y: 300))
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: false,
                                                       hasVisibility: true))
    }

    func testHidingIsAvailableToAPartyPawnToo() {
        // One boolean, not Creature-only: a DM may want a party token off the screen.
        var hidden = makePawn()
        hidden.isHidden = true
        XCTAssertFalse(PlayerVisibility.showsToPlayers(pawn: hidden, regions: litRoom(),
                                                       isFogOverlayOn: true,
                                                       hasVisibility: true))
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
                                                imagePixelSize: imageSize, pixelsPerSquare: 20)
        let asBig = VisibilityCache().regions(for: FogDocument(pawns: [big]),
                                              imagePixelSize: imageSize, pixelsPerSquare: 20)

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
                                                       hasVisibility: true))
    }

    func testBigIsIndependentOfCreature() {
        // Four combinations, all meaningful: an ogre ally, a goblin, an ogre monster, a
        // party member.
        var bigCreature = makePawn()
        bigCreature.isBig = true
        bigCreature.isCreature = true
        XCTAssertTrue(bigCreature.isBig)
        XCTAssertTrue(bigCreature.isCreature)
    }

    // MARK: Helpers

    private func makePawn() -> Pawn {
        Pawn(at: MapPoint(x: 300, y: 300), label: "1",
             colorHex: Pawn.defaultColorHex, brightSquares: 6)
    }

    private func creature(at point: MapPoint) -> Pawn {
        Pawn(at: point, label: "G", colorHex: Pawn.defaultColorHex,
             brightSquares: 6, isCreature: true)
    }

    /// A room lit around (300, 300); (900, 700) is well outside it.
    private func litRoom() -> [LitRegion] {
        VisibilityCache().regions(
            for: FogDocument(lights: [Light(at: MapPoint(x: 300, y: 300),
                                            brightSquares: 5, dimSquares: 5)]),
            imagePixelSize: imageSize, pixelsPerSquare: 20)
    }
}
