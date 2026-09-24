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

    struct Group: Equatable {
        var title: String
        var features: [Monster.Feature]
    }

    /// The one-line facts above the actions, in the order the rulebook prints them.
    /// Only what the note has. Armour class and hit points are not repeated: the Stat Block
    /// editor directly above shows the Pawn's own, which are the ones that are true now.
    static func lines(of monster: Monster) -> [Line] {
        let candidates: [(String, String?)] = [
            ("Speed", monster.speed),
            ("Saves", bonuses(monster.saves)),
            ("Skills", bonuses(monster.skills)),
            ("Vulnerable", monster.damageVulnerabilities),
            ("Resists", monster.damageResistances),
            ("Immune", monster.damageImmunities),
            ("Cond. immune", monster.conditionImmunities),
            ("Senses", monster.senses),
            ("Languages", monster.languages),
            ("CR", monster.challengeRating),
        ]
        return candidates.compactMap { label, value in
            value.map { Line(label: label, value: $0) }
        }
    }

    static func groups(of monster: Monster) -> [Group] {
        [Group(title: "Traits", features: monster.traits),
         Group(title: "Actions", features: monster.actions),
         Group(title: "Bonus Actions", features: monster.bonusActions),
         Group(title: "Reactions", features: monster.reactions),
         Group(title: "Legendary Actions", features: monster.legendaryActions)]
            .filter { !$0.features.isEmpty }
    }

    private static func bonuses(_ proficiencies: [Monster.Proficiency]) -> String? {
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

/// A Monster's page under the Stat Block editor, for the Combatant the editor is pointed at.
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

    var body: some View {
        if let monster = bestiary.monster(named: monsterName) {
            page(monster)
        } else if let unavailable = bestiary.unavailable {
            // Still being read, or not configured: not the same thing as this Monster
            // having left the notes, and not to be reported as it.
            Text(unavailable)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("“\(monsterName)” is not in the Bestiary. Its numbers above are its own and are unaffected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("monster-reference-missing")
        }
    }

    private func page(_ monster: Monster) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(monster.name).font(.caption.weight(.semibold))
                    Text([monster.size, monster.type, monster.alignment]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(MonsterReference.lines(of: monster), id: \.label) { line in
                    (Text(line.label + " ").fontWeight(.semibold) + Text(line.value))
                        .font(.caption)
                }
                ForEach(MonsterReference.groups(of: monster), id: \.title) { group in
                    Text(group.title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(Array(group.features.enumerated()), id: \.offset) { _, feature in
                        (Text(feature.name + ". ").fontWeight(.semibold).italic()
                            + Text(MonsterReference.attributed(feature.desc)))
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        // Takes whatever the tab has left under the editor, and scrolls inside that. It was
        // capped at 240 once, to keep a Caos Orb's page from pushing the Order off the top
        // of the tab — which left a tall window half empty under a page the DM was
        // scrolling three lines at a time. A ScrollView cannot push anything: it shares
        // the height with the Order's instead.
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("monster-reference")
    }
}
