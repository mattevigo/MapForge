import AppKit
import XCTest
@testable import MapForge

/// Which Log a Roll lands in.
///
/// The rule under test is ADR-0014's: exactly one recorder is live at any instant, so the
/// button that records a Roll needs no `if` about fights. The Combat Log takes it while an
/// Encounter runs and the Session Log takes it the rest of the evening — never both, and
/// never neither.
@MainActor
final class RollRoutingTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RollRoutingTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.mapURL = mapURL
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        state.open(Workspace(url: directory))
        return state
    }

    private func pawn(_ label: String, kind: PawnKind = .player) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    private let save = Roll(d20: 16, modifier: 5, difficultyClass: 15)

    // MARK: During a fight

    func testARollDuringAFightGoesToTheCombatLog() {
        let state = makeAppState()
        let grix = pawn("Grix")
        state.fog.pawns = [grix]
        state.startSession()
        state.startEncounter()

        state.recordRoll(pawn: grix, ability: .dexterity, roll: save)

        let rolls = (state.encounter?.pendingChanges ?? []).filter {
            if case .savingThrow = $0 { return true } else { return false }
        }
        XCTAssertEqual(rolls.count, 1, "the Turn's Changes are where a Roll lands mid-fight")
    }

    /// The Session Log is silent for the fight's whole extent, so the same act writes there
    /// exactly zero times. Two records of one Roll is the drift ADR-0014 removes.
    func testARollDuringAFightIsNotAlsoInTheSessionLog() throws {
        let state = makeAppState()
        let grix = pawn("Grix")
        state.fog.pawns = [grix]
        state.startSession()
        state.startEncounter()

        state.recordRoll(pawn: grix, ability: .dexterity, roll: save)

        XCTAssertEqual(try sessionRolls(state).count, 0,
                       "exactly one recorder is live at any instant")
    }

    /// A Roll is often made by someone who is not in the Order at all — the NPC in the
    /// corner, the players' contact, a Creature the DM has benched. It still records.
    func testAPawnOutsideTheOrderCanStillRollDuringAFight() {
        let state = makeAppState()
        let grix = pawn("Grix")
        let bystander = pawn("Innkeeper", kind: .creature)
        state.fog.pawns = [grix, bystander]
        state.startSession()
        state.startEncounter()
        // Out of the Order, still on the Map — a Creature the DM has set aside.
        state.benchCombatant(bystander.id)

        state.recordRoll(pawn: bystander, skill: .persuasion,
                         roll: Roll(d20: 12, modifier: 7, difficultyClass: 15))

        let rolls = (state.encounter?.pendingChanges ?? []).filter {
            if case .abilityCheck = $0 { return true } else { return false }
        }
        XCTAssertEqual(rolls.count, 1,
                       "a Roll is about the Pawn, not about whose Turn it is")
    }

    // MARK: Outside a fight

    func testARollOutsideAFightGoesToTheSessionLog() throws {
        let state = makeAppState()
        let grix = pawn("Grix")
        state.fog.pawns = [grix]
        state.startSession()

        state.recordRoll(pawn: grix, ability: .dexterity, roll: save)

        XCTAssertEqual(try sessionRolls(state).count, 1)
        XCTAssertNil(state.encounter, "precondition: no fight is running")
    }

    /// After the fight ends the Session Log has it back.
    func testARollAfterAFightEndsGoesToTheSessionLogAgain() throws {
        let state = makeAppState()
        let grix = pawn("Grix")
        state.fog.pawns = [grix]
        state.startSession()
        state.startEncounter()
        state.stopEncounter()

        state.recordRoll(pawn: grix, ability: .wisdom, roll: Roll(d20: 8, modifier: 1))

        XCTAssertEqual(try sessionRolls(state).count, 1)
    }

    /// With no Session running there is nowhere to write, and that is not a crash.
    func testARollWithNoSessionRecordsNothingAndDoesNotCrash() {
        let state = makeAppState()
        let grix = pawn("Grix")
        state.fog.pawns = [grix]

        state.recordRoll(pawn: grix, ability: .dexterity, roll: save)

        XCTAssertNil(state.session)
    }

    // MARK: Reading the Session Log back

    /// The Rolls in the Session Log this AppState is writing, read back off disk.
    ///
    /// Read through the writer's own url rather than by listing the folder: a test that
    /// picks `files.first` is reading whichever file the filesystem happened to name first.
    private func sessionRolls(_ state: AppState) throws -> [SessionLine] {
        guard let url = state.sessionWriter?.url else { return [] }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try? SessionLogFile.decoder().decode(SessionLine.self,
                                                               from: Data($0.utf8)) }
            .filter {
                switch $0 {
                case .savingThrow, .abilityCheck: true
                default: false
                }
            }
    }
}
