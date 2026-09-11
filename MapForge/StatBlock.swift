import Foundation

/// A Pawn's combat numbers: what it takes to hit it, how hurt it is, and what it is
/// suffering from.
///
/// Kept beside the Map but never inside the fog file — see
/// `docs/adr/0009-combat-state-lives-outside-the-fog-document.md`. Nothing in
/// `<map>.fog.json` needs to know an ogre has 59 hit points, and a DM sharing a map with
/// its Walls traced is sharing prep work, not their party's wounds.
///
/// One shape for Players and Creatures alike, temporary hit points included. The two
/// differ in what a DM habitually tracks, not in what the rules permit.
struct StatBlock: Codable, Equatable {
    /// Added to a d20 when the Encounter starts.
    var initiativeBonus: Int = 0

    var armorClass: Int = StatBlock.defaultArmorClass

    /// Optional because a Creature stamped and not yet filled in has none, and zero is a
    /// meaningful value that must not stand in for absent: a Combatant at 0 is
    /// unconscious, a Combatant with no number typed yet is waiting for the DM.
    var currentHP: Int?

    var maxHP: Int?

    /// Not optional: absent temporary hit points are zero, and the rules give no meaning
    /// to "unknown".
    var temporaryHP: Int = 0

    var conditions: Set<Condition> = []

    /// Exhaustion is deliberately not a `Condition`: it is a level from 0 to 6, and a set
    /// of booleans cannot hold a level. Clamped on write — there is no seventh level, and
    /// a 6 that crept to 7 would be a number the rules cannot answer questions about.
    var exhaustion: Int = 0 {
        didSet { exhaustion = Self.clampExhaustion(exhaustion) }
    }

    /// Not a Condition, and not rendered as one. It is the single most-forgotten thing at
    /// a table, and it is one boolean.
    var isConcentrating: Bool = false

    static let defaultArmorClass = 10
    static let maximumExhaustion = 6

    /// Whether the DM has given this Combatant the numbers a fight needs. An incomplete
    /// Stat Block never keeps a Pawn out of the Order — it is flagged in the tracker and
    /// joins anyway, because a forgotten stat block must not silently drop a monster from
    /// the fight.
    var isComplete: Bool { currentHP != nil && maxHP != nil }

    init(initiativeBonus: Int = 0,
         armorClass: Int = StatBlock.defaultArmorClass,
         currentHP: Int? = nil,
         maxHP: Int? = nil,
         temporaryHP: Int = 0,
         conditions: Set<Condition> = [],
         exhaustion: Int = 0,
         isConcentrating: Bool = false) {
        self.initiativeBonus = initiativeBonus
        self.armorClass = armorClass
        self.currentHP = currentHP
        self.maxHP = maxHP
        self.temporaryHP = temporaryHP
        self.conditions = conditions
        self.exhaustion = Self.clampExhaustion(exhaustion)
        self.isConcentrating = isConcentrating
    }

    private static func clampExhaustion(_ level: Int) -> Int {
        min(max(level, 0), maximumExhaustion)
    }

    /// Hand-written so decoding goes through the initializer, which clamps. The
    /// synthesized decoder assigns stored properties directly, so it fires neither
    /// `didSet` nor the initializer — and `stats.json` is a file a DM can open and edit,
    /// so an out-of-range level arrives from disk as easily as from the editor.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            initiativeBonus: try container.decodeIfPresent(Int.self, forKey: .initiativeBonus) ?? 0,
            armorClass: try container.decodeIfPresent(Int.self, forKey: .armorClass)
                ?? StatBlock.defaultArmorClass,
            currentHP: try container.decodeIfPresent(Int.self, forKey: .currentHP),
            maxHP: try container.decodeIfPresent(Int.self, forKey: .maxHP),
            temporaryHP: try container.decodeIfPresent(Int.self, forKey: .temporaryHP) ?? 0,
            conditions: try container.decodeIfPresent(Set<Condition>.self, forKey: .conditions) ?? [],
            exhaustion: try container.decodeIfPresent(Int.self, forKey: .exhaustion) ?? 0,
            isConcentrating: try container.decodeIfPresent(Bool.self, forKey: .isConcentrating) ?? false
        )
    }
}
