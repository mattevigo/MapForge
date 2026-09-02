import SwiftUI
import XCTest
@testable import MapForge

final class PawnColorTests: XCTestCase {

    func testHexRoundTripsThroughAColor() throws {
        // A Pawn's colour survives being edited: parse to Color for the picker, write back
        // as hex. If this decayed, a Pawn would drift colour every time it was touched.
        for hex in ["#C81E1E", "#1E88C8", "#000000", "#FFFFFF", "#7F7F7F"] {
            let color = try XCTUnwrap(Color(hex: hex), "failed to parse \(hex)")
            XCTAssertEqual(color.hexString, hex)
        }
    }

    func testLowercaseAndMissingHashAreAccepted() {
        // Hand-edited fog files are meant to be readable and writable by a person.
        XCTAssertEqual(Color(hex: "c81e1e")?.hexString, "#C81E1E")
    }

    func testMalformedHexIsRejectedRatherThanGuessed() {
        // Returning nil shows the fallback colour; guessing would show a silent black disc.
        XCTAssertNil(Color(hex: "#12345"))
        XCTAssertNil(Color(hex: "not a colour"))
        XCTAssertNil(Color(hex: ""))
    }
}
