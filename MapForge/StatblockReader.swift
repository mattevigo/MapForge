import Foundation
import Yams

/// Reads the Monster out of one of the DM's notes.
///
/// A note is a Monster when it holds a ```` ```statblock ```` fence — the notation of
/// Obsidian's Fantasy Statblocks plugin, which is YAML. Everything outside the fence is the
/// DM's prose and is ignored.
///
/// **The only place YAML is known about** (ADR-0019). Yams turns the fence into a tree; what
/// a Monster *is* — which integer `hp: 67 (9d8 + 27)` means, that `−` is a minus — is decided
/// here, on top of that tree.
///
/// **Lenient, because the notes are hand-written** (ADR-0020). A value that cannot be read
/// is absent rather than fatal; only a fence that is not YAML at all, or names nothing, is
/// refused — and then with a reason, because a Monster silently missing from a search is the
/// failure a DM cannot diagnose.
enum StatblockReader {
    enum Reading: Equatable {
        /// No fence — a note about a tavern, an image, anything — or a fence that says it is
        /// no Monster. Not worth reporting.
        case notAMonster
        case monster(Monster)
        /// A fence the DM meant as a Monster and the app could not read.
        case skipped(reason: String)
    }

    static func read(_ markdown: String) -> Reading {
        guard let yaml = fence(in: markdown) else { return .notAMonster }

        let tree: [String: Any]
        do {
            guard let loaded = try Yams.load(yaml: yaml) as? [String: Any] else {
                return .skipped(reason: String(localized: "the statblock is not a list of fields"))
            }
            tree = loaded
        } catch {
            return .skipped(reason: String(localized: "the statblock is not valid YAML"))
        }

        // Not every fence is a Monster (ADR-0023). `bestiary: false` is Fantasy Statblocks'
        // own word for one that is not — a Character's past build, a template — and a fence
        // with a key only a Character has is a Character's. Neither is reported: the note is
        // saying what it is, before it has a name to be skipped under.
        if tree["bestiary"] as? Bool == false || isCharacter(tree) {
            return .notAMonster
        }

        guard let name = text(tree["name"]) else {
            return .skipped(reason: String(localized: "the statblock has no name"))
        }

        var monster = Monster(name: name)
        monster.armorClass = leadingInteger(tree["ac"])
        monster.hitPoints = leadingInteger(tree["hp"])
        monster.initiativeBonus = leadingInteger(tree["initiative"])
        monster.size = text(tree["size"])
        monster.isBig = isBig(size: monster.size)
        monster.type = text(tree["type"])
        monster.alignment = text(tree["alignment"])
        monster.hitDice = text(tree["hit_dice"])
        monster.speed = text(tree["speed"])
        monster.senses = text(tree["senses"])
        monster.languages = text(tree["languages"])
        monster.challengeRating = text(tree["cr"])
        monster.source = text(tree["source"])
        monster.saves = proficiencies(tree["saves"])
        monster.skills = proficiencies(tree["skillsaves"])
        monster.damageVulnerabilities = text(tree["damage_vulnerabilities"])
        monster.damageResistances = text(tree["damage_resistances"])
        monster.damageImmunities = text(tree["damage_immunities"])
        monster.conditionImmunities = text(tree["condition_immunities"])
        monster.traits = features(tree["traits"])
        monster.actions = features(tree["actions"])
        monster.bonusActions = features(tree["bonus_actions"])
        monster.reactions = features(tree["reactions"])
        monster.legendaryActions = features(tree["legendary_actions"])
        return .monster(monster)
    }

    /// The text inside the note's first `statblock` fence, or nil when it has none.
    ///
    /// The first, because a note defines one Monster: a second fence would be a second
    /// `name`, and one file offering two search results is a thing to decide when a vault
    /// actually does it.
    static func fence(in markdown: String) -> String? {
        var body: [Substring] = []
        var isInside = false
        // CRLF folded first: Swift reads "\r\n" as one Character, so a split on "\n" alone
        // would find a Windows-written note to be a single line.
        let unixed = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for line in unixed.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isInside {
                if trimmed.hasPrefix("```") { return body.joined(separator: "\n") }
                body.append(line)
            } else if trimmed.hasPrefix("```statblock") {
                isInside = true
            }
        }
        // An unclosed fence is a note being typed right now. Not a Monster yet.
        return nil
    }

    /// The keys only a Character's fence has. Any one will do: `player` is left out of a
    /// Character nobody plays yet, but its species, class and level are always written.
    static let characterKeys = ["player", "species", "class", "level"]

    /// Whether a fence is a Character's rather than a Monster's (ADR-0023).
    static func isCharacter(_ tree: [String: Any]) -> Bool {
        characterKeys.contains { tree[$0] != nil }
    }

    /// Large and up is a 2×2 token (`CONTEXT.md`, **Big**). Italian and English, because the
    /// vault has both; anything unrecognised — "Small or Medium" — is an ordinary token,
    /// which is the mistake that costs the DM one click rather than a crowded Map.
    static func isBig(size: String?) -> Bool {
        guard let size = size?.lowercased() else { return false }
        let big = ["grande", "enorme", "mastodontica", "mastodontico",
                   "large", "huge", "gargantuan"]
        return big.contains { size.hasPrefix($0) }
    }

    // MARK: Reading a value

    /// A scalar as the text the DM wrote. YAML hands `cr: 5` over as an integer and
    /// `cr: 1/2` as a string; the DM reads both the same way.
    private static func text(_ value: Any?) -> String? {
        let string: String
        switch value {
        case let value as String: string = value
        case let value as Int: string = String(value)
        case let value as Double: string = String(value)
        default: return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The signed integer a value starts with: 27 from `27`, 67 from `67 (9d8 + 27)`, −1
    /// from `"−1 (9)"`.
    private static func leadingInteger(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        guard let text = text(value) else { return nil }
        var digits = ""
        var sign = 1
        for (index, character) in text.enumerated() {
            if index == 0, character == "+" { continue }
            // U+2212 is what a typographically careful note uses, and `Int("−1")` is nil.
            if index == 0, character == "-" || character == "\u{2212}" { sign = -1; continue }
            guard character.isASCII, character.isNumber else { break }
            digits.append(character)
        }
        return Int(digits).map { $0 * sign }
    }

    private static func features(_ value: Any?) -> [Monster.Feature] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            guard let fields = item as? [String: Any], let name = text(fields["name"])
            else { return nil }
            return Monster.Feature(name: name, desc: text(fields["desc"]) ?? "")
        }
    }

    /// `saves:` and `skillsaves:` — a list of single-key maps in the vault's files, and
    /// tolerated as one map, which is the other way the plugin's users write it.
    private static func proficiencies(_ value: Any?) -> [Monster.Proficiency] {
        let maps: [[String: Any]]
        switch value {
        case let list as [Any]: maps = list.compactMap { $0 as? [String: Any] }
        case let map as [String: Any]: maps = [map]
        default: return []
        }
        return maps.flatMap { map in
            map.keys.sorted().compactMap { key in
                leadingInteger(map[key]).map { Monster.Proficiency(name: key, bonus: $0) }
            }
        }
    }
}
