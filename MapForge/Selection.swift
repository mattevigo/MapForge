import Foundation

/// The **Selection**: the Pawns and Lights the DM has picked in the Live View, so that one
/// drag moves them all (`CONTEXT.md`, **Selection**).
///
/// A value of IDs and nothing else — never a copy of a Pawn or a Light. The document is the
/// truth about where each one stands, and a Selection that held positions would be a second
/// copy of them to drift; it says only *which*.
///
/// Two sets rather than one set of some either-type, because the two kinds are picked by
/// different rules — a rectangle picks Pawns only, a Light joins only by its own ⇧-click — and
/// the rules read most plainly when each kind has its own set to act on.
///
/// Never saved: not in the fog document, not in the sidecar, not in any Log. A Selection is a
/// way of acting, not a thing in the record.
struct Selection: Equatable {
    private(set) var pawnIDs: Set<Pawn.ID> = []
    private(set) var lightIDs: Set<Light.ID> = []

    var isEmpty: Bool { pawnIDs.isEmpty && lightIDs.isEmpty }

    func contains(pawn id: Pawn.ID) -> Bool { pawnIDs.contains(id) }
    func contains(light id: Light.ID) -> Bool { lightIDs.contains(id) }

    /// Whether the token — a Pawn or a Light Marker — is a member.
    func contains(_ token: LiveHitTest) -> Bool {
        switch token {
        case .pawn(let id): return contains(pawn: id)
        case .light(let id): return contains(light: id)
        }
    }

    /// ⇧-click on a Pawn: in if it was out, out if it was in.
    mutating func toggle(pawn id: Pawn.ID) {
        if pawnIDs.remove(id) == nil { pawnIDs.insert(id) }
    }

    /// ⇧-click on a Light Marker — the only way a Light joins.
    mutating func toggle(light id: Light.ID) {
        if lightIDs.remove(id) == nil { lightIDs.insert(id) }
    }

    /// A plain rectangle on the bare Map: the Pawns inside it become the whole Selection. Any
    /// Light goes too — a rectangle never picks one, and replacing means nothing is kept.
    mutating func replace(withPawns ids: some Sequence<Pawn.ID>) {
        pawnIDs = Set(ids)
        lightIDs = []
    }

    /// A ⇧-rectangle: the Pawns inside join, and every member already picked stays — a
    /// Pawn the rectangle covers twice is not toggled back out.
    mutating func add(pawns ids: some Sequence<Pawn.ID>) {
        pawnIDs.formUnion(ids)
    }

    /// This Selection without any member that is no longer on the Map — a deleted Pawn or
    /// Light leaves, and everything else stays picked.
    func keepingOnly(pawns: Set<Pawn.ID>, lights: Set<Light.ID>) -> Selection {
        var kept = self
        kept.pawnIDs.formIntersection(pawns)
        kept.lightIDs.formIntersection(lights)
        return kept
    }
}
