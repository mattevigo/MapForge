import XCTest
@testable import MapForge

/// Every word the app writes reaches every Interface Language (`CONTEXT.md`, **Interface
/// Language**). A string added in English only would show English to an Italian table without
/// anyone noticing, since the catalogue falls back to the source language silently; this is the
/// check that notices. It reads the catalogue itself, so it covers every string, not only those a
/// test happens to render.
final class StringCatalogueTests: XCTestCase {
    private struct Catalogue: Decodable {
        var strings: [String: Entry]
    }

    private struct Entry: Decodable {
        var shouldTranslate: Bool?
        var extractionState: String?
        var localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        var stringUnit: StringUnit?
        /// Plural or device variations: translated per case, checked by their own tests.
        var variations: [String: [String: Variation]]?
    }

    private struct Variation: Decodable {
        var stringUnit: StringUnit
    }

    private struct StringUnit: Decodable {
        var state: String
        var value: String
    }

    private func catalogue() throws -> Catalogue {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MapForge/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
    }

    /// The languages a translation is owed in: every Interface Language but the source.
    private var translatedLanguages: [String] {
        InterfaceLanguage.allCases.map(\.rawValue).filter { !$0.isEmpty && $0 != "en" }
    }

    /// The strings that are the app's words: not marked untranslatable (a bare "%@ — %@"), and
    /// not stale (no longer in the source).
    private func appStrings(_ catalogue: Catalogue) -> [(key: String, entry: Entry)] {
        catalogue.strings
            .filter { $0.value.shouldTranslate != false && $0.value.extractionState != "stale" }
            .map { (key: $0.key, entry: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func testEveryStringIsTranslatedInEveryInterfaceLanguage() throws {
        for (key, entry) in appStrings(try catalogue()) {
            for language in translatedLanguages {
                let localization = entry.localizations?[language]
                if let variations = localization?.variations {
                    for unit in variations.values.flatMap(\.values).map(\.stringUnit) {
                        XCTAssertEqual(unit.state, "translated", "\(language): \(key)")
                    }
                } else if let unit = localization?.stringUnit {
                    XCTAssertEqual(unit.state, "translated", "\(language): \(key)")
                    XCTAssertFalse(unit.value.isEmpty, "\(language): \(key)")
                } else {
                    XCTFail("\(language) has no translation: \(key)")
                }
            }
        }
    }

    func testEveryTranslationKeepsItsSourcesPlaceholders() throws {
        // A sentence whose translation drops or retypes a placeholder prints the wrong number,
        // or crashes, only in that language.
        for (key, entry) in appStrings(try catalogue()) {
            for language in translatedLanguages {
                // A plural substitution ("%#@creatures@") carries its placeholders in its
                // variations, which the plural tests prove.
                guard let value = entry.localizations?[language]?.stringUnit?.value,
                      !value.contains("%#@") else { continue }
                XCTAssertEqual(placeholders(in: value), placeholders(in: key), "\(language): \(key)")
            }
        }
    }

    /// The placeholders of `text` by position — "%@ has %lld" and "%2$lld … %1$@" both give
    /// ["@", "lld"].
    private func placeholders(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(lld|ld|d|@|(?:\.\d+)?f)"#)
        let range = NSRange(text.startIndex..., in: text)
        var byPosition: [Int: String] = [:]
        for (index, match) in pattern.matches(in: text, range: range).enumerated() {
            let position = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? index + 1
            byPosition[position] = Range(match.range(at: 2), in: text).map { String(text[$0]) }
        }
        return byPosition.sorted { $0.key < $1.key }.map(\.value)
    }
}
