import CoreGraphics
import Foundation

/// The fields the Edit Pawn sheet offers, buffered until OK.
///
/// A draft rather than bindings straight onto the Pawn, because Live View edits are not
/// undoable (ADR-0013): Cancel is the only way back, so it has to discard rather than
/// un-apply. Editing a copy and committing it in one write is what makes that true — a
/// sheet that wrote through per keystroke would leave half the edit behind on Escape.
///
/// Exactly the six fields the fog editor's inspector had, less position: a Pawn is moved by
/// dragging it, which is a live action of its own. The Stat Block is not here — it lives in
/// its own file and has its own editor (ADR-0009), and one OK button writing two
/// persistence layers is where save semantics get murky.
struct EditPawnDraft: Equatable {
    var label: String
    var colorHex: String
    var kind: PawnKind
    var isBig: Bool
    var sightSquares: CGFloat

    init(pawn: Pawn) {
        label = pawn.label
        colorHex = pawn.colorHex
        kind = pawn.kind
        isBig = pawn.isBig
        sightSquares = pawn.light.brightSquares
    }

    /// The Pawn as this draft would leave it. Everything the sheet does not offer — its
    /// identity, where it stands, its torch, the eye, the Character it was stamped from —
    /// comes through untouched.
    func applied(to pawn: Pawn) -> Pawn {
        var edited = pawn
        edited.label = label
        edited.colorHex = colorHex
        edited.kind = kind
        edited.isBig = isBig
        // Sight is one number, and the dim value is the cosmetic feather derived from it —
        // never set independently, because a character's sight is not a light source. Both
        // move together or the halo stays at whatever the Pawn was created with.
        edited.light.brightSquares = max(0, sightSquares)
        edited.light.dimSquares = Pawn.dimSquares(forSight: sightSquares)
        return edited
    }
}

/// The fields the Edit Light sheet offers, buffered until OK.
///
/// A Light has two radii where a Pawn has one, because a torch really does have a bright
/// band and a dim one — so both are carried and neither is derived from the other. That is
/// the trap this type exists to avoid: `Light.init` defaults dim to twice bright, so
/// re-deriving it on commit would silently double a dim radius a DM had deliberately set
/// equal to bright.
struct EditLightDraft: Equatable {
    var name: String
    var brightSquares: CGFloat
    var dimSquares: CGFloat
    var isOn: Bool

    init(light: Light) {
        name = light.name ?? ""
        brightSquares = light.brightSquares
        // The stored value, never `bright * 2`. See the type's note.
        dimSquares = light.dimSquares
        isOn = light.isOn
    }

    func applied(to light: Light) -> Light {
        var edited = light
        // Blank — empty or whitespace — is nil, exactly as `AppState.setLightName` treats
        // it: "unnamed" must have one representation, or the roster's positional fallback
        // fires for nil and not for "". What is not blank is kept as typed.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.name = trimmed.isEmpty ? nil : name
        edited.brightSquares = max(0, brightSquares)
        edited.dimSquares = max(0, dimSquares)
        edited.isOn = isOn
        return edited
    }
}
