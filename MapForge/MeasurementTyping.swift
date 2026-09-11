import CoreGraphics
import Foundation

/// Typing a distance while a Measurement is armed: type `9`, press Return, get a 9 m
/// projection aimed where the mouse points.
///
/// The decision of whether a keystroke belongs to this feature is a **pure function**,
/// deliberately. It goes through a process-global `NSEvent` monitor — SwiftUI focus does
/// not reach these overlays — and `DeleteKey` exists in its current shape because such a
/// monitor once ate ⌫ from a text field and deleted a Wall mid-word. Digits collide with
/// far more than ⌫ does, so the three gates are stated here where they can be tested
/// without driving a window.
enum MeasurementTyping {
    /// What a keystroke means. `passThrough` is the default and the safe one: anything not
    /// positively claimed goes back to AppKit untouched.
    enum Decision: Equatable {
        case passThrough
        case digit(Character)
        case backspace
        case commit
        case abandon
    }

    /// The three gates, all of which must open before a key is claimed:
    ///
    /// - `isArmed` — a Measurement exists. Much narrower than `DeleteKey`'s always-on
    ///   monitor: this is live only in a state the DM entered deliberately.
    /// - `isInFrame` — the cursor is over the Map, scoped as `ScrollWheel` scopes rather
    ///   than as `DeleteKey` does, because the Control Window is full of other controls.
    /// - `isEditingText` — nothing is taking text input. The gate `DeleteKey` learned the
    ///   hard way; a DM typing into "Grid squares wide" must not also be sizing a cone.
    static func decide(for key: Character, isArmed: Bool, isInFrame: Bool,
                       isEditingText: Bool) -> Decision {
        guard isArmed, isInFrame, !isEditingText else { return .passThrough }
        switch key {
        case "0"..."9": return .digit(key)
        case "\u{7F}", "\u{F728}": return .backspace
        case "\r", "\u{3}": return .commit
        case "\u{1B}": return .abandon
        default: return .passThrough
        }
    }

    /// The digits typed so far.
    struct Buffer: Equatable {
        private(set) var text = ""

        /// A stuck key must not build a distance with more digits than any Map has squares.
        static let maxDigits = 4

        var isEmpty: Bool { text.isEmpty }

        var value: CGFloat? {
            guard let value = Double(text) else { return nil }
            return CGFloat(value)
        }

        mutating func append(_ digit: Character) {
            guard text.count < Self.maxDigits else { return }
            // A leading zero says nothing and makes "0" look like a distance.
            guard !(text.isEmpty && digit == "0") else { return }
            text.append(digit)
        }

        mutating func backspace() {
            guard !text.isEmpty else { return }
            text.removeLast()
        }

        mutating func clear() { text = "" }

        /// The typed distance in Grid squares.
        ///
        /// Deliberately **not** snapped, unlike a dragged distance: you typed it, you meant
        /// it — and the common metric distances are not whole numbers of 1.5 m squares.
        func squares(in unit: DistanceUnit) -> CGFloat? {
            guard let value, value > 0 else { return nil }
            return unit.squares(fromDisplay: value)
        }
    }
}
