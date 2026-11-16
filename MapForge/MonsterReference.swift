import SwiftUI

/// A Monster's page, as the DM reads it mid-fight — the text, apart from the view that lays
/// it out.
///
/// The note's own words and nothing computed from them beyond what a rulebook prints beside
/// them — an ability score's modifier: the app never reasons about a speed or an attack bonus,
/// it only spares the DM an alt-tab to their vault while six people wait.
enum MonsterReference {
    struct Line: Equatable {
        var label: String
        var value: String
        /// What the rulebook prints on the same line after it: Initiative beside AC.
        var beside: [Line] = []
    }

    /// The one-line facts, in the two blocks the rulebook prints them in, with the ability
    /// table between: each line built into its block, never placed there by its label.
    struct Lines: Equatable {
        /// `AC 15   Initiative +2`, `HP 45 (6d10 + 12)`, Speed.
        var numbers: [Line]
        /// Saves (when the table cannot hold them), Skills, …, CR.
        var rest: [Line]

        /// Both blocks, in the rulebook's order.
        var all: [Line] { numbers + rest }
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

    /// The one-line facts above the actions, in the order the rulebook prints them.
    /// Only what the note has. Armour class and hit points are the definition's, read from
    /// the note — never a Pawn's, which four wounded gnolls sharing one Page do not share.
    static func lines(of monster: Monster) -> Lines {
        let rest: [(String, String?)] = [
            (String(localized: "Saves"), bonuses(savesOffTable(monster.saves, monster.abilityScores))),
            (String(localized: "Skills"), bonuses(monster.skills)),
            (String(localized: "Vulnerabilities"), monster.damageVulnerabilities),
            (String(localized: "Resistances"), monster.damageResistances),
            // The 2024 book's one line: damage, then conditions.
            (String(localized: "Immunities"),
             joined([monster.damageImmunities, monster.conditionImmunities], by: "; ")),
            (String(localized: "Senses"), monster.senses),
            (String(localized: "Languages"), monster.languages),
            (String(localized: "CR"), monster.challengeRating),
        ]
        return Lines(numbers: numbers(armorClass: monster.armorClass,
                                      initiativeBonus: monster.initiativeBonus,
                                      hitPoints: monster.hitPoints, hitDice: monster.hitDice,
                                      speed: monster.speed),
                     rest: present(rest))
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
            Line(label: initiativeLabel, value: signed($0))
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
    private static func joined(_ parts: [String?], by separator: String) -> String? {
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

    static func abilities(of monster: Monster) -> AbilityTable? {
        abilities(monster.abilityScores, saves: monster.saves)
    }

    /// The table, from the note's six scores and the saves it lists. A save is matched onto
    /// its Ability by the rulebook's name, in any language, as the Roll sheet matches it
    /// (ADR-0029); the first wins a repeat.
    static func abilities(_ scores: AbilityScores?, saves: [Monster.Proficiency]) -> AbilityTable? {
        guard let scores else { return nil }
        return AbilityTable(rows: Ability.allCases.map { ability in
            let modifier = signed(scores.modifier(ability))
            let listed = saves.first { Ability.named($0.name) == ability }
            return AbilityTable.Row(ability: ability, score: scores[ability], modifier: modifier,
                                    save: listed.map(save) ?? modifier)
        })
    }

    /// A listed save, with the `●` a Character's note marks a proficient one with kept.
    private static func save(_ listed: Monster.Proficiency) -> String {
        (listed.name.contains("●") ? "● " : "") + signed(listed.bonus)
    }

    /// The saves still to be given on a Saves line: all of them with no table, else those
    /// whose name matches no Ability — so nothing the note says is lost.
    static func savesOffTable(_ saves: [Monster.Proficiency],
                              _ scores: AbilityScores?) -> [Monster.Proficiency] {
        guard scores != nil else { return saves }
        return saves.filter { Ability.named($0.name) == nil }
    }

    /// A bonus as the rulebook prints it: always signed, with the true minus.
    static func signed(_ bonus: Int) -> String {
        "\(bonus < 0 ? "−" : "+")\(abs(bonus))"
    }

    /// A Page's parts as the rulebook divides a creature, a red rule between each and the next.
    enum Block: Hashable {
        /// The name, what it is, and the warnings.
        case heading
        /// `Lines.numbers`.
        case numbers
        case abilities
        /// `Lines.rest`.
        case lines
        /// Traits, Actions, …: each heading has its own rule beneath it.
        case groups
    }

    /// The blocks the note fills, in order: one it leaves empty is not there, so no two rules
    /// sit one on the other where it would have been.
    static func blocks(_ lines: Lines, _ abilities: AbilityTable?, _ groups: [Group]) -> [Block] {
        let filled: [(Block, Bool)] = [(.numbers, !lines.numbers.isEmpty),
                                       (.abilities, abilities != nil),
                                       (.lines, !lines.rest.isEmpty),
                                       (.groups, !groups.isEmpty)]
        return [.heading] + filled.filter(\.1).map(\.0)
    }

    static func blocks(of monster: Monster) -> [Block] {
        blocks(lines(of: monster), abilities(of: monster), groups(of: monster))
    }

    static func groups(of monster: Monster) -> [Group] {
        [features(String(localized: "Traits"), monster.traits),
         features(String(localized: "Actions"), monster.actions),
         features(String(localized: "Bonus Actions"), monster.bonusActions),
         features(String(localized: "Reactions"), monster.reactions),
         features(String(localized: "Legendary Actions"), monster.legendaryActions)]
            .filter { !$0.paragraphs.isEmpty }
    }

    static func features(_ title: String, _ features: [Monster.Feature]) -> Group {
        Group(title: title, paragraphs: features.map(Paragraph.feature))
    }

    static func bonuses(_ proficiencies: [Monster.Proficiency]) -> String? {
        guard !proficiencies.isEmpty else { return nil }
        return proficiencies
            .map { "\($0.name) \(signed($0.bonus))" }
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

/// A Monster's page, in the popover beside the Stat Block editor's name, for the Combatant
/// the editor is pointed at.
///
/// **The one live read of the Bestiary** (ADR-0020): looked up by the name the Pawn
/// remembers, each time it is drawn. Right here and nowhere else, because this is reference
/// and not state — every number the fight depends on was copied into the Stat Block when the
/// Monster was chosen. A Creature whose Monster has left the notes says so and loses nothing
/// else. Never on the Player Display.
struct MonsterReferenceView: View {
    /// The name the Pawn remembers.
    let monsterName: String
    let bestiary: Bestiary
    /// The unit in force, which the note is checked against.
    let unit: DistanceUnit

    var body: some View {
        if let monster = bestiary.monster(named: monsterName) {
            ReferencePageView(name: monster.name,
                              heading: [monster.size, monster.type, monster.alignment]
                                  .compactMap { $0 }.joined(separator: " · "),
                              warning: monster.warning(current: unit),
                              pictureProblem: monster.picture?.problem,
                              lines: MonsterReference.lines(of: monster),
                              abilities: MonsterReference.abilities(of: monster),
                              groups: MonsterReference.groups(of: monster))
                .accessibilityIdentifier("monster-reference")
        } else if let unavailable = bestiary.unavailable {
            // Still being read, or not configured: not the same thing as this Monster
            // having left the notes, and not to be reported as it.
            ReferenceCaption(text: Text(unavailable))
        } else {
            ReferenceCaption(text: Text("“\(monsterName)” is not in the Bestiary. Its numbers above are its own and are unaffected."))
                .accessibilityIdentifier("monster-reference-missing")
        }
    }
}

/// A page of the DM's notes beside the Stat Block editor — a Monster's or a Character's, laid
/// out alike so the DM reads both the same way mid-fight.
///
/// Drawn as a rulebook prints a creature — as the Fantasy Statblocks plugin draws one in the
/// DM's Obsidian notes, so nothing is re-learned between the two: the name in red serif small
/// caps, a red rule between each block and the next, serif section headings ruled beneath,
/// on parchment (`Color.page`). The look never costs the reading: body text stays in the
/// system font, at body size, in the scheme's text colour, and stays selectable.
///
/// Body size, not caption size: this is read at arm's length while six people wait, and
/// the 10-point captions it was first set in were a squint. It scrolls, so size costs no room.
struct ReferencePageView: View {
    let name: String
    /// Under the name: what the thing is. Left out when the note says nothing of it.
    let heading: String
    /// Under the heading, when the note is in the Distance Unit not in force (ADR-0027) — so
    /// a "9 m" is not read aloud to a table that speaks feet as if it were.
    let warning: String?
    /// Under the heading too, when the note names a picture that gives no Face — so the DM
    /// learns why this Monster's Pawns wear their colour, and which link to fix.
    var pictureProblem: String?
    let lines: MonsterReference.Lines
    /// Drawn between the two blocks of `lines`. Nil when the note lacks a score.
    let abilities: MonsterReference.AbilityTable?
    let groups: [MonsterReference.Group]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                let blocks = MonsterReference.blocks(lines, abilities, groups)
                ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                    if index > 0 {
                        PageRule()
                    }
                    content(of: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        // Takes whatever height its popover gives it, up to `PawnPage.maxHeight`, and
        // scrolls inside that. It lived under the editor once, sharing the tab with the
        // list above, and a long roster left it nothing; a popover has no list to share with.
        .frame(maxHeight: .infinity)
        .preference(key: PageSurface.self, value: true)
    }

    @ViewBuilder
    private func content(of block: MonsterReference.Block) -> some View {
        switch block {
        case .heading:
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.title2, design: .serif, weight: .bold).smallCaps())
                    .foregroundStyle(Color.pageAccent)
                if !heading.isEmpty {
                    // In the body's colour, not a secondary grey: grey on parchment is a squint.
                    Text(heading)
                        .font(.subheadline)
                        .italic()
                }
                // Warnings keep their colour on the parchment as off it: they are the app
                // speaking, not the rulebook.
                if let warning {
                    Label(warning, systemImage: "ruler")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("reference-other-unit")
                }
                if let pictureProblem {
                    Label(pictureProblem, systemImage: "photo")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("reference-picture-problem")
                }
            }
        case .numbers:
            lineBlock(lines.numbers)
        case .abilities:
            if let abilities {
                AbilityTableView(table: abilities)
            }
        case .lines:
            lineBlock(lines.rest)
        case .groups:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeading(title: group.title)
                        ForEach(Array(group.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            text(paragraph).font(.body)
                        }
                    }
                }
            }
        }
    }

    private func lineBlock(_ lines: [MonsterReference.Line]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.label) { line in
                text(line).font(.body)
            }
        }
    }

    /// `AC 15   Initiative +2`: each label in semibold in the heading colour, what stands
    /// beside it three spaces on.
    private func text(_ line: MonsterReference.Line) -> Text {
        line.beside.reduce(Text(line.label + " ").fontWeight(.semibold)
            .foregroundStyle(Color.pageHeading) + Text(line.value)) {
            $0 + Text("   ") + text($1)
        }
    }

    private func text(_ paragraph: MonsterReference.Paragraph) -> Text {
        switch paragraph {
        case .feature(let feature):
            return Text(feature.name + ". ").bold().italic()
                + Text(MonsterReference.attributed(feature.desc))
        case .plain(let line):
            return Text(MonsterReference.attributed(line))
        }
    }
}

/// Traits, Actions, …: in the serif, in the heading colour, at least the body's size, with a
/// thin red rule beneath.
private struct SectionHeading: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.pageHeading)
            Rectangle()
                .fill(Color.pageAccent)
                .frame(height: 1)
        }
    }
}

/// The red rule between a Page's blocks.
private struct PageRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.pageAccent)
            .frame(height: 1.5)
            .padding(.vertical, 2)
    }
}

/// The six Abilities as the 2024 book prints them: two blocks of three, STR DEX CON beside
/// INT WIS CHA, each Ability with its score, Mod and Save.
///
/// Side by side where the Page is wide enough for both at body size — the popover is — and
/// one above the other where it is not, as a pinned panel narrowed to its minimum: never
/// shrunk or truncated to fit, since a squinted-at save is the one the DM misreads.
struct AbilityTableView: View {
    let table: MonsterReference.AbilityTable

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) { halves }
            VStack(alignment: .leading, spacing: 8) { halves }
        }
        .accessibilityIdentifier("reference-abilities")
    }

    private var halves: some View {
        ForEach(Array(table.blocks.enumerated()), id: \.offset) { _, rows in
            AbilityBlock(rows: rows)
        }
    }
}

/// Three Abilities under their MOD and SAVE headings.
private struct AbilityBlock: View {
    let rows: ArraySlice<MonsterReference.AbilityTable.Row>

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(verbatim: "")
                Text(verbatim: "")
                Text("MOD", comment: "The ability table's column of modifiers, as the stat block heads it")
                // Its own key: "Save" alone is the verb that saves a file.
                Text(String(localized: "ability-table.save", defaultValue: "SAVE",
                            comment: "The ability table's column of saving throws, as the stat block heads it"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.pageHeading)
            ForEach(rows, id: \.ability) { row in
                GridRow {
                    Text(row.ability.abbreviation)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.pageHeading)
                        .gridColumnAlignment(.leading)
                    Text(verbatim: "\(row.score)")
                    Text(verbatim: row.modifier)
                    Text(verbatim: row.save)
                }
                .font(.body.monospacedDigit())
            }
        }
        .fixedSize()
    }
}

/// Whether what a page's holder — the popover, a pinned panel — shows is a Page, which wants
/// the parchment to the holder's edges. A caption standing in for one does not.
struct PageSurface: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// The parchment beneath, edge to edge, when what this holds is a Page.
    func pageSurface() -> some View {
        backgroundPreferenceValue(PageSurface.self) { isPage in
            if isPage {
                Color.page.ignoresSafeArea()
            }
        }
    }
}

/// The Page's colours: named in the asset catalogue, each with a light and a dark appearance,
/// so the DM can tune them at the table without touching code.
extension Color {
    /// Parchment in light mode, a dark page in dark mode.
    static let page = Color("PageSurface")
    /// The name, the rules between blocks and under headings.
    static let pageAccent = Color("PageAccent")
    /// Section headings and line labels.
    static let pageHeading = Color("PageHeading")
}

/// What stands where a page would be, when there is none to show: one quiet line.
struct ReferenceCaption: View {
    let text: Text

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
