import AppKit
import SwiftUI

/// A Pawn as players and the DM both see it: a filled disc in its colour with its label.
///
/// One view shared by the Control Window preview and the Player Display, so a token can
/// never look like two different things on the two screens — the DM points at the red
/// circle and the players must be looking at the same red circle.
struct PawnToken: View {
    let pawn: Pawn
    /// Diameter in the coordinate space of whichever surface is drawing it. Sized in Grid
    /// squares by the caller, so a token reads as occupying its square.
    let diameter: CGFloat
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: pawn.colorHex) ?? .red)
                // A Pawn whose light is out is still on the Map — dimmed, not gone.
                .opacity(pawn.light.isOn ? 1 : 0.55)
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.6),
                        lineWidth: isSelected ? 3 : 1.5)
            if diameter >= 16 {
                // Below this the label is unreadable and only muddies the disc's colour,
                // which is the thing a player actually identifies a token by.
                Text(pawn.label)
                    .font(.system(size: diameter * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, diameter * 0.1)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

extension Color {
    /// `#RRGGBB`, the form a Pawn's colour is stored in — a string so the fog file stays
    /// portable and readable, per `FogDocument`. Returns nil on anything malformed rather
    /// than guessing, so a bad value shows as the fallback instead of a silent black disc.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension Color {
    /// `#RRGGBB` for storage, from whatever the colour picker produced. Falls back to the
    /// default rather than writing an unparseable value into the fog file — the round trip
    /// through `Color(hex:)` has to be closed, or a Pawn's colour would decay each edit.
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return Pawn.defaultColorHex
        }
        let r = Int((components.redComponent * 255).rounded())
        let g = Int((components.greenComponent * 255).rounded())
        let b = Int((components.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Pawn {
    /// The colour a newly placed Pawn takes when there is no previous one to copy.
    static let defaultColorHex = "#C81E1E"
}
