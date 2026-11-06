import AppKit
import XCTest
@testable import MapForge

/// Re-cutting a Face that came from a Monster, a Character or an Item: whether the Edit Pawn sheet asks
/// "only this Pawn, or every one?", and which Pawns "every" reaches — the one exception to a
/// Face being a copy, and only ever the DM's doing (ADR-0028).
@MainActor
final class FaceRecutTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FaceRecutTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private let durgaID = UUID()

    private func creature(_ label: String, monster: String? = "Goblin",
                          face: PawnFace? = PawnFace(file: "goblin.png", origin: .monster)) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, monsterName: monster, face: face)
    }

    private func player(characterID: UUID?, face: PawnFace?) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: "Durga", colorHex: "#C81E1E",
             brightSquares: 6, kind: .player, characterID: characterID, face: face)
    }

    private func picture() throws -> CGImage {
        try FaceFixture.halves(width: 300, height: 100)
    }

    // MARK: The draft

    func testReCuttingStartsFromTheSquareItWasCutAs() throws {
        var face = FaceDraft(PawnFace(file: "goblin.png", origin: .monster))

        face.recut(try picture(), from: CGRect(x: 20, y: 0, width: 80, height: 80))

        XCTAssertEqual(face.newCut?.cut, CGRect(x: 20, y: 0, width: 80, height: 80))
        XCTAssertTrue(face.isRecut)
    }

    func testAnotherPictureIsNoReCut() throws {
        var face = FaceDraft(PawnFace(file: "goblin.png", origin: .monster))
        face.recut(try picture(), from: CGRect(x: 20, y: 0, width: 80, height: 80))

        face.choosePicture(try picture())

        XCTAssertFalse(face.isRecut)
    }

    // MARK: Whether OK asks

    func testReCuttingAMonstersFaceAsks() throws {
        var draft = EditPawnDraft(pawn: creature("GG1"))
        draft.face.recut(try picture(), from: CGRect(x: 0, y: 0, width: 50, height: 50))

        XCTAssertEqual(draft.recutSource, .monster("Goblin"))
        XCTAssertTrue(draft.asksWhomToRecut)
    }

    /// The Monster's picture is the one its note names. Another one is this Pawn's alone.
    func testAnotherPictureForAMonstersFaceDoesNotAsk() throws {
        var draft = EditPawnDraft(pawn: creature("GG1"))
        draft.face.choosePicture(try picture())

        XCTAssertFalse(draft.asksWhomToRecut)
    }

    func testAnyNewCutOfACharactersFaceAsks() throws {
        var draft = EditPawnDraft(pawn: player(characterID: durgaID,
                                               face: PawnFace(file: "d.png", origin: .character)))
        draft.face.choosePicture(try picture())

        XCTAssertEqual(draft.recutSource, .character(durgaID))
        XCTAssertTrue(draft.asksWhomToRecut)
    }

    func testAFaceCutByHandReCutsWithoutAsking() throws {
        var draft = EditPawnDraft(pawn: creature("GG1", face: PawnFace(file: "mine.png",
                                                                       origin: .hand)))
        draft.face.choosePicture(try picture())

        XCTAssertNil(draft.recutSource)
        XCTAssertFalse(draft.asksWhomToRecut)
    }

    func testNothingCutAsksNothing() {
        XCTAssertFalse(EditPawnDraft(pawn: creature("GG1")).asksWhomToRecut)
    }

    // MARK: Which Pawns "every" reaches

    func testEveryReachesThePawnsThatTookTheFaceFromThatMonsterAlone() {
        let goblins = [creature("GG1"), creature("GG2")]
        let handCut = creature("GG3", face: PawnFace(file: "mine.png", origin: .hand))
        let ogre = creature("Og1", monster: "Ogre", face: PawnFace(file: "ogre.png", origin: .monster))
        let colour = creature("GG4", face: nil)

        let recut = FaceRecut.recut(goblins + [handCut, ogre, colour], from: .monster("Goblin"),
                                    to: "new.png")

        XCTAssertEqual(recut.map(\.face?.file), ["new.png", "new.png", "mine.png", "ogre.png", nil])
        XCTAssertEqual(recut[0].face?.origin, .monster)
    }

    func testEveryReachesThePawnsStampedFromThatCharacterAlone() {
        let durga = player(characterID: durgaID, face: PawnFace(file: "d.png", origin: .character))
        let other = player(characterID: UUID(), face: PawnFace(file: "o.png", origin: .character))
        let handCut = player(characterID: durgaID, face: PawnFace(file: "mine.png", origin: .hand))

        let recut = FaceRecut.recut([durga, other, handCut], from: .character(durgaID),
                                    to: "new.png")

        XCTAssertEqual(recut.map(\.face?.file), ["new.png", "o.png", "mine.png"])
        XCTAssertEqual(recut[0].face?.origin, .character)
    }

    /// The Pawn the DM re-cut takes the new cut as the definition's, even when its own Face
    /// was removed in the sheet before the new picture was chosen.
    func testThePawnReCutForEveryOneKeepsItsSource() {
        let durga = player(characterID: durgaID, face: nil)

        let recut = FaceRecut.recut([durga], from: .character(durgaID), to: "new.png",
                                    reCutting: durga.id)

        XCTAssertEqual(recut[0].face, PawnFace(file: "new.png", origin: .character))
    }

    func testAPawnsSourceIsTheDefinitionItsFaceCameFrom() {
        XCTAssertEqual(FaceSource(of: creature("GG1")), .monster("Goblin"))
        XCTAssertEqual(FaceSource(of: player(characterID: durgaID,
                                             face: PawnFace(file: "d.png", origin: .character))),
                       .character(durgaID))
        XCTAssertNil(FaceSource(of: creature("GG1", face: PawnFace(file: "m.png", origin: .hand))))
        XCTAssertNil(FaceSource(of: creature("GG1", monster: nil)))
    }

    /// A Treasure's Face from its Item is that Item's, by the name the Treasure remembers.
    func testATreasuresSourceIsTheItemItsFaceCameFrom() {
        let borsa = Pawn(at: MapPoint(x: 100, y: 100), label: "Bo1", colorHex: "#D4A017",
                         brightSquares: 0, kind: .treasure, itemName: "Borsa",
                         face: PawnFace(file: "borsa.png", origin: .item))
        var forgotten = borsa
        forgotten.itemName = nil

        XCTAssertEqual(FaceSource(of: borsa), .item("Borsa"))
        XCTAssertEqual(FaceSource.item("Borsa").origin, .item)
        XCTAssertNil(FaceSource(of: forgotten))
    }

    // MARK: OK

    /// An open Workspace whose Goblin's note names a picture, cut once, with three Goblins on
    /// the Map — two wearing the Monster's Face, one cut by hand.
    private func makeGoblins() async throws -> (AppState, Workspace, [Pawn]) {
        let folder = root.appendingPathComponent("Eroi")
        try fileManager.createDirectory(at: folder.appendingPathComponent("Allegati"),
                                        withIntermediateDirectories: true)
        let workspace = try WorkspaceStore().adopt(folder)
        try FaceFixture.writePNG(try picture(),
                                 to: folder.appendingPathComponent("Allegati/Goblin.png"))
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.open(workspace)
        await state.bestiaryLoad?.value
        var goblin = Monster(name: "Goblin", armorClass: 15, hitPoints: 7)
        goblin.picture = .found("Allegati/Goblin.png")
        state.bestiary = Bestiary(monsters: [goblin, Monster(name: "Ogre", hitPoints: 59)])
        state.mapURL = folder.appendingPathComponent("dungeon.png")
        let face = try XCTUnwrap(state.monsterFace(for: goblin))
        let pawns = [creature("GG1", face: face), creature("GG2", face: face),
                     creature("GG3", face: PawnFace(file: "mine.png", origin: .hand))]
        state.fog.pawns = pawns
        return (state, workspace, pawns)
    }

    private func recutDraft(of pawn: Pawn, in state: AppState) throws -> EditPawnDraft {
        var draft = EditPawnDraft(pawn: pawn)
        let source = try XCTUnwrap(state.recutPicture(for: try XCTUnwrap(FaceSource(of: pawn))))
        draft.face.recut(source.picture, from: source.cut)
        draft.face.setCut(CGRect(x: 0, y: 0, width: 60, height: 60))
        return draft
    }

    func testReCuttingStartsFromTheMonstersPictureAndSquare() async throws {
        let (state, _, pawns) = try await makeGoblins()

        let source = try XCTUnwrap(state.recutPicture(for: .monster("Goblin")))

        XCTAssertEqual(source.picture.width, 300)
        XCTAssertEqual(source.cut, CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertNil(FaceSource(of: pawns[2]), "a hand cut keeps no picture")
    }

    func testEveryChangesTheMonstersCutAndEveryPawnOnTheMapThatTookIt() async throws {
        let (state, workspace, pawns) = try await makeGoblins()
        var draft = try recutDraft(of: pawns[0], in: state)
        draft.recutsEvery = true

        state.updatePawn(id: pawns[0].id, with: draft)

        let cut = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .monsters["Goblin"])
        XCTAssertEqual(cut.square, CGRect(x: 0, y: 0, width: 60, height: 60))
        XCTAssertEqual(state.fog.pawns.map(\.face?.file), [cut.file, cut.file, "mine.png"])
        XCTAssertEqual(state.fog.pawns[0].face?.origin, .monster)
        // And the Pawns that take the Face afterwards.
        XCTAssertEqual(state.monsterFace(for: try XCTUnwrap(state.bestiary.monster(named: "Goblin")))?.file,
                       cut.file)
    }

    func testOnlyThisPawnChangesThatPawnAloneAndMakesItHandCut() async throws {
        let (state, workspace, pawns) = try await makeGoblins()
        let before = NoteFacesStore(directory: workspace.supportDirectory).load()

        state.updatePawn(id: pawns[0].id, with: try recutDraft(of: pawns[0], in: state))

        XCTAssertEqual(state.fog.pawns[0].face?.origin, .hand)
        XCTAssertEqual(state.fog.pawns[1].face, pawns[1].face)
        XCTAssertEqual(NoteFacesStore(directory: workspace.supportDirectory).load(), before)
    }

    func testAPawnReCutForItselfKeepsItsFaceOnBecomingAnotherMonster() async throws {
        let (state, _, pawns) = try await makeGoblins()
        state.updatePawn(id: pawns[0].id, with: try recutDraft(of: pawns[0], in: state))
        let own = state.fog.pawns[0].face

        var ogre = EditPawnDraft(pawn: state.fog.pawns[0])
        ogre.pick(try XCTUnwrap(state.bestiary.monster(named: "Ogre")), among: state.fog.pawns)
        state.updatePawn(id: pawns[0].id, with: ogre)

        XCTAssertEqual(state.fog.pawns[0].face, own)
    }

    func testEveryChangesTheCharactersOwnFaceAndItsPawnsOnTheMap() async throws {
        let (state, _, _) = try await makeGoblins()
        state.addParty(named: "Eroi")
        state.addCharacter(PartyCharacter(id: durgaID, name: "Durga",
                                          face: PawnFace(file: "d.png", origin: .hand)))
        let stamped = [player(characterID: durgaID, face: PawnFace(file: "d.png", origin: .character)),
                       player(characterID: durgaID, face: PawnFace(file: "d.png", origin: .character))]
        state.fog.pawns = stamped
        var draft = EditPawnDraft(pawn: stamped[0])
        draft.face.choosePicture(try picture())
        draft.recutsEvery = true

        state.updatePawn(id: stamped[0].id, with: draft)

        let own = try XCTUnwrap(state.activeParty?.characters.first?.face)
        XCTAssertNotEqual(own.file, "d.png")
        XCTAssertEqual(own.origin, .hand)
        XCTAssertEqual(state.fog.pawns.map(\.face?.file), [own.file, own.file])
        XCTAssertEqual(state.fog.pawns.map(\.face?.origin), [.character, .character])
    }

    /// Nothing is kept before OK: opening the picture again and moving the square writes no
    /// file and changes no Pawn, which is what lets the sheet's Cancel discard a re-cut whole.
    func testAReCutKeepsNothingUntilOK() async throws {
        let (state, workspace, pawns) = try await makeGoblins()
        let before = try fileManager.contentsOfDirectory(atPath: workspace.facesDirectory.path)

        var draft = try recutDraft(of: pawns[0], in: state)
        draft.recutsEvery = true
        _ = draft   // the sheet closes without OK

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: workspace.facesDirectory.path),
                       before)
        XCTAssertEqual(state.fog.pawns, pawns)
    }

    func testOnlyAFaceCutFromANotesPictureCanBeReCut() async throws {
        let (state, _, pawns) = try await makeGoblins()

        XCTAssertTrue(state.canRecut(.monster("Goblin")))
        XCTAssertFalse(state.canRecut(.monster("Ogre")), "its note names no picture")
    }

    func testEveryIsOfferedUnderTheNameOfADefinitionStillThere() async throws {
        let (state, _, _) = try await makeGoblins()

        XCTAssertEqual(state.recutName(for: .monster("Goblin")), "Goblin")
        XCTAssertNil(state.recutName(for: .monster("Wraith")))
        XCTAssertNil(state.recutName(for: .character(UUID())))
    }

    // MARK: Re-cutting what the sheet shows now

    /// A Pawn with no Face that takes its Monster's in the sheet can cut that square at once.
    func testAFaceTakenInTheSheetCanBeReCutAtOnce() async throws {
        let (state, workspace, _) = try await makeGoblins()
        let pawn = creature("GG4", face: nil)
        state.fog.pawns = [pawn]
        let goblin = try XCTUnwrap(state.bestiary.monster(named: "Goblin"))
        var draft = EditPawnDraft(pawn: pawn)
        XCTAssertNil(draft.recutSource)

        draft.takeMonsterFace(try XCTUnwrap(state.monsterFace(for: goblin)), of: goblin.name)
        let source = try XCTUnwrap(draft.recutSource)
        let picture = try XCTUnwrap(state.recutPicture(for: source))
        draft.face.recut(picture.picture, from: picture.cut)
        draft.face.setCut(CGRect(x: 0, y: 0, width: 60, height: 60))
        draft.recutsEvery = true
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertTrue(draft.asksWhomToRecut)
        let cut = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .monsters["Goblin"])
        XCTAssertEqual(cut.square, CGRect(x: 0, y: 0, width: 60, height: 60))
        XCTAssertEqual(state.fog.pawns[0].face, PawnFace(file: cut.file, origin: .monster))
    }

    /// The note now names another picture: re-cutting opens that one, from its centre, never
    /// the picture the old cut was made from.
    func testReCuttingOpensThePictureTheNoteNamesNow() async throws {
        let (state, workspace, _) = try await makeGoblins()
        try FaceFixture.writePNG(try FaceFixture.halves(width: 200, height: 100),
                                 to: workspace.url.appendingPathComponent("Allegati/Goblin-nuovo.png"))
        var goblin = try XCTUnwrap(state.bestiary.monster(named: "Goblin"))
        goblin.picture = .found("Allegati/Goblin-nuovo.png")
        state.bestiary = Bestiary(monsters: [goblin])

        let picture = try XCTUnwrap(state.recutPicture(for: .monster("Goblin")))

        XCTAssertEqual(picture.picture.width, 200)
        XCTAssertEqual(picture.cut, CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    // MARK: An Item's Face

    private func treasure(_ label: String, item: String? = "Borsa", face: PawnFace?) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#D4A017",
             brightSquares: 0, kind: .treasure, itemName: item, face: face)
    }

    /// An open Workspace whose Borsa's note names a picture, cut once, with four Treasures on
    /// the Map — two wearing the Borsa's Face, one cut by hand, one a Corda's — and a Goblin
    /// wearing its Monster's.
    private func makeBorse() async throws -> (AppState, Workspace, [Pawn]) {
        let (state, workspace, goblins) = try await makeGoblins()
        try FaceFixture.writePNG(try picture(),
                                 to: workspace.url.appendingPathComponent("Allegati/Borsa.png"))
        var borsa = Item(name: "Borsa")
        borsa.picture = .found("Allegati/Borsa.png")
        state.treasury = Treasury(items: [borsa, Item(name: "Corda")])
        let face = try XCTUnwrap(state.itemFace(for: borsa))
        let pawns = [treasure("Bo1", face: face), treasure("Bo2", face: face),
                     treasure("Bo3", face: PawnFace(file: "mine.png", origin: .hand)),
                     treasure("Co1", item: "Corda", face: PawnFace(file: "corda.png", origin: .item)),
                     goblins[0]]
        state.fog.pawns = pawns
        return (state, workspace, pawns)
    }

    func testEveryChangesTheItemsCutAndEveryTreasureOnTheMapThatTookIt() async throws {
        let (state, workspace, pawns) = try await makeBorse()
        var draft = try recutDraft(of: pawns[0], in: state)
        draft.recutsEvery = true

        state.updatePawn(id: pawns[0].id, with: draft)

        let cut = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .items["Borsa"])
        XCTAssertEqual(cut.square, CGRect(x: 0, y: 0, width: 60, height: 60))
        XCTAssertEqual(state.fog.pawns.map(\.face?.file),
                       [cut.file, cut.file, "mine.png", "corda.png", pawns[4].face?.file])
        XCTAssertEqual(state.fog.pawns[0].face?.origin, .item)
    }

    func testATreasureThatBecomesTheItemAfterwardsTakesTheNewCut() async throws {
        let (state, workspace, pawns) = try await makeBorse()
        var draft = try recutDraft(of: pawns[0], in: state)
        draft.recutsEvery = true
        state.updatePawn(id: pawns[0].id, with: draft)
        let chest = treasure("1", item: nil, face: nil)
        state.fog.pawns.append(chest)

        var becoming = EditPawnDraft(pawn: chest)
        becoming.pick(try XCTUnwrap(state.treasury.item(named: "Borsa")), among: state.fog.pawns)
        state.updatePawn(id: chest.id, with: becoming)

        let cut = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .items["Borsa"])
        XCTAssertEqual(state.fog.pawns.last?.face, PawnFace(file: cut.file, origin: .item))
    }

    func testOnlyThisTreasureChangesThatTreasureAloneAndLeavesTheItemsCut() async throws {
        let (state, workspace, pawns) = try await makeBorse()
        let before = NoteFacesStore(directory: workspace.supportDirectory).load()

        state.updatePawn(id: pawns[0].id, with: try recutDraft(of: pawns[0], in: state))

        XCTAssertEqual(state.fog.pawns[0].face?.origin, .hand)
        XCTAssertNotEqual(state.fog.pawns[0].face?.file, pawns[0].face?.file)
        XCTAssertEqual(Array(state.fog.pawns.dropFirst()), Array(pawns.dropFirst()))
        XCTAssertEqual(NoteFacesStore(directory: workspace.supportDirectory).load(), before)
    }

    func testReCuttingAnItemsFaceAsksAndStartsFromItsPictureAndSquare() async throws {
        let (state, _, pawns) = try await makeBorse()

        let draft = try recutDraft(of: pawns[0], in: state)
        let source = try XCTUnwrap(state.recutPicture(for: .item("Borsa")))

        XCTAssertEqual(draft.recutSource, .item("Borsa"))
        XCTAssertTrue(draft.asksWhomToRecut)
        XCTAssertEqual(source.picture.width, 300)
        XCTAssertEqual(source.cut, CGRect(x: 100, y: 0, width: 100, height: 100))
    }

    /// Another picture over an Item's Face is this Treasure's alone, as over a Monster's.
    func testAnotherPictureForAnItemsFaceDoesNotAsk() async throws {
        let (_, _, pawns) = try await makeBorse()
        var draft = EditPawnDraft(pawn: pawns[0])
        draft.face.choosePicture(try picture())

        XCTAssertFalse(draft.asksWhomToRecut)
    }

    func testOnlyAnItemWhoseNoteNamesAPictureCanBeReCutForEveryOne() async throws {
        let (state, _, _) = try await makeBorse()

        XCTAssertTrue(state.canRecut(.item("Borsa")))
        XCTAssertFalse(state.canRecut(.item("Corda")), "its note names no picture")
        XCTAssertEqual(state.recutName(for: .item("Borsa")), "Borsa")
        XCTAssertNil(state.recutName(for: .item("Gemma di Fuoco")), "gone from the notes")
    }

    // MARK: What OK asks

    func testOKAsksAboutAMonstersFaceInTermsOfPawns() {
        let question = RecutQuestion(.monster("Goblin"), named: "Goblin")

        XCTAssertEqual(question.onlyThis, "Only This Pawn")
        XCTAssertEqual(question.every, "Every Goblin")
        XCTAssertEqual(question.message, "This Face came from Goblin. Every Pawn on this Map wearing it, and every Pawn that takes it later, can have the new cut.")
    }

    func testOKAsksAboutAnItemsFaceInTermsOfTreasures() {
        let question = RecutQuestion(.item("Borsa"), named: "Borsa")

        XCTAssertEqual(question.onlyThis, "Only This Treasure")
        XCTAssertEqual(question.every, "Every Borsa")
        XCTAssertEqual(question.message, "This Face came from Borsa. Every Treasure on this Map wearing it, and every Treasure that becomes it later, can have the new cut.")
    }

    func testACharactersOwnFaceKeepsNoPictureToReCut() async throws {
        let (state, _, _) = try await makeGoblins()
        state.addParty(named: "Eroi")
        state.addCharacter(PartyCharacter(id: durgaID, name: "Durga",
                                          face: PawnFace(file: "d.png", origin: .hand)))

        XCTAssertFalse(state.canRecut(.character(durgaID)))
    }
}
