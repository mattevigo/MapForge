import SwiftUI

/// A Monster's Page, as the DM reads it mid-fight — the text, apart from the view that lays
/// it out.
///
/// The note's own words and nothing computed from them beyond what a rulebook prints beside
/// them — an ability score's modifier: the app never reasons about a speed or an attack bonus,
/// it only spares the DM an alt-tab to their vault while six people wait.
enum MonsterReference {
    /// The blocks of the Monster's Page, in the order the rulebook prints them: only what the
    /// note has. Armour class and hit points are the definition's, read from the note — never
    /// a Pawn's, which four wounded gnolls sharing one Page do not share.
    static func blocks(of monster: Monster) -> [PageText.Block] {
        let skillsToChallengeRating: [(String, String?)] = [
            (String(localized: "Saves"),
             PageText.bonuses(PageText.savesOffTable(monster.saves, monster.abilityScores))),
            (String(localized: "Skills"), PageText.bonuses(monster.skills)),
            (String(localized: "Vulnerabilities"), monster.damageVulnerabilities),
            (String(localized: "Resistances"), monster.damageResistances),
            // The 2024 book's one line: damage, then conditions.
            (String(localized: "Immunities"),
             PageText.joined([monster.damageImmunities, monster.conditionImmunities], by: "; ")),
            (String(localized: "Senses"), monster.senses),
            (String(localized: "Languages"), monster.languages),
            (String(localized: "CR"), monster.challengeRating),
        ]
        return PageText.blocks(
            armorClassToSpeed: PageText.numbers(armorClass: monster.armorClass,
                                                initiativeBonus: monster.initiativeBonus,
                                                hitPoints: monster.hitPoints,
                                                hitDice: monster.hitDice, speed: monster.speed),
            abilities: abilities(of: monster),
            skillsToChallengeRating: PageText.present(skillsToChallengeRating),
            groups: groups(of: monster))
    }

    static func abilities(of monster: Monster) -> PageText.AbilityTable? {
        PageText.abilities(monster.abilityScores, saves: monster.saves)
    }

    static func groups(of monster: Monster) -> [PageText.Group] {
        [PageText.features(String(localized: "Traits"), monster.traits),
         PageText.features(String(localized: "Actions"), monster.actions),
         PageText.features(String(localized: "Bonus Actions"), monster.bonusActions),
         PageText.features(String(localized: "Reactions"), monster.reactions),
         PageText.features(String(localized: "Legendary Actions"), monster.legendaryActions)]
            .filter { !$0.paragraphs.isEmpty }
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
                              blocks: MonsterReference.blocks(of: monster))
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

/// A Page of the DM's notes beside the Stat Block editor — a Monster's or a Character's, laid
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
    /// What the Page says, from `.heading` on: only the blocks the note fills.
    let blocks: [PageText.Block]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
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
        .preference(key: HoldsPage.self, value: true)
    }

    @ViewBuilder
    private func content(of block: PageText.Block) -> some View {
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
        case .armorClassToSpeed(let lines), .skillsToChallengeRating(let lines):
            lineBlock(lines)
        case .abilities(let table):
            AbilityTableView(table: table)
        case .groups(let groups):
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

    private func lineBlock(_ lines: [PageText.Line]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.label) { line in
                text(line).font(.body)
            }
        }
    }

    /// `AC 15   Initiative +2`: each label in semibold in the heading colour, what stands
    /// beside it three spaces on.
    private func text(_ line: PageText.Line) -> Text {
        line.beside.reduce(Text(line.label + " ").fontWeight(.semibold)
            .foregroundStyle(Color.pageHeading) + Text(line.value)) {
            $0 + Text("   ") + text($1)
        }
    }

    private func text(_ paragraph: PageText.Paragraph) -> Text {
        switch paragraph {
        case .feature(let feature):
            return Text(feature.name + ". ").bold().italic()
                + Text(PageText.attributed(feature.desc))
        case .plain(let line):
            return Text(PageText.attributed(line))
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
    let table: PageText.AbilityTable

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
    let rows: ArraySlice<PageText.AbilityTable.Row>

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(verbatim: "")
                Text(verbatim: "")
                Text("MOD", comment: "The ability table's column of modifiers, as the rulebook heads it")
                // Its own key: "Save" alone is the verb that saves a file.
                Text(String(localized: "ability-table.save", defaultValue: "SAVE",
                            comment: "The ability table's column of saving throws, as the rulebook heads it"))
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

/// Whether what a Page's holder — the popover, a pinned panel — shows is one, which wants
/// the parchment to the holder's edges. A caption standing in for one does not.
struct HoldsPage: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// The parchment beneath, edge to edge, when what this holds is a Page.
    func pageSurface() -> some View {
        backgroundPreferenceValue(HoldsPage.self) { isPage in
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
