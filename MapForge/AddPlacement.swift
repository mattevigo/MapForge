import CoreGraphics

/// What `Add` puts on the Map, and what it inherits from what is already there.
///
/// Pure policy, out of the view for the reason `LiveHitTest` is: the inheritance table is a
/// rule a DM meets six times in a row while stocking an encounter, and it should be provable
/// without driving a window.
///
/// Inheritance is the whole point. A DM populating an encounter places six goblins, and each
/// one arriving with the wrong colour, size or sight is a correction they have to notice and
/// make — six chances to miss one and light the room with it. It is **per Kind** rather than
/// per Pawn: a DM's Creatures and Players are differently coloured, so following whatever was
/// placed most recently would drag a goblin's green onto a party member.
enum AddPlacement {
    /// A new Pawn of `kind` at `point`, or nil when the point is outside the image.
    ///
    /// Refused rather than clamped, exactly as `Stamp` refuses a drop outside: a Pawn beyond
    /// the implicit Walls is meaningless to Visibility and unreachable on the clipped mirror,
    /// and landing it at the edge would put it where the DM did not point. The caller stays
    /// armed so the next click can simply be better aimed.
    ///
    /// `imageSize` nil skips the bounds check, for callers that have no image loaded to
    /// check against.
    static func pawn(kind: PawnKind, at point: MapPoint, existing: [Pawn],
                     imageSize: CGSize? = nil) -> Pawn? {
        guard isInside(point, imageSize) else { return nil }
        // The last of this Kind, not the last placed. See the type's note.
        let previous = existing.last { $0.kind == kind }
        return Pawn(at: point,
                    label: Pawn.nextLabel(after: existing),
                    colorHex: previous?.colorHex ?? Pawn.defaultColorHex,
                    brightSquares: previous?.light.brightSquares ?? defaultSightSquares,
                    kind: kind,
                    isBig: previous?.isBig ?? false)
    }

    /// A new Light at `point`, or nil when the point is outside the image.
    ///
    /// Refused on the same rule as a Pawn. An asymmetry was tried here — a Light outside the
    /// image lights nothing the players can see, so it reads as harmless — but it is not:
    /// `LiveHitTest` only reaches what the DM can click, so a Light out there could never be
    /// selected, edited or deleted again. Unreachable is the same problem for both, and one
    /// rule is easier to rely on than two.
    static func light(at point: MapPoint, existing: [Light],
                      imageSize: CGSize? = nil) -> Light? {
        guard isInside(point, imageSize) else { return nil }
        let previous = existing.last
        return Light(at: point,
                     brightSquares: previous?.brightSquares ?? defaultBrightSquares,
                     // The stored dim, never `bright * 2` — a DM who set dim equal to bright
                     // on the last torch meant it, and placing the next one is not the moment
                     // to undo that.
                     dimSquares: previous?.dimSquares,
                     // Deliberately not inherited: a doused torch is a live state, not a kind
                     // of torch. Inheriting it would have a DM who doused one place invisible
                     // Lights ever after.
                     isOn: true,
                     name: Light.nextName(after: existing))
    }

    /// Matches `PartyCharacter.defaultSightSquares`, so a hand-placed Pawn and a Stamped one
    /// do not drift apart.
    static let defaultSightSquares: CGFloat = 6

    /// A torch: 20 ft bright is 4 Grid squares. Dim follows `Light`'s own default of twice
    /// bright, the 5e convention.
    static let defaultBrightSquares: CGFloat = 4

    private static func isInside(_ point: MapPoint, _ imageSize: CGSize?) -> Bool {
        guard let imageSize else { return true }
        return point.x >= 0 && point.y >= 0
            && point.x <= imageSize.width && point.y <= imageSize.height
    }
}
