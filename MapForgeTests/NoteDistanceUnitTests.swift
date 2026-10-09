import XCTest
@testable import MapForge

/// Which Distance Unit a note writes its distances in, read from its Speed and Senses alone
/// (ADR-0027) — the two fields every Monster's note has, short and predictable, where the
/// prose of an action is neither.
final class NoteDistanceUnitTests: XCTestCase {
    private func units(_ texts: String?...) -> Set<DistanceUnit> {
        DistanceUnit.named(in: texts)
    }

    func testAMetricSpeedIsMetres() {
        XCTAssertEqual(units("9 m"), [.metres])
        XCTAssertEqual(units("9m, scalare 6m"), [.metres])
        // How a hand-written Italian note abbreviates it, and German's dative plural.
        XCTAssertEqual(units("9 mt"), [.metres])
        XCTAssertEqual(units("Dunkelsicht 18 Metern"), [.metres])
    }

    func testOneSpeedNamingBothUnitsNamesBoth() {
        XCTAssertEqual(units("9 m, nuotare 30 ft"), [.metres, .feet])
    }

    func testAnImperialSpeedIsFeet() {
        XCTAssertEqual(units("30 ft."), [.feet])
        XCTAssertEqual(units("30 ft, fly 60 ft"), [.feet])
        XCTAssertEqual(units("30 feet"), [.feet])
    }

    func testTheWordsForFeetInEveryInterfaceLanguage() {
        for speed in ["30 piedi", "30 Fuß", "30 Fuss", "30 pieds", "30 pies", "30 pés", "30 πόδια"] {
            XCTAssertEqual(units(speed), [.feet], speed)
        }
    }

    func testTheWordsForMetresInEveryInterfaceLanguage() {
        for speed in ["9 metri", "9 metres", "9 meters", "9 Meter", "9 mètres", "9 metros",
                      "9 μέτρα", "1,5 m", "7.5 m"] {
            XCTAssertEqual(units(speed), [.metres], speed)
        }
    }

    func testSensesCountAsWellAsSpeed() {
        XCTAssertEqual(units("9 m", "scurovisione 60 ft"), [.metres, .feet])
        XCTAssertEqual(units(nil, "darkvision 60 ft., passive Perception 10"), [.feet])
    }

    func testANoteThatNamesNoUnitNamesNone() {
        XCTAssertEqual(units("camminare 9"), [])
        XCTAssertEqual(units(nil, nil), [])
        XCTAssertEqual(units("Percezione passiva 12"), [])
    }

    func testAWordThatOnlyStartsWithAUnitIsNotOne() {
        // "9 mani" is not nine metres, nor "30 feral" thirty feet.
        XCTAssertEqual(units("9 mani"), [])
        XCTAssertEqual(units("30 feral"), [])
    }
}

/// The notes flagged for being in the unit the Mac is not set to, and the switch offered when
/// every note that names a unit agrees on the other one (ADR-0027).
final class OtherUnitNotesTests: XCTestCase {
    private func monster(_ name: String, _ units: Set<DistanceUnit>) -> Monster {
        var monster = Monster(name: name)
        monster.distanceUnits = units
        monster.file = "Bestiario/\(name).md"
        return monster
    }

    func testOnlyNotesThatNameTheOtherUnitAreFlaggedAndMixedOnesAreAmongThem() {
        let notes = [monster("Gnoll", [.metres]),
                     monster("Ogre", [.feet]),
                     monster("Wraith", []),
                     monster("Sahuagin", [.metres, .feet])]

        let flagged = OtherUnitNotes(notes, current: .metres)

        XCTAssertEqual(flagged?.unit, .feet)
        XCTAssertEqual(flagged?.notes.map(\.name), ["Ogre", "Sahuagin"])
        XCTAssertEqual(flagged?.notes.map(\.file), ["Bestiario/Ogre.md", "Bestiario/Sahuagin.md"])
        XCTAssertEqual(flagged?.caption, "2 notes in feet")
    }

    func testNothingIsSaidWhenEveryNoteSpeaksTheUnitInForce() {
        let notes = [monster("Gnoll", [.metres]), monster("Wraith", [])]
        XCTAssertNil(OtherUnitNotes(notes, current: .metres))
    }

    func testOneNoteIsCountedInTheSingular() {
        XCTAssertEqual(OtherUnitNotes([monster("Gnoll", [.metres])], current: .feet)?.caption,
                       "1 note in metres")
    }

    func testTheReferencePageWarnsOnlyANoteInTheOtherUnit() {
        XCTAssertEqual(monster("Ogre", [.feet]).warning(current: .metres),
                       "This note gives distances in feet.")
        XCTAssertEqual(monster("Sahuagin", [.metres, .feet]).warning(current: .feet),
                       "This note gives distances in metres.")
        XCTAssertNil(monster("Gnoll", [.metres]).warning(current: .metres))
        XCTAssertNil(monster("Wraith", []).warning(current: .feet))
    }

    func testTheNotesAgreeOnlyWhenEveryUnitTheyNameIsTheSame() {
        XCTAssertEqual(DistanceUnit.agreed(by: [[.feet], [], [.feet]]), .feet)
        XCTAssertNil(DistanceUnit.agreed(by: [[.feet], [.metres]]))
        XCTAssertNil(DistanceUnit.agreed(by: [[.feet, .metres]]))
        XCTAssertNil(DistanceUnit.agreed(by: [[], []]))
    }
}
