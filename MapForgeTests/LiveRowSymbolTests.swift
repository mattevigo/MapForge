import AppKit
import XCTest
@testable import MapForge

/// Every SF Symbol the live row names must actually exist on the running system.
///
/// `Image(systemName:)` renders an empty frame for a name that does not resolve, with no
/// warning and no crash — so `person.viewfinder`, which has only a `.fill` variant, shipped
/// as a row of blank buttons and was caught by eye rather than by the suite. A symbol name
/// is data the app depends on, and this is the cheapest place to hold it down.
final class LiveRowSymbolTests: XCTestCase {
    func testEveryLiveRowSymbolResolves() {
        let names = ["eye", "eye.slash",                  // hide from the Player Display
                     "binoculars", "binoculars.fill",     // Solo Sight
                     "flame", "flame.fill",               // a Light\'s switch
                     "tv", "tv.slash",                    // the Player Display's state
                     "exclamationmark.triangle.fill"]     // the undeclared-Grid warning
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(name) does not resolve — it will render as an empty button")
        }
    }
}
