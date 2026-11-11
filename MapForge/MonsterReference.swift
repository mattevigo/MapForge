import SwiftUI

/// A Monster's page, as the DM reads it mid-fight — the text, apart from the view that lays
/// it out.
///
/// The note's own words and nothing computed from them: the app never reasons about a speed
/// or an attack bonus, it only spares the DM an alt-tab to their vault while six people wait.
enum MonsterReference {
    struct Line: Equatable {
        var label: String
        var value: String
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
    /// Only what the note has. Armour class and hit points are not repeated: the Stat Block
    /// editor directly above shows the Pawn's own, which are the ones that are true now.
    static func lines(of monster: Monster) -> [Line] {
        let candidates: [(String, String?)] = [
            (String(localized: "Speed"), monster.speed),
            (String(localized: "Saves"), bonuses(monster.saves)),
            (String(localized: "Skills"), bonuses(monster.skills)),
            (String(localized: "Vulnerable"), monster.damageVulnerabilities),
            (String(localized: "Resists"), monster.damageResistances),
            (String(localized: "Immune"), monster.damageImmunities),
            (String(localized: "Cond. immune"), monster.conditionImmunities),
            (String(localized: "Senses"), monster.senses),
            (String(localized: "Languages"), monster.languages),
            (String(localized: "CR"), monster.challengeRating),
        ]
        return candidates.compactMap { label, value in
            value.map { Line(label: label, value: $0) }
        }
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
            .map { "\($0.name) \($0.bonus < 0 ? "−" : "+")\(abs($0.bonus))" }
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
/// At body size, not caption size: this is read at arm's length while six people wait, and
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
    let lines: [MonsterReference.Line]
    let groups: [MonsterReference.Group]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if !heading.isEmpty {
                        Text(heading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                ForEach(lines, id: \.label) { line in
                    (Text(line.label + " ").fontWeight(.semibold) + Text(line.value))
                        .font(.body)
                }
                ForEach(groups, id: \.title) { group in
                    Text(group.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(Array(group.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        text(paragraph).font(.body)
                    }
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
    }

    private func text(_ paragraph: MonsterReference.Paragraph) -> Text {
        switch paragraph {
        case .feature(let feature):
            return Text(feature.name + ". ").fontWeight(.semibold).italic()
                + Text(MonsterReference.attributed(feature.desc))
        case .plain(let line):
            return Text(MonsterReference.attributed(line))
        }
    }
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
