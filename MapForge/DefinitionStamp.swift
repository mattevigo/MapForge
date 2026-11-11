import Foundation

/// What saying "this Pawn is that definition" — a Creature a Monster, a Treasure an Item —
/// does to its label and its Face. One rule for both, kept out of the sheet and out of
/// `AppState` so it can be proved without either, and a **copy** (ADR-0007, ADR-0020): nothing
/// here reads the notes again afterwards.
///
/// What only a Monster brings, its numbers, is `MonsterStamp`'s. An Item has none.
enum DefinitionStamp {
    // MARK: The label

    /// The label a Pawn takes on becoming the definition called `name`: "GG1", "GG2" for two
    /// Gnoll Guerrieri, "Bo1", "Bo2" for two Borse.
    ///
    /// Only a label the app gave is replaced: the bare number the Pawn was born with
    /// (`Pawn.nextLabel`), or the one a `previous` definition gave it — "GG1" on a Gnoll
    /// Guerriero the DM is making an Ogre. Anything else is something the DM typed, and is
    /// theirs. Numbered one past the highest label of the same initials on the Map, whatever
    /// definition it belongs to: Gnoll Guerriero and Goblin Guerriero share "GG" and share one
    /// run of numbers, because what a label is *for* in the Order is telling two rows apart.
    static func label(named name: String, replacing label: String, from previous: String? = nil,
                      among pawns: [Pawn]) -> String {
        guard Int(label) != nil || isLabel(label, givenBy: previous) else { return label }
        let prefix = initials(of: name)
        guard !prefix.isEmpty else { return label }
        let highest = pawns.compactMap { pawn -> Int? in
            guard pawn.label.hasPrefix(prefix) else { return nil }
            return Int(pawn.label.dropFirst(prefix.count))
        }.max() ?? 0
        return "\(prefix)\(highest + 1)"
    }

    /// Whether `label` is one the definition called `name` would have given: its initials and
    /// a number.
    static func isLabel(_ label: String, givenBy name: String?) -> Bool {
        guard let name else { return false }
        let prefix = initials(of: name)
        guard !prefix.isEmpty, label.hasPrefix(prefix) else { return false }
        return Int(label.dropFirst(prefix.count)) != nil
    }

    /// The first letter of each word, capitalised — or the first two letters of a name that
    /// is one word, because "W1" is too thin to read at a glance. Punctuation is stepped
    /// over, so "(antica)" gives A and "d'Ossa" gives D.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
        guard words.count != 1 else {
            let word = words[0]
            return word.prefix(1).uppercased() + word.dropFirst().prefix(1).lowercased()
        }
        return words.map { $0.prefix(1).uppercased() }.joined()
    }

    // MARK: The Face

    /// The Face a Pawn wearing `current` has on becoming a definition whose Face is `given`.
    ///
    /// A Face the Pawn took from a Monster or an Item is the app's, and is replaced — by the
    /// new definition's, or by nothing, which shows the colour again — exactly as a label
    /// taken from the old one's initials is. One the DM cut by hand, or one a Character gave,
    /// is the DM's and is never touched. A Pawn with none takes the definition's.
    static func face(over current: PawnFace?, from given: PawnFace?) -> PawnFace? {
        switch current?.origin {
        case .hand, .character: return current
        case .monster, .item, nil: return given
        }
    }
}
