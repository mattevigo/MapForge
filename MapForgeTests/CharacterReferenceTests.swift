import XCTest
@testable import MapForge

/// What the Combat tab shows of a Character while its Pawn fights: the note's own words,
/// found through the Character the Pawn was Stamped from (ADR-0007, amended).
final class CharacterReferenceTests: XCTestCase {
    /// Durga's fence as DM Realm writes it, cut down to a few of each.
    private let durga = """
    ```statblock
    layout: DM Realm Character
    name: Durga Pietraferma
    species: Umano
    class: Chierico (Dominio dell'Inganno)
    level: 5
    player: Baldu
    ac: 14
    hp: 48
    hit_dice: 5d8
    initiative: -1
    speed: 9 metri
    stats: [11, 8, 18, 12, 17, 12]
    saves:
      - Forza: 0
      - Saggezza ●: 6
    skillsaves:
      - Arcano: 7
    senses: Scurovisione 18 metri, Percezione Passiva 21
    languages: Comune, Nanico
    actions:
      - name: Mazza
        desc: "+3 al tiro per colpire, portata 1,5 metri, 1d6 danni Contundenti"
    spells:
      - "Saggezza, CD del tiro salvezza degli incantesimi 14, +6 al tiro per colpire con incantesimi"
      - 1° livello: 4 slot
      - 2° livello: 3 slot
    traits:
      - name: Intraprendente
        desc: "Ottiene Ispirazione Eroica ogni volta che completa un Riposo Lungo."
    ```
    """

    private func note(_ markdown: String) throws -> CharacterNote {
        guard case .fields(let fields) = StatblockReader.fields(in: markdown),
              case .character(let note) = StatblockReader.character(from: fields)
        else { return try XCTUnwrap(nil, "not read as a Character's note") }
        return note
    }

    // MARK: Reading the page

    func testTheNotesPageIsReadBesideItsNumbers() throws {
        let note = try note(durga)
        XCTAssertEqual(note.species, "Umano")
        XCTAssertEqual(note.characterClass, "Chierico (Dominio dell'Inganno)")
        XCTAssertEqual(note.level, "5")
        XCTAssertEqual(note.speed, "9 metri")
        XCTAssertEqual(note.saves, [.init(name: "Forza", bonus: 0), .init(name: "Saggezza ●", bonus: 6)])
        XCTAssertEqual(note.skills, [.init(name: "Arcano", bonus: 7)])
        XCTAssertEqual(note.senses, "Scurovisione 18 metri, Percezione Passiva 21")
        XCTAssertEqual(note.languages, "Comune, Nanico")
        XCTAssertEqual(note.actions.map(\.name), ["Mazza"])
        XCTAssertEqual(note.traits.map(\.name), ["Intraprendente"])
    }

    func testSpellsAreTheNotesLinesInOrder() throws {
        // YAML reads `- 1° livello: 4 slot` as a map of one key, not as the line it looks like.
        XCTAssertEqual(try note(durga).spells, [
            "Saggezza, CD del tiro salvezza degli incantesimi 14, +6 al tiro per colpire con incantesimi",
            "1° livello: 4 slot",
            "2° livello: 3 slot",
        ])
    }

    func testWhatIsNotALineInSpellsIsLeftOut() throws {
        let odd = """
        ```statblock
        name: Test
        level: 1
        spells:
          - 14
          - [Dardo, Scudo]
          - Saggezza: 3
            Intelligenza: 1
          - "CD 12"
        ```
        """
        XCTAssertEqual(try note(odd).spells, ["CD 12"])
    }

    // MARK: The page

    func testOnlyWhatTheNoteHasIsListedAndNeverItsArmourOrHitPoints() {
        // The Stat Block editor above shows the Pawn's own, which are the ones true now.
        let note = CharacterNote(name: "Test", armorClass: 14, maxHP: 48, speed: "9 metri",
                                 languages: "Comune")
        XCTAssertEqual(CharacterReference.lines(of: note).map(\.label), ["Speed", "Languages"])
    }

    func testAProficientSaveKeepsTheNotesMark() {
        var note = CharacterNote(name: "Test")
        note.saves = [.init(name: "Forza", bonus: 0), .init(name: "Saggezza ●", bonus: 6)]
        note.skills = [.init(name: "Arcano", bonus: 7)]
        let lines = CharacterReference.lines(of: note)
        XCTAssertEqual(lines.first { $0.label == "Saves" }?.value, "Forza +0, Saggezza ● +6")
        XCTAssertEqual(lines.first { $0.label == "Skills" }?.value, "Arcano +7")
    }

    func testTheHeadingSaysWhoTheCharacterIsWithWhatTheNoteHas() throws {
        XCTAssertEqual(CharacterReference.heading(of: try note(durga)),
                       "Umano · Chierico (Dominio dell'Inganno) · Level 5")
        XCTAssertEqual(CharacterReference.heading(of: CharacterNote(name: "Test", characterClass: "Mago")),
                       "Mago")
        XCTAssertEqual(CharacterReference.heading(of: CharacterNote(name: "Test")), "")
    }

    func testTheGroupsAreTraitsActionsSpellsAndTheEmptyOnesAreDropped() throws {
        XCTAssertEqual(CharacterReference.groups(of: try note(durga)).map(\.title),
                       ["Traits", "Actions", "Spells"])

        var fighter = CharacterNote(name: "Test")
        fighter.actions = [.init(name: "Spadone", desc: "")]
        XCTAssertEqual(CharacterReference.groups(of: fighter).map(\.title), ["Actions"])
    }

    func testSpellsArePlainLinesAndTheRestAreFeatures() throws {
        let groups = CharacterReference.groups(of: try note(durga))
        XCTAssertEqual(groups.first { $0.title == "Actions" }?.paragraphs,
                       [.feature(.init(name: "Mazza",
                                       desc: "+3 al tiro per colpire, portata 1,5 metri, 1d6 danni Contundenti"))])
        XCTAssertEqual(groups.first { $0.title == "Spells" }?.paragraphs.last, .plain("2° livello: 3 slot"))
    }

    // MARK: Finding the page

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterReference.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A Workspace whose notes are read, with Durga in the active Party.
    @MainActor
    private func workspaceWithDurga(linked: Bool = true) throws -> (AppState, PartyCharacter) {
        let state = AppState(preferences: DisplayPreferences(defaults: .standard),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.bestiary = Bestiary()
        state.characterNotes = CharacterNotes(notes: [try note(durga)])
        state.addParty(named: "Lost Boys")
        state.addCharacter(PartyCharacter(name: "Durga",
                                          noteName: linked ? "Durga Pietraferma" : nil))
        return (state, try XCTUnwrap(state.activeParty?.characters.first))
    }

    private func pawn(of character: PartyCharacter?) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "Durga", colorHex: "#FF0000",
             brightSquares: 6, characterID: character?.id)
    }

    @MainActor
    func testAPawnFindsItsCharactersPageThroughItsCharacter() throws {
        let (state, durga) = try workspaceWithDurga()
        XCTAssertEqual(state.characterPage(for: pawn(of: durga)), .note(try note(self.durga)))
    }

    @MainActor
    func testAnUnlinkedCharacterSaysSoAndLinkingItReachesThePawnAlreadyPlaced() throws {
        let (state, durga) = try workspaceWithDurga(linked: false)
        let placed = pawn(of: durga)
        XCTAssertEqual(state.characterPage(for: placed), .unlinked(characterName: "Durga"))

        var linked = durga
        linked.link(to: try note(self.durga))
        state.updateCharacter(linked)
        XCTAssertEqual(state.characterPage(for: placed), .note(try note(self.durga)),
                       "no new Stamp: the page is looked up, not copied")
    }

    @MainActor
    func testANoteThatHasGoneIsNamed() throws {
        let (state, durga) = try workspaceWithDurga()
        state.characterNotes = CharacterNotes()
        XCTAssertEqual(state.characterPage(for: pawn(of: durga)),
                       .missing(noteName: "Durga Pietraferma"))
    }

    @MainActor
    func testWhileTheNotesAreReadThePageSaysSoRatherThanThatTheNoteIsGone() throws {
        let (state, durga) = try workspaceWithDurga()
        state.bestiary = .reading
        state.characterNotes = CharacterNotes()
        XCTAssertEqual(state.characterPage(for: pawn(of: durga)),
                       .unavailable("Reading the Bestiary…"))
    }

    @MainActor
    func testAPawnWithNoCharacterHasNoPage() throws {
        let (state, durga) = try workspaceWithDurga()
        XCTAssertNil(state.characterPage(for: pawn(of: nil)), "a Player placed by hand")

        let placed = pawn(of: durga)
        state.deleteCharacter(id: durga.id)
        XCTAssertNil(state.characterPage(for: placed), "a deleted Character loses a page and nothing else")
    }
}
