import AppKit
import SwiftUI

/// A Pawn as players and the DM both see it: a filled disc in its colour with its label — or,
/// when it has a Face, that Face filling the disc, with neither colour nor label over it
/// unless the DM's pointer rests on it.
///
/// One view shared by the Control Window preview and the Player Display, so a token can
/// never look like two different things on the two screens — the DM points at the red
/// circle and the players must be looking at the same red circle. A Face is read here, from
/// the environment's `FaceLibrary`, for the same reason: no surface can draw it differently.
struct PawnToken: View {
    let pawn: Pawn
    /// The side of ONE Grid square in the coordinate space of whichever surface is drawing
    /// it — not the token's own width. A Big Pawn spans two of these, and the view works
    /// that multiplication out itself.
    ///
    /// The distinction is load-bearing. Callers used to pre-multiply, which made "how big
    /// is this token's footprint" and "how big is this view" the same number: a Big Pawn's
    /// label then rendered at twice everyone else's point size, and its suppression floor
    /// was effectively halved. The disc scales with the footprint; the text does not.
    let squareSide: CGFloat
    var isSelected = false

    /// Whether the disc grows for a Big Pawn. False on chrome that is not the Map — the
    /// live row's tokens are fixed-size buttons, and doubling one there just makes that
    /// row taller than its neighbours without conveying anything the inspector does not.
    var scalesWithFootprint = true

    /// Whether this is the Player Display rather than the DM's own screen. Players get the
    /// bare disc — see `showsLabel(atDiameter:toPlayers:hasFace:isHovered:)`.
    var isForPlayers = false

    /// Whether the DM's pointer rests on this token. Brings a Face's label back on the
    /// Control Window, where four Goblins wearing one Face are otherwise identical; changes
    /// nothing for a Pawn without one, whose label is always there.
    var isHovered = false

    /// The disc's width: one square, or two for a Big Pawn on a surface that shows Maps.
    private var diameter: CGFloat {
        squareSide * (scalesWithFootprint ? pawn.squaresAcross : 1)
    }

    /// The token's outline: a disc for anyone who acts, a rounded square for Treasure.
    ///
    /// Shape rather than colour, because colour is already spoken for — a DM assigns it per
    /// token to tell one goblin from another, so it cannot also carry what a token *is*. A
    /// square reads as an object rather than a figure at a glance, which is the distinction
    /// that matters when the DM is pointing at the Map mid-fight.
    ///
    /// Rounded, not sharp: at the live row's 14 pt and at low map zoom a hard-cornered
    /// square reads as a stray pixel block, and the radius scales with the token so it
    /// stays the same shape at every size.
    private var outline: AnyShape { Self.outline(for: pawn.kind, diameter: diameter) }

    /// The outline a token of `kind` is drawn in at `diameter` — the one place the shapes
    /// live, so the Edit Pawn sheet's preview of a Face is the token it will make.
    static func outline(for kind: PawnKind, diameter: CGFloat) -> AnyShape {
        switch kind {
        case .player, .creature: return AnyShape(Circle())
        case .treasure: return AnyShape(RoundedRectangle(cornerRadius: diameter * 0.18))
        }
    }

    /// What shows through a Face's transparent parts on a token of `kind`. An Item's picture
    /// is usually an object on a transparent ground, so a Treasure's Face is drawn on white,
    /// never on the Map; anyone who acts keeps their Face's own ground. Shared with the Edit
    /// Pawn sheet's preview, like `outline(for:diameter:)`.
    static func faceGround(for kind: PawnKind) -> Color {
        switch kind {
        case .player, .creature: return .clear
        case .treasure: return .white
        }
    }

    /// Where the Pawn's Face is read from. Nil with no Workspace open.
    @Environment(\.faceLibrary) private var faceLibrary

    /// The kept cut this Pawn is drawn as, or nil to draw its colour — no Face, or one whose
    /// cut has gone missing, which costs the Pawn its picture and nothing else.
    private var faceImage: NSImage? {
        pawn.face.flatMap { faceLibrary?.image(for: $0) }
    }

    var body: some View {
        let face = faceImage
        ZStack {
            Group {
                if let face {
                    // The Face covers the whole token: no colour shows round it, and its
                    // shape is still the Kind's, so a chest's Face is still a square.
                    Image(nsImage: face)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .background(Self.faceGround(for: pawn.kind))
                        .clipShape(outline)
                } else {
                    outline.fill(Color(hex: pawn.colorHex) ?? .red)
                }
            }
            // A Pawn whose light is out is still on the Map — dimmed, not gone.
            .opacity(pawn.light.isOn ? 1 : 0.55)
            outline
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.6),
                        lineWidth: isSelected ? 3 : 1.5)
            // Sized from ONE square, so an ogre's "3" is the same size as a goblin's and
            // the legibility floor means the same thing for both.
            if Self.showsLabel(atDiameter: squareSide, toPlayers: isForPlayers,
                               hasFace: face != nil, isHovered: isHovered) {
                Text(pawn.label)
                    .font(.system(size: squareSide * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, squareSide * 0.1)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// Whether a token this size, on this screen, gets its label drawn.
    ///
    /// Three separate reasons a label is absent, answered in one place so no call site has
    /// to remember them all.
    ///
    /// **Who is looking.** The table gets the bare disc — `PlayerVisibility` holds that
    /// rule and the reasoning, beside everything else the players do and do not see. The
    /// disc's colour, size and shape are untouched, so the reason `PawnToken` is one shared
    /// view still holds: the DM points at the red circle and the players are looking at the
    /// same red circle.
    ///
    /// **Whether it could be read.** The threshold used to be 16 pt, above every floor the
    /// call sites apply (10-12 pt) — so at low zoom, or with no Grid declared, Pawns
    /// rendered as unlabelled coloured dots on the preview as well. That is the real
    /// defect behind "Pawns should have editable labels": they had them and could not be
    /// seen. The floor is where a one- or two-character label stops being readable at all
    /// rather than where it stops being comfortable — `minimumScaleFactor` lets the text
    /// shrink into the disc instead of vanishing from it. Below 8 pt the glyph is a couple
    /// of grey pixels that only muddy the disc's colour.
    ///
    /// **Whether a Face covers it.** The Face is what the table identifies the Pawn by, so
    /// no label is drawn over it — until the DM points at the token, because four Goblins
    /// wearing one Face cannot be told apart any other way. Only the DM's screen has a
    /// pointer; the table's rule above already keeps it silent.
    ///
    /// Defaults to the DM because three of the four call sites are DM chrome. The one
    /// screen that must stay silent is the one that says so.
    static func showsLabel(atDiameter diameter: CGFloat, toPlayers: Bool = false,
                           hasFace: Bool = false, isHovered: Bool = false) -> Bool {
        if toPlayers, !PlayerVisibility.showsPawnLabelToPlayers { return false }
        if hasFace, !isHovered { return false }
        return diameter >= 8
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

    /// The label a newly placed Pawn takes: one past the highest number already in use.
    ///
    /// Derived from the labels rather than from `pawns.count`, which reuses a number after
    /// a delete — place three, delete the second, and the next Pawn is "3" as well. Two
    /// tokens with one name mid-fight is exactly the confusion a label exists to prevent.
    /// Non-numeric labels are skipped, so renaming "2" to "Goblin B" frees the 2 rather
    /// than blocking the count.
    /// Saturates rather than trapping: the live rename field takes any text, so a DM can
    /// set a label of `Int.max` and the next placement would crash the app on overflow.
    static func nextLabel(after pawns: [Pawn]) -> String {
        let highest = pawns.compactMap { Int($0.label) }.max() ?? 0
        return "\(highest == Int.max ? highest : highest + 1)"
    }
}
