import AppKit
import XCTest
@testable import MapForge

/// The Page's red text is read on its own page at WCAG AA, 4.5:1 for normal text, in light
/// mode and dark — the colours read from the asset catalogue the DM tunes them in.
final class PageContrastTests: XCTestCase {
    func testTheHeadingColourIsReadableOnThePageInBothSchemes() throws {
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            XCTAssertGreaterThanOrEqual(try contrast("PageHeading", on: "PageSurface", in: scheme),
                                        4.5, "\(scheme.rawValue)")
        }
    }

    func testTheNameAndRulesColourIsReadableOnThePageInBothSchemes() throws {
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            XCTAssertGreaterThanOrEqual(try contrast("PageAccent", on: "PageSurface", in: scheme),
                                        4.5, "\(scheme.rawValue)")
        }
    }

    /// WCAG 2's contrast ratio between two named colours as `scheme` resolves them.
    private func contrast(_ text: String, on page: String,
                          in scheme: NSAppearance.Name) throws -> Double {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme))
        let lighter = max(try luminance(text, appearance), try luminance(page, appearance))
        let darker = min(try luminance(text, appearance), try luminance(page, appearance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ name: String, _ appearance: NSAppearance) throws -> Double {
        let named = try XCTUnwrap(NSColor(named: name), "\(name) is not in the asset catalogue")
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = named.usingColorSpace(.sRGB)
        }
        let color = try XCTUnwrap(resolved)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}
