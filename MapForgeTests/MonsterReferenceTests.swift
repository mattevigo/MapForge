import XCTest
@testable import MapForge

/// What the Combat tab shows of a Monster while it fights: the note's own words, made
/// presentable and nothing more.
final class MonsterReferenceTests: XCTestCase {
    // MARK: A description

    func testWikilinksAreFlattenedToWhatTheDMWouldRead() {
        // Obsidian's links mean nothing outside Obsidian, and `[[` mid-sentence is noise.
        XCTAssertEqual(MonsterReference.plain("attacca con [[Squartare]]."),
                       "attacca con Squartare.")
        XCTAssertEqual(MonsterReference.plain("secondo il [[Tomo_del_Ferro]]"),
                       "secondo il Tomo del Ferro")
        XCTAssertEqual(MonsterReference.plain("vedi [[03_Bestiario/Lich|il Lich]] e [[Wraith#Azioni]]"),
                       "vedi il Lich e Wraith")
    }

    func testEmphasisIsRenderedRatherThanShown() {
        let text = MonsterReference.attributed("*Colpito:* 5 danni, **terreno difficile**.")
        XCTAssertEqual(String(text.characters), "Colpito: 5 danni, terreno difficile.")
    }

    func testTextThatIsNotValidMarkdownIsShownAsWritten() {
        // Never blank: a description the parser dislikes is still the description.
        XCTAssertEqual(String(MonsterReference.attributed("5 * 3 [oops").characters), "5 * 3 [oops")
    }

    // MARK: The lines above the actions

    func testOnlyWhatTheNoteHasIsListed() {
        let monster = Monster(name: "Test", armorClass: 15, hitPoints: 27, speed: "9 m",
                              challengeRating: "1/2")
        XCTAssertEqual(MonsterReference.lines(of: monster).map(\.label), ["Speed", "CR"])
    }

    func testSavesAndSkillsReadAsSignedBonuses() {
        var monster = Monster(name: "Test")
        monster.saves = [.init(name: "Des", bonus: 3), .init(name: "Sag", bonus: -1)]
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        let lines = MonsterReference.lines(of: monster)
        XCTAssertEqual(lines.first { $0.label == "Saves" }?.value, "Des +3, Sag −1")
        XCTAssertEqual(lines.first { $0.label == "Skills" }?.value, "Furtività +6")
    }

    func testTheGroupsKeepTheBooksOrderAndDropTheEmptyOnes() {
        var monster = Monster(name: "Test")
        monster.reactions = [.init(name: "Parata", desc: "")]
        monster.actions = [.init(name: "Morso", desc: "")]
        XCTAssertEqual(MonsterReference.groups(of: monster).map(\.title), ["Actions", "Reactions"])
    }
}
