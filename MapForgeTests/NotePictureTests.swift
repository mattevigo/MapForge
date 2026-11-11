import XCTest
@testable import MapForge

/// Finding the picture a note's `image:` names among the Workspace's files — exactly, or not
/// at all. Obsidian's rules for choosing between two pictures of one name depend on settings
/// the app cannot see, so the app never chooses (ADR-0028).
final class NotePictureTests: XCTestCase {
    private let pictures = ["Riferimento/Allegati/Goblin.webp",
                            "Campagne/Eroi/Allegati/Goblin.webp",
                            "Riferimento/Allegati/Nothic.webp"]

    func testAPathQualifiedLinkNamesExactlyThatFile() {
        XCTAssertEqual(NotePicture.resolve("Campagne/Eroi/Allegati/Goblin.webp", among: pictures),
                       .found("Campagne/Eroi/Allegati/Goblin.webp"))
    }

    func testAPathQualifiedLinkToNothingIsMissing() {
        XCTAssertEqual(NotePicture.resolve("Mostri/Goblin.webp", among: pictures),
                       .missing(link: "Mostri/Goblin.webp"))
    }

    func testABareNameOneFileHasFindsThatFile() {
        XCTAssertEqual(NotePicture.resolve("Nothic.webp", among: pictures),
                       .found("Riferimento/Allegati/Nothic.webp"))
    }

    func testABareNameTwoFilesShareIsAmbiguous() {
        XCTAssertEqual(NotePicture.resolve("Goblin.webp", among: pictures),
                       .ambiguous(link: "Goblin.webp"))
    }

    func testABareNameNoFileHasIsMissing() {
        XCTAssertEqual(NotePicture.resolve("Wraith.webp", among: pictures),
                       .missing(link: "Wraith.webp"))
    }

    /// The Mac's own disks ignore case, and so does a link the DM typed.
    func testCaseIsIgnored() {
        XCTAssertEqual(NotePicture.resolve("nothic.WEBP", among: pictures),
                       .found("Riferimento/Allegati/Nothic.webp"))
    }

    func testOnlyAMissingOrAmbiguousPictureIsAProblem() {
        XCTAssertNil(NotePicture.found("Nothic.webp").problem)
        XCTAssertNotNil(NotePicture.missing(link: "Wraith.webp").problem)
        XCTAssertNotNil(NotePicture.ambiguous(link: "Goblin.webp").problem)
    }

    /// Obsidian writes the shortest path that is unique, so a link's folder may be only the
    /// last of several. It names the one file whose path ends so, and still never guesses.
    func testAPartialPathNamesTheOneFileWhosePathEndsSo() {
        XCTAssertEqual(NotePicture.resolve("Eroi/Allegati/Goblin.webp", among: pictures),
                       .found("Campagne/Eroi/Allegati/Goblin.webp"))
        XCTAssertEqual(NotePicture.resolve("Allegati/Goblin.webp", among: pictures),
                       .ambiguous(link: "Allegati/Goblin.webp"))
    }

    func testAPartialPathMatchesWholeFoldersOnly() {
        XCTAssertEqual(NotePicture.resolve("ati/Nothic.webp", among: pictures),
                       .missing(link: "ati/Nothic.webp"))
    }

    /// The formats a Map accepts, and so the formats a Face is cut from.
    func testAFileThatIsNoPNGJPEGOrWebPIsReportedAsSuch() {
        XCTAssertEqual(NotePicture.resolve("Scheda.pdf", among: ["Allegati/Scheda.pdf"]),
                       .notAPicture(link: "Scheda.pdf"))
        XCTAssertNotNil(NotePicture.notAPicture(link: "Scheda.pdf").problem)
    }
}
