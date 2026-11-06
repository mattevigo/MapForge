import Foundation
import Yams

/// Reads the Monster out of one of the DM's notes.
///
/// A note is a Monster when it holds a ```` ```statblock ```` fence — the notation of
/// Obsidian's Fantasy Statblocks plugin, which is YAML. Everything outside the fence is the
/// DM's prose and is ignored.
///
/// **One of the two places YAML is known about** (ADR-0019) — `ItemReader`, which reads a
/// note's frontmatter, is the other. Yams turns the fence into a tree; what
/// a Monster *is* — which integer `hp: 67 (9d8 + 27)` means, that `−` is a minus, what
/// `extends` lays over what — is decided here, on top of that tree.
///
/// **Lenient with prose, strict with numbers** (ADR-0020, ADR-0023). A value that cannot be
/// read is absent rather than fatal; only a fence that is not YAML at all, names nothing, or
/// extends what cannot be found is refused — and then with a reason, because a Monster
/// silently missing from a search is the failure a DM cannot diagnose. A number is a number
/// or nothing: an empty field asks the DM, a wrong one does not.
enum StatblockReader {
    enum Reading: Equatable {
        /// No fence — a note about a tavern, an image, anything — or a fence that says it is
        /// no Monster. Not worth reporting.
        case notAMonster
        case monster(Monster)
        /// A fence the DM meant as a Monster and the app could not read.
        case skipped(reason: String)
    }

    /// A fence's fields as YAML gives them, before they are a Monster.
    typealias Fields = [String: Any]

    enum Fence {
        case none
        case fields(Fields)
        /// A fence that is not YAML, or not a list of fields.
        case unreadable(reason: String)
    }

    /// One note on its own. A note that `extends` another cannot be read this way — the
    /// Bestiary reads every fence first and calls `monster(from:bases:)`.
    static func read(_ markdown: String) -> Reading {
        switch fields(in: markdown) {
        case .none: return .notAMonster
        case .unreadable(let reason): return .skipped(reason: reason)
        case .fields(let fields): return monster(from: fields, bases: [:])
        }
    }

    /// The fields of the note's statblock, read but not yet judged.
    static func fields(in markdown: String) -> Fence {
        guard let yaml = fence(in: markdown) else { return .none }
        do {
            guard let loaded = try Yams.load(yaml: yaml) as? Fields else {
                return .unreadable(reason: String(localized: "the statblock is not a list of fields"))
            }
            return .fields(loaded)
        } catch {
            return .unreadable(reason: String(localized: "the statblock is not valid YAML"))
        }
    }

    /// The Monster a fence defines, with what it `extends` taken from `bases` — every named
    /// fence in the Workspace that is not a Character's, by name.
    static func monster(from fields: Fields, bases: [String: Fields]) -> Reading {
        // Not every fence is a Monster (ADR-0023). `bestiary: false` is Fantasy Statblocks'
        // own word for one that is not — a Character's past build, a template — and a fence
        // with a key only a Character has is a Character's. Neither is reported: the note is
        // saying what it is, before it has a name to be skipped under.
        if isOutOfBestiary(fields) || isCharacter(fields) {
            return .notAMonster
        }

        guard let name = name(of: fields) else {
            return .skipped(reason: String(localized: "the statblock has no name"))
        }

        let tree: Fields
        switch resolved(fields, bases: bases, chain: [name]) {
        case .success(let merged): tree = merged
        case .failure(let unresolved): return .skipped(reason: unresolved.reason)
        }

        var monster = Monster(name: name)
        monster.armorClass = number(tree["ac"])
        monster.hitPoints = number(tree["hp"])
        monster.initiativeBonus = number(tree["initiative"])
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
        monster.abilityScores = abilityScores(tree["stats"])
        monster.damageVulnerabilities = text(tree["damage_vulnerabilities"])
        monster.damageResistances = text(tree["damage_resistances"])
        monster.damageImmunities = text(tree["damage_immunities"])
        monster.conditionImmunities = text(tree["condition_immunities"])
        monster.traits = features(tree["traits"])
        monster.actions = features(tree["actions"])
        monster.bonusActions = features(tree["bonus_actions"])
        monster.reactions = features(tree["reactions"])
        monster.legendaryActions = features(tree["legendary_actions"])
        monster.imageLink = imageLink(tree["image"])
        return .monster(monster)
    }

    enum CharacterReading: Equatable {
        /// A Monster's fence, a fence kept out of the bestiary, or no fence at all.
        case notACharacter
        case character(CharacterNote)
        case skipped(reason: String)
    }

    /// The Character a fence defines, when it is a Character's (ADR-0024). A past build kept
    /// with `bestiary: false` is not: a hero has one note and one set of numbers.
    static func character(from fields: Fields) -> CharacterReading {
        guard isCharacter(fields), !isOutOfBestiary(fields) else { return .notACharacter }
        guard let name = name(of: fields) else {
            return .skipped(reason: String(localized: "the statblock has no name"))
        }
        var note = CharacterNote(name: name)
        note.armorClass = number(fields["ac"])
        note.maxHP = number(fields["hp"])
        note.initiativeBonus = number(fields["initiative"])
        note.size = text(fields["size"])
        note.isBig = isBig(size: note.size)
        note.species = text(fields["species"])
        note.characterClass = text(fields["class"])
        note.level = text(fields["level"])
        note.speed = text(fields["speed"])
        note.senses = text(fields["senses"])
        note.languages = text(fields["languages"])
        note.saves = proficiencies(fields["saves"])
        note.skills = proficiencies(fields["skillsaves"])
        note.abilityScores = abilityScores(fields["stats"])
        note.traits = features(fields["traits"])
        note.actions = features(fields["actions"])
        note.spells = textList(fields["spells"])
        note.imageLink = imageLink(fields["image"])
        return .character(note)
    }

    /// The name a fence goes by — what `extends` and a Pawn's `monsterName` match on.
    static func name(of fields: Fields) -> String? {
        text(fields["name"])
    }

    /// `bestiary: false`: kept out of the list, though another fence may still extend it.
    static func isOutOfBestiary(_ fields: Fields) -> Bool {
        fields["bestiary"] as? Bool == false
    }

    // MARK: Extends

    enum Unresolved: Error, Equatable {
        case missing(String)
        case loop

        var reason: String {
            switch self {
            case .missing(let base):
                return String(localized: "extends: “\(base)” names a Monster no note defines")
            case .loop:
                return String(localized: "its extends chain comes back to itself")
            }
        }
    }

    /// A fence with what it `extends` laid underneath, as Fantasy Statblocks resolves it: each
    /// key the fence writes replaces the base's value whole — an NPC's `actions` are its
    /// actions, not the base's plus its own — and the rest is the base's. Several bases
    /// (`extends: [A, B]`) are laid in order, the later winning. `chain` holds every name
    /// already on the way down, so a loop is caught rather than followed forever.
    static func resolved(_ fields: Fields, bases: [String: Fields],
                         chain: [String]) -> Result<Fields, Unresolved> {
        let parents = baseNames(fields["extends"])
        guard !parents.isEmpty else { return .success(fields) }
        var merged: Fields = [:]
        for parent in parents {
            guard !chain.contains(parent) else { return .failure(.loop) }
            guard let base = bases[parent] else { return .failure(.missing(parent)) }
            switch resolved(base, bases: bases, chain: chain + [parent]) {
            case .failure(let unresolved): return .failure(unresolved)
            case .success(let full): merged.merge(full) { _, later in later }
            }
        }
        // Whether a fence is listed is its own say, never its base's.
        merged["bestiary"] = nil
        merged.merge(fields) { _, own in own }
        merged["extends"] = nil
        return .success(merged)
    }

    /// `extends: Esploratore` or `extends: [Esploratore, Bandito]`.
    private static func baseNames(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap(text) }
        return text(value).map { [$0] } ?? []
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

    /// `image:` as a wikilink's target: `"[[Nothic.webp]]"`, or the same unquoted, which YAML
    /// reads as a list inside a list. An embed's `!` before it, a heading after `#` and a
    /// display text after `|` are how the link is written, not what it names.
    ///
    /// A wikilink only (ADR-0028). A web address is ignored, because opening a game must not
    /// need the network, and so is plain text, which Obsidian does not draw as a picture.
    static func imageLink(_ value: Any?) -> String? {
        let target: String
        if let outer = value as? [Any], outer.count == 1,
           let inner = outer.first as? [Any], inner.count == 1, let name = text(inner.first) {
            target = name
        } else if let text = text(value) {
            let link = text.hasPrefix("!") ? String(text.dropFirst()) : text
            guard link.hasPrefix("[["), link.hasSuffix("]]") else { return nil }
            target = String(link.dropFirst(2).dropLast(2))
        } else {
            return nil
        }
        let name = target.prefix { $0 != "|" && $0 != "#" }
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

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

    /// A signed integer, alone or followed by a bracket: 27, `67 (9d8 + 27)`, `"−1 (9)"`.
    /// Anything else is no number at all — `11 + il livello dell'incantesimo` is a formula
    /// whose leading 11 is wrong at every spell level, and a wrong number looks trustworthy
    /// where an empty field asks (ADR-0023).
    static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        guard let text = text(value) else { return nil }
        var rest = Substring(text)
        var sign = 1
        // U+2212 is what a typographically careful note uses, and `Int("−1")` is nil.
        if let first = rest.first, first == "+" || first == "-" || first == "\u{2212}" {
            sign = first == "+" ? 1 : -1
            rest = rest.dropFirst()
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard let magnitude = Int(digits) else { return nil }
        let tail = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty || (tail.hasPrefix("(") && tail.hasSuffix(")")) else { return nil }
        return magnitude * sign
    }

    private static func features(_ value: Any?) -> [Monster.Feature] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            guard let fields = item as? [String: Any], let name = text(fields["name"])
            else { return nil }
            return Monster.Feature(name: name, desc: text(fields["desc"]) ?? "")
        }
    }

    /// `spells:` — a list of text, one line each. A line with a colon in it,
    /// `- 1° livello: 4 slot`, is a map of one key to YAML, and is put back together as the
    /// line the DM wrote. Anything else in the list — a bare number, a nested list — is not
    /// a line of the note's and is left out.
    private static func textList(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            if let map = item as? [String: Any] {
                guard map.count == 1, let (key, value) = map.first,
                      let text = text(value) else { return nil }
                return "\(key): \(text)"
            }
            return (item as? String).flatMap(text)
        }
    }

    /// `stats: [14, 12, 11, 6, 10, 7]` — six numbers, each by `number(_:)`'s rule, or nothing
    /// at all. One score that is not a number spoils the list: an offer built on five good
    /// scores and a guess would be wrong with confidence (ADR-0029).
    private static func abilityScores(_ value: Any?) -> AbilityScores? {
        guard let items = value as? [Any] else { return nil }
        let scores = items.compactMap(number)
        guard scores.count == items.count else { return nil }
        return AbilityScores(scores)
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
                number(map[key]).map { Monster.Proficiency(name: key, bonus: $0) }
            }
        }
    }
}
