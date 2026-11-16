import Foundation

/// What a Page says, as a Monster's and a Character's alike give it — its lines, its ability
/// table, its headed groups and the blocks a rule is drawn between — built from what the
/// note has, apart from the view that lays it out.
enum PageText {
    struct Line: Equatable {
        var label: String
        var value: String
        /// What the rulebook prints on the same line after it: Initiative beside AC.
        var beside: [Line] = []
    }

    /// The six Abilities as the rulebook prints them under Speed: each score, its modifier
    /// and its saving throw. Only for a note that gives all six scores.
    struct AbilityTable: Equatable {
        struct Row: Equatable {
            var ability: Ability
            var score: Int
            var modifier: String
            /// The note's save for this Ability, as it writes it, or else the modifier.
            var save: String
        }

        /// STR, DEX, CON, INT, WIS, CHA.
        var rows: [Row]

        /// STR DEX CON, then INT WIS CHA: the two blocks of three the book prints side by side.
        var blocks: [ArraySlice<Row>] {
            stride(from: 0, to: rows.count, by: 3).map { rows[$0..<min($0 + 3, rows.count)] }
        }
    }

    /// A heading on the page — Traits, Actions — and what it holds.
    struct Group: Equatable {
        var title: String
        var paragraphs: [Paragraph]
    }

    /// One paragraph under a Group: a named feature, or a line the note writes as it is — a
    /// Character's spellcasting, which has no name to put in front of it.
    enum Paragraph: Equatable {
        case feature(Monster.Feature)
        case plain(String)
    }

    /// A Line for each label whose value the note has, in order.
    static func present(_ candidates: [(String, String?)]) -> [Line] {
        candidates.compactMap { label, value in value.map { Line(label: label, value: $0) } }
    }

    /// `AC 15   Initiative +2`, then `HP 45 (6d10 + 12)`, then Speed: each part only when the
    /// note has it.
    static func numbers(armorClass: Int?, initiativeBonus: Int?,
                        hitPoints: Int?, hitDice: String?, speed: String?) -> [Line] {
        var lines: [Line] = []
        let initiative = initiativeBonus.map {
            Line(label: initiativeLabel, value: $0.signed)
        }
        if let armorClass {
            lines.append(Line(label: armorClassLabel, value: "\(armorClass)",
                              beside: initiative.map { [$0] } ?? []))
        } else if let initiative {
            lines.append(initiative)
        }
        if let hp = joined([hitPoints.map { "\($0)" }, hitDice.map { "(\($0))" }], by: " ") {
            lines.append(Line(label: hitPointsLabel, value: hp))
        }
        if let speed {
            lines.append(Line(label: speedLabel, value: speed))
        }
        return lines
    }

    /// The parts the note has, `separator` between them; nil when it has none.
    static func joined(_ parts: [String?], by separator: String) -> String? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: separator)
    }

    private static var armorClassLabel: String {
        String(localized: "AC", comment: "Armour Class, abbreviated")
    }
    private static var initiativeLabel: String { String(localized: "Initiative") }
    private static var hitPointsLabel: String {
        String(localized: "HP", comment: "Hit points, as narrow as the field")
    }
    private static var speedLabel: String { String(localized: "Speed") }

    /// The table, from the note's six scores and the saves it lists. A save is matched onto
    /// its Ability by the rulebook's name, in any language, as the Roll sheet matches it
    /// (ADR-0029); the first wins a repeat.
    static func abilities(_ scores: AbilityScores?, saves: [Monster.Proficiency]) -> AbilityTable? {
        guard let scores else { return nil }
        return AbilityTable(rows: Ability.allCases.map { ability in
            let modifier = scores.modifier(ability).signed
            let listed = saves.first { Ability.named($0.name) == ability }
            return AbilityTable.Row(ability: ability, score: scores[ability], modifier: modifier,
                                    save: listed.map(save) ?? modifier)
        })
    }

    /// A listed save, with the `●` a Character's note marks a proficient one with kept.
    private static func save(_ listed: Monster.Proficiency) -> String {
        (listed.name.contains("●") ? "● " : "") + listed.bonus.signed
    }

    /// The saves still to be given on a Saves line: all of them with no table, else those
    /// whose name matches no Ability — so nothing the note says is lost.
    static func savesOffTable(_ saves: [Monster.Proficiency],
                              _ scores: AbilityScores?) -> [Monster.Proficiency] {
        guard scores != nil else { return saves }
        return saves.filter { Ability.named($0.name) == nil }
    }

    /// A Page's parts as the rulebook divides a creature, a red rule between each and the next:
    /// each with what it holds, so a block is there only when the note fills it.
    enum Block: Equatable {
        /// The name, what it is, and the warnings.
        case heading
        /// `AC 15   Initiative +2`, `HP 45 (6d10 + 12)`, Speed.
        case armorClassToSpeed([Line])
        case abilities(AbilityTable)
        /// Skills, …, CR, as many as the note has — led by a Saves line when the table cannot
        /// hold a save the note lists. A Character's ends at Languages.
        case skillsToChallengeRating([Line])
        /// Traits, Actions, …: each heading has its own rule beneath it.
        case groups([Group])
    }

    /// The blocks the note fills, in order: one it leaves empty is not there, so no two rules
    /// sit one on the other where it would have been. Each line is built into its block,
    /// never placed there by its label.
    static func blocks(armorClassToSpeed: [Line], abilities: AbilityTable?,
                       skillsToChallengeRating: [Line], groups: [Group]) -> [Block] {
        var blocks: [Block] = [.heading]
        if !armorClassToSpeed.isEmpty { blocks.append(.armorClassToSpeed(armorClassToSpeed)) }
        if let abilities { blocks.append(.abilities(abilities)) }
        if !skillsToChallengeRating.isEmpty {
            blocks.append(.skillsToChallengeRating(skillsToChallengeRating))
        }
        if !groups.isEmpty { blocks.append(.groups(groups)) }
        return blocks
    }

    static func features(_ title: String, _ features: [Monster.Feature]) -> Group {
        Group(title: title, paragraphs: features.map(Paragraph.feature))
    }

    static func bonuses(_ proficiencies: [Monster.Proficiency]) -> String? {
        guard !proficiencies.isEmpty else { return nil }
        return proficiencies
            .map { "\($0.name) \($0.bonus.signed)" }
            .joined(separator: ", ")
    }

    // MARK: A description

    /// `desc` with Obsidian's wikilinks flattened to what the DM would read there:
    /// `[[Squartare]]` is "Squartare", `[[path/Lich|il Lich]]` is "il Lich", and the
    /// underscores a vault's file names use for spaces are spaces again.
    static func plain(_ desc: String) -> String {
        var result = ""
        var rest = Substring(desc)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            result += rest[..<open.lowerBound]
            result += linkText(rest[open.upperBound..<close.lowerBound])
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    private static func linkText(_ link: Substring) -> String {
        if let bar = link.lastIndex(of: "|") { return String(link[link.index(after: bar)...]) }
        let target = link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let file = target.split(separator: "/").last ?? target
        return file.replacingOccurrences(of: "_", with: " ")
    }

    /// `desc` ready to draw: wikilinks flattened, `*emphasis*` rendered. Inline markdown only
    /// — a description is a paragraph, and a stray `#` in one is not a heading. Text the
    /// parser refuses is shown as written, because a blank action is worse than an ugly one.
    static func attributed(_ desc: String) -> AttributedString {
        let text = plain(desc)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
