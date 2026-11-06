import Foundation

/// What a Pawn's Face came from, when it came from a definition rather than the DM's hand: the
/// Monster or the Item it was taken from, or the Character that Stamped it.
enum FaceSource: Equatable {
    case monster(String)
    case character(UUID)
    case item(String)

    /// What `pawn`'s Face came from: the Monster in its `monsterName`, the Character in its
    /// `characterID` or the Item in its `itemName`, by the Face's own `from` — or nil for a
    /// Face cut by hand, or none.
    ///
    /// The one place those remembered fields decide anything beyond a page of reference and
    /// a count: which Pawns re-cutting a definition's Face reaches (ADR-0028).
    init?(of pawn: Pawn) {
        switch pawn.face?.origin {
        case .monster:
            guard let name = pawn.monsterName else { return nil }
            self = .monster(name)
        case .character:
            guard let id = pawn.characterID else { return nil }
            self = .character(id)
        case .item:
            guard let name = pawn.itemName else { return nil }
            self = .item(name)
        case .hand, nil:
            return nil
        }
    }

    /// The `from` a Face taken from this source carries.
    var origin: PawnFace.Origin {
        switch self {
        case .monster: .monster
        case .character: .character
        case .item: .item
        }
    }
}

/// Re-cutting a definition's Face for **every** Pawn that took it — the one exception to a
/// Face being a copy, and only ever the DM's doing (ADR-0028).
///
/// Pure, out of `AppState`, so which Pawns "every" reaches is proved without a Workspace: on
/// the open Map, those that took their Face from that very Monster, Character or
/// Item, and no other. A Face the DM cut by hand stays theirs; a Pawn of another Monster or
/// another Item is not this one's.
enum FaceRecut {
    /// `pawns` with every Pawn that took its Face from `source` wearing `file` instead —
    /// and `reCutting`, the Pawn the DM re-cut, whatever its Face was by the time OK was
    /// pressed: the new cut is the definition's, and so is that Pawn's Face.
    static func recut(_ pawns: [Pawn], from source: FaceSource, to file: String,
                      reCutting id: Pawn.ID? = nil) -> [Pawn] {
        pawns.map { pawn in
            guard pawn.id == id || FaceSource(of: pawn) == source else { return pawn }
            var recut = pawn
            recut.face = PawnFace(file: file, origin: source.origin)
            return recut
        }
    }
}

/// What OK asks before a re-cut of a definition's Face is kept: "only this Pawn, or every
/// one?" (ADR-0028), in the words of the Pawns "every" would reach — Treasures for an Item's
/// Face, which only a Treasure takes.
struct RecutQuestion: Equatable {
    /// The answer that keeps the cut for this Pawn alone.
    let onlyThis: String
    /// The answer that gives it to the definition — "Every Goblin".
    let every: String
    /// What "every" reaches.
    let message: String

    /// The question for a Face that came from `source`, still defined under `name`.
    init(_ source: FaceSource, named name: String) {
        every = String(localized: "Every \(name)")
        switch source {
        case .item:
            onlyThis = String(localized: "Only This Treasure")
            message = String(localized: "This Face came from \(name). Every Treasure on this Map wearing it, and every Treasure that becomes it later, can have the new cut.")
        case .monster, .character:
            onlyThis = String(localized: "Only This Pawn")
            message = String(localized: "This Face came from \(name). Every Pawn on this Map wearing it, and every Pawn that takes it later, can have the new cut.")
        }
    }
}
