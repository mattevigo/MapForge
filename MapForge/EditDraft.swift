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
/// dragging it, which is a live action of its own.
///
/// **No Stat Block field is here, and none may be added.** The numbers live in their own file
/// and have their own editor (ADR-0009); a hit point total half-typed into this sheet and
/// then met by Cancel is where save semantics get murky. What *is* here is the Monster's
/// name, and that is a narrower thing: naming a Monster makes OK perform one whole-value
/// stamp (`MonsterStamp`, in `AppState.updatePawn`), which is an act rather than an edit. OK
/// still commits everything the sheet shows and Cancel still commits nothing. See ADR-0021.
struct EditPawnDraft: Equatable {
    var label: String
    var colorHex: String
    var kind: PawnKind
    var isBig: Bool
    var sightSquares: CGFloat
    /// The Monster this Creature is, by name. Set through `pick` and `clearMonster`, which
    /// keep the label and the size in step with it.
    private(set) var monsterName: String?

    /// The Monster the Pawn had when the sheet opened — what decides whether OK stamps.
    private let openedWithMonster: String?
    /// The label the Pawn had when the sheet opened, to give back if a pick is undone.
    private let openedWithLabel: String
    /// The label the last `pick` wrote, so a second pick can tell the app's label from one
    /// the DM typed over it.
    private var pickedLabel: String?

    init(pawn: Pawn) {
        label = pawn.label
        colorHex = pawn.colorHex
        kind = pawn.kind
        isBig = pawn.isBig
        sightSquares = pawn.light.brightSquares
        monsterName = pawn.monsterName
        openedWithMonster = pawn.monsterName
        openedWithLabel = pawn.label
    }

    /// Say which Monster this Creature is, and show the DM what follows from it in the
    /// fields they can see: the size, and a label still the bare number the Pawn was born
    /// with becomes "GG1". Both stay the DM's to overtype before OK.
    ///
    /// `pawns` is the Map as it stands, for the label's number.
    mutating func pick(_ monster: Monster, among pawns: [Pawn]) {
        monsterName = monster.name
        isBig = monster.isBig
        // A label this sheet wrote is not one the DM typed: changing one's mind from an
        // Ogre to a Gnoll should not leave the gnoll called "Og1".
        let replaceable = label == pickedLabel ? openedWithLabel : label
        let relabelled = MonsterStamp.label(for: monster, replacing: replaceable, among: pawns)
        guard relabelled != replaceable else { return }
        label = relabelled
        pickedLabel = relabelled
    }

    /// Forget the Monster. The Stat Block is not touched — a copy is not un-copied — and a
    /// label this sheet wrote goes back to what it replaced.
    mutating func clearMonster() {
        monsterName = nil
        if label == pickedLabel { label = openedWithLabel }
        pickedLabel = nil
    }

    /// The Monster OK must stamp, or nil when it must not.
    ///
    /// Only a Monster that *changed*: OK with it untouched leaves the Stat Block untouched,
    /// or opening a wounded gnoll to change its colour would heal it.
    var monsterToStamp: String? {
        guard kind == .creature, monsterName != openedWithMonster else { return nil }
        return monsterName
    }

    /// What OK would do to hit points that already exist, or nil when there is nothing to
    /// ask: the Monster is untouched, it has left the Bestiary, or nothing would be lost.
    /// `existing` is the Pawn's Stat Block as it stands — the fight's copy, mid-Encounter.
    func healing(over existing: StatBlock, in bestiary: Bestiary) -> MonsterStamp.Healing? {
        bestiary.monster(named: monsterToStamp)
            .flatMap { MonsterStamp.healing(from: $0, over: existing) }
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
        // Only a Creature can be a Monster (`CONTEXT.md`). The search box is hidden for the
        // other Kinds, and the memory goes with it rather than lingering unseen.
        edited.monsterName = kind == .creature ? monsterName : nil
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
