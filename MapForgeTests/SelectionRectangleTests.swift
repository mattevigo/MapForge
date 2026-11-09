import XCTest
@testable import MapForge

/// The selection rectangle: with nothing armed, a drag on the bare Map picks the Pawns whose
/// centres it covers (`CONTEXT.md`, **Selection**; the `pawn-selection` spec, ticket 03).
@MainActor
final class SelectionRectangleTests: XCTestCase {

    // MARK: The centre rule

    /// A Pawn is in when its centre is. The rectangle is in Map space — image pixels, where
    /// `Pawn.at` is — so this holds at any magnification.
    func testAPawnWhoseCentreIsInsideIsPicked() {
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 50))

        XCTAssertEqual(SelectionRectangle.pawnIDs(centredIn: CGRect(x: 0, y: 0,
                                                                     width: 100, height: 100),
                                                  among: [rogue, fighter]),
                       [rogue.id])
    }

    /// A Big Pawn's token reaching into the rectangle is not enough: an ogre half in and
    /// half out is picked by where it stands, as every other Pawn is.
    func testABigPawnOverlappingTheEdgeWithItsCentreOutsideIsNotPicked() {
        // 40 pixels a square: the ogre spans 80, so from x 110 it reaches back to x 70.
        let ogre = pawn("Ogre", at: MapPoint(x: 110, y: 50), kind: .creature, isBig: true)

        XCTAssertEqual(SelectionRectangle.pawnIDs(centredIn: CGRect(x: 0, y: 0,
                                                                     width: 100, height: 100),
                                                  among: [ogre]),
                       [])
    }

    /// Every Kind is picked alike — a Creature or a Treasure inside is as much in as a
    /// Player.
    func testEveryKindOfPawnIsPicked() {
        let rogue = pawn("Rogue", at: MapPoint(x: 10, y: 10))
        let goblin = pawn("Goblin", at: MapPoint(x: 20, y: 20), kind: .creature)
        let chest = pawn("Chest", at: MapPoint(x: 30, y: 30), kind: .treasure)

        XCTAssertEqual(Set(SelectionRectangle.pawnIDs(centredIn: CGRect(x: 0, y: 0,
                                                                         width: 50, height: 50),
                                                      among: [rogue, goblin, chest])),
                       [rogue.id, goblin.id, chest.id])
    }

    /// A centre exactly on the edge counts: the DM who drew the edge through the token has
    /// drawn it round the token as far as anyone can see.
    func testACentreOnTheEdgeIsInside() {
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))

        XCTAssertEqual(SelectionRectangle.pawnIDs(centredIn: CGRect(x: 0, y: 0,
                                                                     width: 100, height: 100),
                                                  among: [rogue]),
                       [rogue.id])
    }

    // MARK: Replace, add, clear

    /// A plain rectangle is a fresh pick: the Pawns inside become the whole Selection, and
    /// everything picked before — a Pawn outside, a Light — is let go.
    func testAPlainRectangleReplacesTheSelectionLightsIncluded() {
        let appState = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let goblin = pawn("Goblin", at: MapPoint(x: 300, y: 300), kind: .creature)
        let lantern = Light(at: MapPoint(x: 300, y: 50), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue, goblin]
        appState.fog.lights = [lantern]
        appState.toggleSelection(pawn: goblin.id)
        appState.toggleSelection(light: lantern.id)

        appState.selectPawns(inside: CGRect(x: 0, y: 0, width: 100, height: 100), adding: false)

        XCTAssertEqual(appState.selection.pawnIDs, [rogue.id])
        XCTAssertEqual(appState.selection.lightIDs, [])
    }

    /// A Light inside the rectangle stays out of it: a Light joins only by ⇧-click.
    func testALightInsideTheRectangleIsNotPicked() {
        let appState = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let brazier = Light(at: MapPoint(x: 60, y: 60), brightSquares: 2, name: "brazier")
        appState.fog.pawns = [rogue]
        appState.fog.lights = [brazier]

        appState.selectPawns(inside: CGRect(x: 0, y: 0, width: 100, height: 100), adding: false)
        XCTAssertFalse(appState.selection.contains(light: brazier.id))

        appState.selectPawns(inside: CGRect(x: 0, y: 0, width: 100, height: 100), adding: true)
        XCTAssertFalse(appState.selection.contains(light: brazier.id))
    }

    /// A ⇧-rectangle adds: the Pawns inside join, and every member already picked — Light
    /// included — stays. A Pawn picked twice is not toggled back out.
    func testAShiftRectangleAddsToTheSelection() {
        let appState = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let fighter = pawn("Fighter", at: MapPoint(x: 70, y: 70))
        let goblin = pawn("Goblin", at: MapPoint(x: 300, y: 300), kind: .creature)
        let lantern = Light(at: MapPoint(x: 300, y: 50), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue, fighter, goblin]
        appState.fog.lights = [lantern]
        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(pawn: goblin.id)
        appState.toggleSelection(light: lantern.id)

        appState.selectPawns(inside: CGRect(x: 0, y: 0, width: 100, height: 100), adding: true)

        XCTAssertEqual(appState.selection.pawnIDs, [rogue.id, fighter.id, goblin.id])
        XCTAssertEqual(appState.selection.lightIDs, [lantern.id])
    }

    /// An empty plain rectangle ends the Selection, as a plain click on the bare Map does:
    /// the DM swept nothing, and a fresh pick of nothing is nothing picked.
    func testAnEmptyPlainRectangleClearsTheSelection() {
        let appState = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let lantern = Light(at: MapPoint(x: 60, y: 60), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue]
        appState.fog.lights = [lantern]
        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(light: lantern.id)

        appState.selectPawns(inside: CGRect(x: 200, y: 200, width: 50, height: 50),
                             adding: false)

        XCTAssertTrue(appState.selection.isEmpty)
    }

    /// An empty ⇧-rectangle changes nothing: the DM reaching for one more and missing, as a
    /// ⇧-click on the bare Map is.
    func testAnEmptyShiftRectangleKeepsTheSelection() {
        let appState = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        appState.fog.pawns = [rogue]
        appState.toggleSelection(pawn: rogue.id)

        appState.selectPawns(inside: CGRect(x: 200, y: 200, width: 50, height: 50),
                             adding: true)

        XCTAssertEqual(appState.selection.pawnIDs, [rogue.id])
    }

    // MARK: Map space

    /// The rectangle runs between where the drag began and where the pointer is, whichever
    /// way the DM dragged — up and to the left covers what down and to the right does.
    func testTheRectangleIsTheSameWhicheverWayItWasDragged() {
        let a = MapPoint(x: 10, y: 20), b = MapPoint(x: 110, y: 70)

        XCTAssertEqual(SelectionRectangle.mapRect(from: a, to: b),
                       CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(SelectionRectangle.mapRect(from: b, to: a),
                       CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    // MARK: Which drag draws one

    /// With nothing armed, a plain drag that starts on the bare Map draws the rectangle.
    func testAPlainDragOnTheBareMapWithNothingArmedDrawsARectangle() {
        XCTAssertTrue(SelectionRectangle.begins(isArmed: false, isOptionDown: false,
                                                startsOn: nil, isTokenDragging: false))
    }

    /// A drag that starts on a token is that token's drag — the Pawn or Light moves, and
    /// no rectangle is drawn over it.
    func testADragThatStartsOnATokenDrawsNoRectangle() {
        let rogue = pawn("Rogue", at: MapPoint(x: 50, y: 50))
        let lantern = Light(at: MapPoint(x: 60, y: 60), brightSquares: 4, name: "lantern")

        XCTAssertFalse(SelectionRectangle.begins(isArmed: false, isOptionDown: false,
                                                 startsOn: .pawn(rogue.id),
                                                 isTokenDragging: false))
        XCTAssertFalse(SelectionRectangle.begins(isArmed: false, isOptionDown: false,
                                                 startsOn: .light(lantern.id),
                                                 isTokenDragging: false))
    }

    /// A press on the rim of a token, dragged away from it: the token's own drag picks it
    /// up from the first point, and by the time this drag has gone far enough to decide, the
    /// token — or the whole Selection it belongs to — has already moved off the spot that
    /// was pressed. Asked of where the tokens stand now, that spot is the bare Map; but the
    /// drag is the token's, and draws no rectangle beside the move — nor, on release,
    /// replaces the Selection being carried.
    func testADragWhileATokenIsBeingDraggedDrawsNoRectangle() {
        XCTAssertFalse(SelectionRectangle.begins(isArmed: false, isOptionDown: false,
                                                 startsOn: nil, isTokenDragging: true))
    }

    /// With Add, a Measurement or the Viewport armed, the drag is what it was before there
    /// was a rectangle.
    func testADragWithSomethingArmedDrawsNoRectangle() {
        for (add, shape, measurement, viewport) in [(true, false, false, false),
                                                    (false, true, false, false),
                                                    (false, false, true, false),
                                                    (false, false, false, true)] {
            let isArmed = ArmedTool.State(hasArmedAdd: add, hasArmedShape: shape,
                                          hasMeasurement: measurement,
                                          isViewportArmed: viewport).isArmed
            XCTAssertFalse(SelectionRectangle.begins(isArmed: isArmed, isOptionDown: false,
                                                     startsOn: nil, isTokenDragging: false))
        }
    }

    /// ⌥-drag pans the Magnifier and never draws a rectangle. (The middle button never
    /// reaches a `DragGesture` at all — see `MiddleMouseDragModifier`.)
    func testAnOptionDragDrawsNoRectangle() {
        XCTAssertFalse(SelectionRectangle.begins(isArmed: false, isOptionDown: true,
                                                 startsOn: nil, isTokenDragging: false))
    }

    // MARK: Where the drag starts

    /// The token a drag starts on is asked of the token as drawn, in the view's points —
    /// the edge of a big token is the token, as it is to the Pawn's own drag. Drawn here at
    /// 1 point a pixel, 40 points a square.
    func testAPressOnATokensEdgeIsOnTheToken() {
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))

        // 18 points from the centre of a 40-point disc.
        XCTAssertEqual(token(under: CGPoint(x: 118, y: 100), pawns: [rogue]), .pawn(rogue.id))
    }

    /// A Light Marker is grabbed across a square's worth, not only its dot — so a press there
    /// is the marker's drag and draws no rectangle.
    func testAPressOnALightMarkersGrabAreaIsOnTheMarker() {
        let lantern = Light(at: MapPoint(x: 300, y: 300), brightSquares: 4, name: "lantern")

        XCTAssertEqual(token(under: CGPoint(x: 315, y: 300), lights: [lantern]),
                       .light(lantern.id))
    }

    /// The Pawn standing on a Light Marker is what is under the press — the one drawn on top.
    func testAPressOnAPawnStandingOnALightIsOnThePawn() {
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let brazier = Light(at: rogue.at, brightSquares: 2, name: "brazier")

        XCTAssertEqual(token(under: CGPoint(x: 100, y: 100), pawns: [rogue], lights: [brazier]),
                       .pawn(rogue.id))
    }

    func testAPressBesideEveryTokenIsOnTheBareMap() {
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let lantern = Light(at: MapPoint(x: 300, y: 300), brightSquares: 4, name: "lantern")

        XCTAssertNil(token(under: CGPoint(x: 200, y: 200), pawns: [rogue], lights: [lantern]))
    }

    private func token(under point: CGPoint, pawns: [Pawn] = [],
                       lights: [Light] = []) -> LiveHitTest? {
        // 800 pixels across 20 squares, drawn 800 points wide: 40 points a square.
        let map = MapScale(imagePixelSize: CGSize(width: 800, height: 600),
                           physicalWidthInches: 20)
        return PawnLayer.token(under: point, pawns: pawns, lights: lights, map: map,
                               frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    // MARK: Fixtures

    private func makeAppState() -> AppState {
        AppState(preferences: DisplayPreferences(
            defaults: UserDefaults(suiteName: "SelectionRectangleTests.\(UUID().uuidString)")!))
    }


    private func pawn(_ label: String, at point: MapPoint, kind: PawnKind = .player,
                      isBig: Bool = false) -> Pawn {
        Pawn(at: point, label: label, colorHex: Pawn.defaultColorHex, brightSquares: 6,
             kind: kind, isBig: isBig)
    }
}
