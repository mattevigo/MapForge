import Foundation

/// The DM's reorder of the Scene tab's Pawns.
///
/// There is one order, not a list order beside a Map order: the Scene tab lists `fog.pawns`
/// as it stands, grouped by Kind, and the Map draws it in the same order — so a Pawn dragged
/// lower in its group is also drawn over its neighbours and wins a click where tokens overlap,
/// exactly as a newly placed Pawn, which lands at the bottom, always has. Add copies from the
/// last Pawn of a Kind, so it copies from the bottom of that group.
///
/// Pure, so where a row lands is decided where a test can reach it.
enum PawnOrder {
    /// `pawns` with `moving` taken to `target`'s place in their Kind's group: after it when
    /// dragged down, before it when dragged up, as a list's row does.
    ///
    /// Only that Kind's Pawns change places; every other Pawn keeps its index, so reordering
    /// the Players never changes which goblin stands over which. Nil when nothing is to move:
    /// the two are of different Kinds — the groups *are* the Kinds — or the same Pawn, or
    /// either is gone, which the list and the document can disagree about for a frame after a
    /// delete.
    static func move(_ moving: Pawn.ID, onto target: Pawn.ID, in pawns: [Pawn]) -> [Pawn]? {
        guard moving != target,
              let kind = pawns.first(where: { $0.id == moving })?.kind,
              pawns.first(where: { $0.id == target })?.kind == kind
        else { return nil }

        let slots = pawns.indices.filter { pawns[$0].kind == kind }
        var group = slots.map { pawns[$0] }
        guard let from = group.firstIndex(where: { $0.id == moving }),
              let to = group.firstIndex(where: { $0.id == target })
        else { return nil }
        // Removed first and inserted at the target's old index: that is after the target when
        // moving down, the target having shifted up one, and before it when moving up.
        group.insert(group.remove(at: from), at: to)

        var reordered = pawns
        for (slot, pawn) in zip(slots, group) { reordered[slot] = pawn }
        return reordered
    }

    /// Where `move` would put `moving`, for the line the Scene tab draws while the drag hovers
    /// over `target`: `.after` it when dragged down, `.before` it when dragged up, nil where
    /// the drop would be refused — so no line promises a drop that will not happen.
    static func landing(_ moving: Pawn.ID, onto target: Pawn.ID, in pawns: [Pawn]) -> Landing? {
        guard move(moving, onto: target, in: pawns) != nil,
              let from = pawns.firstIndex(where: { $0.id == moving }),
              let to = pawns.firstIndex(where: { $0.id == target })
        else { return nil }
        return from < to ? .after : .before
    }

    enum Landing: Equatable { case before, after }
}
