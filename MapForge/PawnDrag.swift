import SwiftUI
import UniformTypeIdentifiers

/// What travels when the DM drags a Pawn's row in the Scene tab to reorder it (`PawnOrder`).
///
/// Its own private `UTType`, as `CharacterDragPayload` has, so the Map's drop — which takes a
/// Party Character and stamps it — refuses a Pawn's row by type rather than stamping a copy
/// of it, and the rows refuse a Character, text or a file the same way. Only the id travels:
/// `fog.pawns` is the one authority on where the Pawn is now.
extension UTType {
    static let pawnID = UTType(exportedAs: "com.mattevigo.MapForge.pawn-id")
}

struct PawnDragPayload: Codable, Transferable {
    let pawnID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pawnID)
    }
}
