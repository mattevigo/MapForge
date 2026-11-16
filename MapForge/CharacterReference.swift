import SwiftUI

/// How far `AppState.characterNote(for:)` got from a Pawn to its Character's note.
enum CharacterNoteLookup: Equatable {
    /// The Pawn was not Stamped from a Character.
    case noCharacter
    /// The Character that Stamped it has been deleted from every Party since.
    case characterGone
    /// The Character was never linked to a note.
    case unlinked(PartyCharacter)
    /// The Character's note is not among the notes read.
    case missing(noteName: String)
    case found(CharacterNote)
}

/// What the Combat tab shows under a Player Pawn's Stat Block editor — `AppState.characterPage(for:)`.
enum CharacterPage: Equatable {
    /// The Character's note, read from the Workspace.
    case note(CharacterNote)
    /// The DM has not said which note is the Character's own: the Party panel is where they do.
    case unlinked(characterName: String)
    /// The Character's note was renamed or deleted. Its Pawns' numbers are their own and lose
    /// nothing; only this page is gone.
    case missing(noteName: String)
    /// The notes are still being read, or no Workspace is open — not the same thing as the
    /// note having gone, and not to be reported as it.
    case unavailable(String)
}

/// A Character's Page, as the DM reads it mid-fight — the text, apart from the view that lays
/// it out. `MonsterReference` for a Player: the note's own words and, as there, nothing
/// computed from them but an ability score's modifier, so "what's my spell save DC again?" is
/// answered without asking the player.
enum CharacterReference {
    /// Under the name, as a Monster's page gives size · type · alignment: who this is.
    static func heading(of note: CharacterNote) -> String {
        [note.species,
         note.characterClass,
         note.level.map { String(localized: "Level \($0)", comment: "A Character's level, under its name") }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The one-line facts above the Traits, as a Monster's Page gives them. Only what the note
    /// has. Its armour class and hit points are the note's — the maximum, with no hit dice —
    /// never its Pawn's.
    static func lines(of note: CharacterNote) -> PageText.Lines {
        let rest: [(String, String?)] = [
            (String(localized: "Saves"),
             PageText.bonuses(PageText.savesOffTable(note.saves, note.abilityScores))),
            (String(localized: "Skills"), PageText.bonuses(note.skills)),
            (String(localized: "Senses"), note.senses),
            (String(localized: "Languages"), note.languages),
        ]
        return PageText.Lines(
            numbers: PageText.numbers(armorClass: note.armorClass,
                                      initiativeBonus: note.initiativeBonus,
                                      hitPoints: note.maxHP, hitDice: nil,
                                      speed: note.speed),
            rest: PageText.present(rest))
    }

    /// The ability table, as a Monster's Page gives it.
    static func abilities(of note: CharacterNote) -> PageText.AbilityTable? {
        PageText.abilities(note.abilityScores, saves: note.saves)
    }

    /// The blocks a rule is drawn between, as a Monster's Page divides them.
    static func blocks(of note: CharacterNote) -> [PageText.Block] {
        PageText.blocks(lines(of: note), abilities(of: note), groups(of: note))
    }

    /// Traits and Actions as a Monster's are; Spells as the plain lines the note writes.
    static func groups(of note: CharacterNote) -> [PageText.Group] {
        [PageText.features(String(localized: "Traits"), note.traits),
         PageText.features(String(localized: "Actions"), note.actions),
         PageText.Group(title: String(localized: "Spells"),
                        paragraphs: note.spells.map(PageText.Paragraph.plain))]
            .filter { !$0.paragraphs.isEmpty }
    }
}

/// A Character's page, in the popover beside the Stat Block editor's name, for a Pawn
/// Stamped from it.
///
/// `MonsterReferenceView`'s twin, and like it reference and not state: every number the fight
/// depends on was copied into the Stat Block at the Stamp. What is shown is decided by
/// `AppState.characterPage(for:)`; this only lays it out. Never on the Player Display.
struct CharacterReferenceView: View {
    let page: CharacterPage
    /// The unit in force, which the note is checked against.
    let unit: DistanceUnit

    var body: some View {
        switch page {
        case .note(let note):
            ReferencePageView(name: note.name,
                              heading: CharacterReference.heading(of: note),
                              warning: note.warning(current: unit),
                              pictureProblem: note.picture?.problem,
                              lines: CharacterReference.lines(of: note),
                              abilities: CharacterReference.abilities(of: note),
                              groups: CharacterReference.groups(of: note))
                .accessibilityIdentifier("character-reference")
        case .unlinked(let characterName):
            ReferenceCaption(text: Text("“\(characterName)” has no note. Choose one with Edit… in the Party panel."))
                .accessibilityIdentifier("character-reference-unlinked")
        case .missing(let noteName):
            ReferenceCaption(text: Text("“\(noteName)” is not in the notes. Its numbers above are its own and are unaffected."))
                .accessibilityIdentifier("character-reference-missing")
        case .unavailable(let unavailable):
            // Already said in the interface language; shown as it is.
            ReferenceCaption(text: Text(unavailable))
        }
    }
}
