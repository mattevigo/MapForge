import Foundation

/// What saying "this Treasure is that Item" copies onto the Pawn — kept out of the sheet and
/// out of `AppState`, as `MonsterStamp` is for a Creature, and a copy for the same reason
/// (ADR-0007, ADR-0020): nothing here reads the Treasury again afterwards.
///
/// An Item has no numbers, so there is no Stat Block to stamp and no healing to ask about.
enum ItemStamp {
    /// The label a Treasure takes on becoming `item`: "Bo1", "Bo2" for two Borse.
    ///
    /// `MonsterStamp`'s rule exactly: only the bare number the Pawn was born with, or the
    /// initials of the `previous` Item it was, is replaced; numbered one past the highest
    /// label of the same initials on the Map.
    static func label(for item: Item, replacing label: String, from previous: String? = nil,
                      among pawns: [Pawn]) -> String {
        MonsterStamp.label(named: item.name, replacing: label, from: previous, among: pawns)
    }

    /// The Face a Treasure wearing `current` has on becoming an Item whose Face is `itemFace`.
    ///
    /// `MonsterStamp`'s rule exactly: a Face an Item (or a Monster) gave is replaced — by the
    /// new Item's, or by nothing, which shows the colour again; one the DM cut by hand, or one
    /// a Character gave, is never touched; a Treasure with none takes the Item's.
    static func face(over current: PawnFace?, from itemFace: PawnFace?) -> PawnFace? {
        MonsterStamp.face(over: current, from: itemFace)
    }
}
