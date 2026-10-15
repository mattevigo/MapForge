import Foundation

/// What a Pawn's Face came from, when it came from a definition rather than the DM's hand: the
/// Monster it was taken from, or the Character that Stamped it.
enum FaceSource: Equatable {
    case monster(String)
    case character(UUID)

    /// What `pawn`'s Face came from: the Monster in its `monsterName` or the Character in its
    /// `characterID`, by the Face's own `from` — or nil for a Face cut by hand, or none.
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
        case .hand, nil:
            return nil
        }
    }

    /// The `from` a Face taken from this source carries.
    var origin: PawnFace.Origin {
        switch self {
        case .monster: .monster
        case .character: .character
        }
    }
}

/// Re-cutting a definition's Face for **every** Pawn that took it — the one exception to a
/// Face being a copy, and only ever the DM's doing (ADR-0028).
///
/// Pure, out of `AppState`, so which Pawns "every" reaches is proved without a Workspace: on
/// the open Map, those that took their Face from that very Monster or Character, and no
/// other. A Face the DM cut by hand stays theirs; a Pawn of another Monster is not this one's.
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
