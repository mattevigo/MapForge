import SwiftUI

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

/// A Character's page, as the DM reads it mid-fight — the text, apart from the view that lays
/// it out. `MonsterReference` for a Player: the note's own words and nothing computed from
/// them, so "what's my spell save DC again?" is answered without asking the player.
enum CharacterReference {
    /// Under the name, as a Monster's page gives size · type · alignment: who this is.
    static func heading(of note: CharacterNote) -> String {
        [note.species,
         note.characterClass,
         note.level.map { String(localized: "Level \($0)", comment: "A Character's level, under its name") }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The one-line facts above the Traits. Only what the note has. Armour class and hit
    /// points are not repeated: the Stat Block editor directly above shows the Pawn's own.
    static func lines(of note: CharacterNote) -> [MonsterReference.Line] {
        let candidates: [(String, String?)] = [
            (String(localized: "Speed"), note.speed),
            (String(localized: "Saves"), MonsterReference.bonuses(note.saves)),
            (String(localized: "Skills"), MonsterReference.bonuses(note.skills)),
            (String(localized: "Senses"), note.senses),
            (String(localized: "Languages"), note.languages),
        ]
        return candidates.compactMap { label, value in
            value.map { MonsterReference.Line(label: label, value: $0) }
        }
    }

    /// Traits and Actions as a Monster's are; Spells as the plain lines the note writes.
    static func groups(of note: CharacterNote) -> [MonsterReference.Group] {
        [MonsterReference.features(String(localized: "Traits"), note.traits),
         MonsterReference.features(String(localized: "Actions"), note.actions),
         MonsterReference.Group(title: String(localized: "Spells"),
                                paragraphs: note.spells.map(MonsterReference.Paragraph.plain))]
            .filter { !$0.paragraphs.isEmpty }
    }
}

/// A Character's page under the Stat Block editor, for a Pawn Stamped from it.
///
/// `MonsterReferenceView`'s twin, and like it reference and not state: every number the fight
/// depends on was copied into the Stat Block at the Stamp. What is shown is decided by
/// `AppState.characterPage(for:)`; this only lays it out. Never on the Player Display.
struct CharacterReferenceView: View {
    let page: CharacterPage

    var body: some View {
        switch page {
        case .note(let note):
            ReferencePageView(name: note.name,
                              heading: CharacterReference.heading(of: note),
                              lines: CharacterReference.lines(of: note),
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
