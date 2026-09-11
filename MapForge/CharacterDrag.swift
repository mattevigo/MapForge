import SwiftUI
import UniformTypeIdentifiers

/// What travels from the Party panel to the Map during a drag.
///
/// The app's first drag-and-drop of any kind — every other "drag" here is a `DragGesture`
/// inside one view. Carries only the Character's id: the roster is the one authority on what
/// a Character *is*, and putting its fields on the pasteboard would create a second, staler
/// copy for the drop to read.
///
/// A private `UTType` rather than plain text, so a file or a snippet of text dragged onto the
/// Map is refused by the type system rather than by hand-written validation that has to guess
/// what the DM meant.
extension UTType {
    static let partyCharacterID = UTType(exportedAs: "com.mattevigo.MapForge.character-id")
}

struct CharacterDragPayload: Codable, Transferable {
    let characterID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .partyCharacterID)
    }
}
