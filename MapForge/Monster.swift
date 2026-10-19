import Foundation

/// A kind of creature as the DM's notes define it — a Gnoll Guerriero, a Wraith.
///
/// A definition, not a token: never on a Map and never wounded. It stands to a Creature as a
/// `PartyCharacter` stands to a Player's Pawn, and is taken the same way — by copy
/// (`MonsterStamp`, ADR-0020). Unlike a Character it is never authored here: the only place a
/// Monster is written is the DM's own notes, which is why this type has no `Codable` and no
/// store that saves one.
///
/// Two halves. The three optional numbers are what a Stamp copies into a Stat Block, and they
/// are optional because a hand-written note may simply lack one — such a Monster is still
/// offered and stamps what it has. Everything else is text the DM reads mid-fight, kept as
/// the note wrote it: the app never computes with a speed or a sense.
struct Monster: Equatable, Identifiable {
    /// What the DM searches for, and what a Pawn remembers. Unique within a `Bestiary`.
    var name: String

    var armorClass: Int?
    /// The book's average. `hitDice` is carried for the DM to read and never rolled.
    var hitPoints: Int?
    var initiativeBonus: Int?
    /// Large and up — a 2×2 token. See `StatblockReader.isBig(size:)`.
    var isBig = false

    var size: String?
    var type: String?
    var alignment: String?
    var hitDice: String?
    var speed: String?
    var senses: String?
    var languages: String?
    var challengeRating: String?
    var source: String?
    var saves: [Proficiency] = []
    var skills: [Proficiency] = []
    var damageVulnerabilities: String?
    var damageResistances: String?
    var damageImmunities: String?
    var conditionImmunities: String?

    var traits: [Feature] = []
    var actions: [Feature] = []
    var bonusActions: [Feature] = []
    var reactions: [Feature] = []
    var legendaryActions: [Feature] = []

    /// The note it was read from, relative to the Workspace root — so a DM told that a
    /// Monster is written in the other unit can find the note to change.
    var file = ""
    /// The Distance Units its Speed and Senses name — none, one or both — read once with the
    /// rest of the note, never again on a redraw (ADR-0027).
    var distanceUnits: Set<DistanceUnit> = []
    /// The picture the fence's `image:` links to, as the link names it — "Nothic.webp",
    /// "Riferimento/Allegati/Goblin.webp" — or nil when it names none (ADR-0028).
    var imageLink: String?
    /// That picture found among the Workspace's files, or why it was not. Nil with no
    /// `image:`. What the Monster's Face is cut from.
    var picture: NotePicture?

    var id: String { name }

    /// One named thing a Monster can do or is: a trait, an action, a reaction.
    ///
    /// `desc` is the note's own markdown, wikilinks and all. Making it presentable is the
    /// reference view's job, so the reading stays a reading.
    struct Feature: Equatable {
        var name: String
        var desc: String
    }

    /// A save or a skill the Monster is good at, as the note names it — "Saggezza ●",
    /// "Furtività", "constitution". Kept as written for the reference page; the Roll sheet
    /// matches it onto an `Ability` or `Skill` by its rulebook name when it offers a Modifier,
    /// and a name that matches nothing offers nothing (ADR-0029).
    struct Proficiency: Equatable {
        var name: String
        var bonus: Int
    }
}
