import Foundation

/// The roster's own logic, kept out of the view: what the Party panel counts, and how a
/// `PartyBook` changes when the DM edits it.
///
/// Free functions on a caseless enum rather than a view model, matching how this app already
/// tests view logic (`FogInspectorRowHeight`, `LiveRowSymbol`): the decisions are pure, the
/// SwiftUI around them is a thin shell.
enum PartyRoster {
    // MARK: What the panel shows

    /// How many Pawns on the current Map were Stamped from this Character.
    ///
    /// Matched on the Character's id, never its name: renaming a Pawn live in the sidebar is
    /// something the DM can already do, and a count that silently went wrong when they did
    /// would be worse than no count. Shown only when non-zero — it is a glance at who is
    /// already on the table, and it forbids nothing: duplicates are deliberate.
    static func placedCount(of character: PartyCharacter, among pawns: [Pawn]) -> Int {
        pawns.filter { $0.characterID == character.id }.count
    }

    // MARK: Editing the roster

    /// The Party the panel should offer: the remembered one, or the first, or none.
    ///
    /// A remembered ID naming a Party that has since been deleted resolves here rather than
    /// in `DisplayPreferences` — deleting a Party must not have to reach into preferences to
    /// keep the app consistent.
    ///
    /// A dangling ID **falls back to the first Party** rather than to none. That is a
    /// different question from the one `DisplayPreferences.activePartyID` answers, which is
    /// whether a malformed stored *string* is an ID at all (it resolves to nil there). Here
    /// the ID parsed fine and simply names a Party that is gone, and showing an empty panel
    /// beside a roster that exists would read as the feature being broken. The DM can still
    /// pick any Party from the picker.
    static func activeParty(in book: PartyBook, id: UUID?) -> Party? {
        if let id, let party = book.parties.first(where: { $0.id == id }) { return party }
        return book.parties.first
    }

    static func addParty(named name: String, to book: PartyBook) -> (PartyBook, Party) {
        let party = Party(name: name)
        var book = book
        book.parties.append(party)
        return (book, party)
    }

    static func renameParty(id: UUID, to name: String, in book: PartyBook) -> PartyBook {
        var book = book
        guard let index = book.parties.firstIndex(where: { $0.id == id }) else { return book }
        book.parties[index].name = name
        return book
    }

    /// Deletes a Party. Pawns Stamped from its Characters are untouched — they live in the
    /// Map's own file and know nothing about the roster. See ADR 0007.
    static func deleteParty(id: UUID, from book: PartyBook) -> PartyBook {
        var book = book
        book.parties.removeAll { $0.id == id }
        return book
    }

    static func addCharacter(_ character: PartyCharacter,
                             toPartyWith partyID: UUID,
                             in book: PartyBook) -> PartyBook {
        var book = book
        guard let index = book.parties.firstIndex(where: { $0.id == partyID }) else { return book }
        book.parties[index].characters.append(character)
        return book
    }

    /// Replaces a Character in place, keeping its position in the DM's order.
    ///
    /// Pawns already Stamped from it are deliberately not revisited: a Stamp is a copy taken
    /// at the moment of the drag, so renaming Thorin today leaves last week's map exactly as
    /// it was run. That silence is the decision, not an oversight.
    ///
    /// Searches every Party rather than the active one, and stops at the first match. A
    /// Character belongs to exactly one Party, so "which Party is active" is not part of the
    /// question — making it so would mean an edit silently doing nothing if the DM switched
    /// Party while the editor was open.
    static func updateCharacter(_ character: PartyCharacter, in book: PartyBook) -> PartyBook {
        var book = book
        for partyIndex in book.parties.indices {
            guard let index = book.parties[partyIndex].characters
                .firstIndex(where: { $0.id == character.id }) else { continue }
            book.parties[partyIndex].characters[index] = character
            return book
        }
        return book
    }

    /// Deletes a Character. Its Pawns stay on their Maps, fully functional; they only stop
    /// being counted.
    static func deleteCharacter(id: UUID, in book: PartyBook) -> PartyBook {
        var book = book
        for partyIndex in book.parties.indices {
            book.parties[partyIndex].characters.removeAll { $0.id == id }
        }
        return book
    }
}
