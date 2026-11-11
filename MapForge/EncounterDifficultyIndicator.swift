import SwiftUI

/// The Encounter Difficulty above the Combat tab's controls, before Play and while the fight
/// runs alike (ADR-0032): the bar when the party gives budgets, the Creatures' XP alone when
/// no Player counts, and under either a note of the Pawns that could not be counted.
///
/// Drawn only when a Creature counts — `CombatPanel` asks `AppState.encounterDifficultyReading`
/// for that — because a fight with nothing to fight has nothing to rate.
struct EncounterDifficultyIndicator: View {
    var encounterDifficulty: EncounterDifficulty
    var uncountedNote: String?
    var uncountedHelp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let bar = EncounterDifficultyBar(encounterDifficulty) {
                bar
            } else {
                creatureXPAlone
            }
            if let uncountedNote {
                Text(uncountedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(uncountedHelp)
                    .accessibilityIdentifier("encounter-difficulty-uncounted")
            }
        }
    }

    /// No band and no bar: with no counted Player there are no budgets to draw the marks
    /// from, and a band named against nothing would be a verdict the app cannot give.
    private var creatureXPAlone: some View {
        EncounterDifficultyCaption(value: encounterDifficulty.creatureXPLabel())
            .help(String(localized: "No Player counts, so there is no XP budget to rate the Creatures against.",
                         comment: "Over the Creatures' XP, shown alone when no Player in the fight can be counted"))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("encounter-difficulty")
    }
}

extension EncounterDifficulty {
    /// The Creatures' total alone, for when no Player counts and there is no band: "650 XP",
    /// "1.100 PE".
    func creatureXPLabel(in locale: Locale = .interface) -> String {
        String(localized: LocalizedStringResource(
            "\(creatureXP.grouped(in: locale)) XP", locale: locale,
            comment: "The Creatures' total when no Player counts, so there is no band: 650 XP"))
    }
}

extension EncounterDifficultyReading {
    /// How many Pawns on each side could not be counted — "2 Creatures, 1 Player not
    /// counted" — or nil when every one was.
    var uncountedNote: String? { uncountedNote(in: .interface) }

    /// The note in `locale`, each count in its own plural: "2 creature, 1 giocatore non
    /// contati".
    func uncountedNote(in locale: Locale) -> String? {
        let creatures = uncounted.filter { $0.reason.kind == .creature }.count
        let players = uncounted.count - creatures
        let note: LocalizedStringResource
        switch (creatures, players) {
        case (0, 0):
            return nil
        case (_, 0):
            note = LocalizedStringResource("\(creatures) Creatures not counted", locale: locale,
                                           comment: "Under the Encounter Difficulty: Creatures in the fight whose Challenge Rating could not be read")
        case (0, _):
            note = LocalizedStringResource("\(players) Players not counted", locale: locale,
                                           comment: "Under the Encounter Difficulty: Players in the fight whose level could not be read")
        default:
            note = LocalizedStringResource("\(creatures) Creatures, \(players) Players not counted", locale: locale,
                                           comment: "Under the Encounter Difficulty: Creatures and Players in the fight whose numbers could not be read")
        }
        return String(localized: note)
    }

    /// Each uncounted Pawn by its label and why, one to a line, for the note's hover.
    var uncountedHelp: String { uncountedHelp(in: .interface) }

    func uncountedHelp(in locale: Locale) -> String {
        uncounted.map { pawn in
            String(localized: LocalizedStringResource(
                "\(pawn.label): \(pawn.reason.title(in: locale))", locale: locale,
                comment: "A Pawn left out of the Encounter Difficulty and why: GG3: no Monster"))
        }
        .joined(separator: "\n")
    }
}

extension UncountedPawn.Reason {
    /// Why the Pawn was not counted, said so the DM knows what to fix in the notes. Never
    /// guessing at a number, and quoting the text that could not be read.
    var title: String { title(in: .interface) }

    func title(in locale: Locale) -> String {
        var resource = titleResource
        resource.locale = locale
        return String(localized: resource)
    }

    private var titleResource: LocalizedStringResource {
        switch self {
        case .noMonster:
            return LocalizedStringResource("no Monster",
                                           comment: "Why a Creature is not counted: the DM never said which Monster it is")
        case .monsterNotInBestiary(let monsterName):
            return LocalizedStringResource("“\(monsterName)” is not in the Bestiary",
                                           comment: "Why a Creature is not counted: its Monster has left the notes")
        case .challengeRatingNotCounted(let text?):
            return LocalizedStringResource("Challenge Rating “\(text)” cannot be counted",
                                           comment: "Why a Creature is not counted: its Monster's note writes a cr the rules give no XP for, quoted")
        case .challengeRatingNotCounted(nil):
            return LocalizedStringResource("the Monster has no Challenge Rating",
                                           comment: "Why a Creature is not counted: its Monster's note writes no cr")
        case .noCharacter:
            return LocalizedStringResource("no Character",
                                           comment: "Why a Player is not counted: it was not Stamped from a Character")
        case .characterGone:
            return LocalizedStringResource("the Character no longer exists",
                                           comment: "Why a Player is not counted: its Character was deleted")
        case .noNote:
            return LocalizedStringResource("the Character has no note",
                                           comment: "Why a Player is not counted: its Character was never linked to a note")
        case .noteNotFound(let noteName):
            return LocalizedStringResource("the note “\(noteName)” cannot be found",
                                           comment: "Why a Player is not counted: its Character's note is not among the notes read")
        case .levelNotCounted(let text?):
            return LocalizedStringResource("level “\(text)” cannot be counted",
                                           comment: "Why a Player is not counted: its Character's note writes a level that is not a whole number from 1 to 20, quoted")
        case .levelNotCounted(nil):
            return LocalizedStringResource("the note has no level",
                                           comment: "Why a Player is not counted: its Character's note writes no level")
        }
    }
}
