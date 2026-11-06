import CoreGraphics
import Foundation

/// The fields the Edit Pawn sheet offers, buffered until OK.
///
/// A draft rather than bindings straight onto the Pawn, because Live View edits are not
/// undoable (ADR-0013): Cancel is the only way back, so it has to discard rather than
/// un-apply. Editing a copy and committing it in one write is what makes that true — a
/// sheet that wrote through per keystroke would leave half the edit behind on Escape.
///
/// The six fields the fog editor's inspector had, less position — a Pawn is moved by dragging
/// it, which is a live action of its own — and its Face. A Face cut here is a draft like the
/// rest: only OK keeps the cut in the Workspace, so Cancel leaves no file behind.
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
    /// The Item this Treasure is, by name. Set through `pick` and `clearItem`, which keep the
    /// label in step with it, as they do a Monster's.
    private(set) var itemName: String?
    /// The Face the Pawn is drawn as, and any cut made in this sheet and not yet kept. Kept by
    /// OK alone (`AppState.updatePawn`), so Cancel leaves no cut of the Pawn's own in the
    /// Workspace — only, if the DM asked for it, the Monster's shared cut, which the next Pawn
    /// to take its Face would have made the same.
    var face: FaceDraft
    /// The DM's answer to "only this Pawn, or every one?" — true for every Pawn that took the
    /// Face from `recutSource`. Asked only when `asksWhomToRecut`.
    var recutsEvery = false
    /// Where the Face in the sheet came from, when a Monster, a Character or an Item gave
    /// it: whose picture "Re-cut…" opens, and whose cut "every" would change. Asked of the
    /// sheet as it stands — the Face taken or kept, and the Monster or Item it is now — never
    /// of the Pawn as it opened, so a Face taken here can be re-cut at once.
    var recutSource: FaceSource? {
        switch (face.kept ?? openedWithFace)?.origin {
        case .monster: monsterName.map { .monster($0) }
        case .character: characterID.map { .character($0) }
        case .item: itemName.map { .item($0) }
        case .hand, nil: nil
        }
    }
    /// The Character that Stamped the Pawn, whose Face a `character` one is.
    private let characterID: UUID?

    /// The Pawn being edited, so numbering a label does not count the label it is replacing.
    private let pawnID: Pawn.ID
    /// The Monster the Pawn had when the sheet opened — what decides whether OK stamps.
    private let openedWithMonster: String?
    /// The Item the Pawn had when the sheet opened — whose initials a label may carry.
    private let openedWithItem: String?
    /// The label the Pawn had when the sheet opened, to give back if a pick is undone.
    private let openedWithLabel: String
    /// The label the last `pick` wrote, so a second pick can tell the app's label from one
    /// the DM typed over it.
    private var pickedLabel: String?
    /// The Face the Pawn had when the sheet opened, to give back if a Monster's or an Item's
    /// Face taken here stops being this Pawn's Monster's or Item's.
    private let openedWithFace: PawnFace?
    /// The Monster or Item whose Face `takeMonsterFace` or `takeItemFace` gave in this sheet,
    /// while the Pawn still wears it — so picking another does not carry it onto that one.
    private var tookFaceFrom: FaceSource?

    init(pawn: Pawn) {
        pawnID = pawn.id
        label = pawn.label
        colorHex = pawn.colorHex
        kind = pawn.kind
        isBig = pawn.isBig
        sightSquares = pawn.light.brightSquares
        monsterName = pawn.monsterName
        itemName = pawn.itemName
        face = FaceDraft(pawn.face)
        openedWithFace = pawn.face
        characterID = pawn.characterID
        openedWithMonster = pawn.monsterName
        openedWithItem = pawn.itemName
        openedWithLabel = pawn.label
    }

    /// Say which Monster this Creature is, and show the DM what follows from it in the
    /// fields they can see: the size, and a label the app gave — the bare number the Pawn
    /// was born with, or the initials of the Monster it was — becomes "GG1". Both stay the
    /// DM's to overtype before OK.
    ///
    /// `pawns` is the Map as it stands, for the label's number.
    mutating func pick(_ monster: Monster, among pawns: [Pawn]) {
        monsterName = monster.name
        giveBackTakenFace(unlessFrom: .monster(monster.name))
        isBig = monster.isBig
        // A label this sheet wrote is not one the DM typed: changing one's mind from an
        // Ogre to a Gnoll should not leave the gnoll called "Og1".
        let replaceable = label == pickedLabel ? openedWithLabel : label
        let relabelled = MonsterStamp.label(for: monster, replacing: replaceable,
                                            from: openedWithMonster,
                                            among: pawns.filter { $0.id != pawnID })
        guard relabelled != replaceable else { return }
        label = relabelled
        pickedLabel = relabelled
    }

    /// Forget the Monster. The Stat Block is not touched — a copy is not un-copied — and a
    /// label this sheet wrote goes back to what it replaced.
    mutating func clearMonster() {
        monsterName = nil
        giveBackTakenFace(unlessFrom: nil)
        if label == pickedLabel { label = openedWithLabel }
        pickedLabel = nil
    }

    /// Say which Item this Treasure is, and show the DM what follows from it: a label the app
    /// gave — the bare number, or the initials of the Item it was — becomes "Bo1", by the
    /// rule a Monster's label follows. There is nothing else to show: an Item has no numbers.
    /// Its Face is given on OK (`AppState.updatePawn`), as a Monster's is.
    ///
    /// `pawns` is the Map as it stands, for the label's number.
    mutating func pick(_ item: Item, among pawns: [Pawn]) {
        itemName = item.name
        giveBackTakenFace(unlessFrom: .item(item.name))
        let replaceable = label == pickedLabel ? openedWithLabel : label
        let relabelled = ItemStamp.label(for: item, replacing: replaceable, from: openedWithItem,
                                         among: pawns.filter { $0.id != pawnID })
        guard relabelled != replaceable else { return }
        label = relabelled
        pickedLabel = relabelled
    }

    /// Forget the Item. A label this sheet wrote goes back to what it replaced.
    mutating func clearItem() {
        itemName = nil
        giveBackTakenFace(unlessFrom: nil)
        if label == pickedLabel { label = openedWithLabel }
        pickedLabel = nil
    }

    /// The Item OK makes the Treasure, or nil when the Item is untouched — whose Face OK
    /// gives (`AppState.updatePawn`). Only an Item that *changed*, as `monsterToStamp` is.
    var itemToBecome: String? {
        guard kind.canBeItem, itemName != openedWithItem else { return nil }
        return itemName
    }

    /// Whether OK must ask "only this Pawn, or every one?" (ADR-0028).
    ///
    /// Only over a Face a Monster, a Character or an Item gave, and only for a cut that could
    /// be that definition's: a Monster's or an Item's Face is the picture its note names, so
    /// only that picture cut again; a Character's own Face may be any picture. A Face cut by
    /// hand, or another picture over a Monster's or an Item's, is this Pawn's alone and is cut
    /// without asking. Never while the Pawn becomes another Monster or another Item, whose
    /// Face is the new one's: the cut would be asked about under the new one's name, and
    /// "every" would overwrite a cut that was never this Face's.
    var asksWhomToRecut: Bool {
        guard face.newCut != nil, monsterToStamp == nil, itemToBecome == nil else { return false }
        switch recutSource {
        case .monster, .item: return face.isRecut
        case .character: return true
        case nil: return false
        }
    }

    /// Whether the sheet offers to give the Pawn `monster`'s Face — the Monster it is now.
    ///
    /// A Creature takes its Monster's Face on *becoming* it, so one that already was before
    /// Faces existed, or whose Face the DM removed, would otherwise have no way to get it but
    /// to become another Monster and back, healed on the way. Never offered silently: Pawns
    /// already on a Map keep the Face they have until the DM says otherwise (ADR-0028). Not
    /// offered when the Pawn already wears that Monster's Face, or the note names no picture
    /// the Workspace holds.
    func offersMonsterFace(of monster: Monster?) -> Bool {
        guard kind.canBeMonster, let monster, monster.name == monsterName,
              monster.picture?.path != nil else { return false }
        return !wears(.monster(monster.name), openedWith: openedWithMonster.map { .monster($0) })
    }

    /// Give the Pawn `face`, the Face of the Monster named `name` that it is.
    mutating func takeMonsterFace(_ face: PawnFace, of name: String) {
        self.face.take(face)
        tookFaceFrom = .monster(name)
    }

    /// Whether the sheet offers to give the Treasure `item`'s Face — the Item it is now.
    ///
    /// `offersMonsterFace(of:)` for a Treasure, and for the same reason: one that was already
    /// the Item before its note named a picture, or whose Face the DM removed, has no other
    /// way to get it. Not offered when the Treasure already wears that Item's Face, or the
    /// note names no picture the Workspace holds.
    func offersItemFace(of item: Item?) -> Bool {
        guard kind.canBeItem, let item, item.name == itemName,
              item.picture?.path != nil else { return false }
        return !wears(.item(item.name), openedWith: openedWithItem.map { .item($0) })
    }

    /// Give the Treasure `face`, the Face of the Item named `name` that it is.
    mutating func takeItemFace(_ face: PawnFace, of name: String) {
        self.face.take(face)
        tookFaceFrom = .item(name)
    }

    /// Whether the sheet's Face is `source`'s: taken from it here, or — with nothing taken —
    /// worn since the sheet opened, when the Pawn already was `opened`.
    private func wears(_ source: FaceSource, openedWith opened: FaceSource?) -> Bool {
        face.newCut == nil && face.kept?.origin == source.origin
            && (tookFaceFrom ?? opened) == source
    }

    /// The Face the sheet opened with back, when a Monster's or an Item's Face taken here
    /// would otherwise follow the Pawn onto `source` — whose Face OK then gives by the usual
    /// rule. Left alone once the DM has cut or removed a Face since: that is theirs.
    private mutating func giveBackTakenFace(unlessFrom source: FaceSource?) {
        guard let taken = tookFaceFrom, taken != source else { return }
        if face.newCut == nil, face.kept?.origin == taken.origin {
            face = FaceDraft(openedWithFace)
        }
        tookFaceFrom = nil
    }

    /// The Monster OK must stamp, or nil when it must not.
    ///
    /// Only a Monster that *changed*: OK with it untouched leaves the Stat Block untouched,
    /// or opening a wounded gnoll to change its colour would heal it.
    var monsterToStamp: String? {
        guard kind.canBeMonster, monsterName != openedWithMonster else { return nil }
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
        edited.monsterName = kind.canBeMonster ? monsterName : nil
        // And only a Treasure can be an Item, for the same reason.
        edited.itemName = kind.canBeItem ? itemName : nil
        // A removed Face goes; a pending cut is not a Face until OK has kept it, which is
        // `AppState.updatePawn`'s to do, so here it leaves the Face the sheet opened with.
        edited.face = face.kept
        // Sight is one number, and the dim value is the cosmetic feather derived from it —
        // never set independently, because a character's sight is not a light source. Both
        // move together or the halo stays at whatever the Pawn was created with.
        edited.light.brightSquares = max(0, sightSquares)
        edited.light.dimSquares = Pawn.dimSquares(forSight: sightSquares)
        return edited
    }
}

/// A Face being given, cut or taken away in an editor — the Edit Pawn sheet, or a Character's
/// editor in the Party panel — buffered until that editor's OK or Save.
///
/// One type for both, because cutting a Face is the same act whoever will wear it: a new cut
/// starts as the centred square, stays square and inside the picture however it is moved or
/// resized, and is kept in the Workspace only when the edit is committed (`resolved`).
struct FaceDraft: Equatable {
    /// The Face as the editor opened with it — or nil once removed.
    private(set) var kept: PawnFace?
    /// A Face picked and cut in this editor, not yet kept.
    private(set) var newCut: PendingFaceCut?
    /// The Face the editor opened with, so a commit can tell what the DM did to it.
    private let opened: PawnFace?
    /// Whether `newCut` is the picture the Face was cut from, cut again — rather than another
    /// picture chosen.
    private(set) var isRecut = false

    init(_ kept: PawnFace?) {
        self.kept = kept
        opened = kept
    }

    /// Whether there will be a Face once the edit is committed.
    var hasFace: Bool { kept != nil || newCut != nil }

    /// Whether the DM removed the Face or cut a new one in this editor — a decision about the
    /// Face that nothing else committed alongside it should undo.
    var isChanged: Bool { kept != opened || newCut != nil }

    /// Start a cut from `picture`: the largest centred square, for the DM to move and resize.
    mutating func choosePicture(_ picture: CGImage) {
        newCut = PendingFaceCut(picture: picture,
                                cut: FaceCut.centredSquare(in: picture.pixelSize))
        isRecut = false
    }

    /// Cut again the picture the Face was cut from, starting from the square it was cut as.
    mutating func recut(_ picture: CGImage, from square: CGRect) {
        newCut = PendingFaceCut(picture: picture,
                                cut: FaceCut.clamped(square, in: picture.pixelSize))
        isRecut = true
    }

    /// Place the pending cut, kept square and inside the picture.
    mutating func setCut(_ cut: CGRect) {
        adjustCut { FaceCut.clamped(cut, in: $1) }
    }

    /// Resize the pending cut about its centre.
    mutating func resizeCut(toSide side: CGFloat) {
        adjustCut { FaceCut.resized($0, toSide: side, in: $1) }
    }

    /// `newCut` with its square replaced by what `change` makes of it and the picture's size.
    private mutating func adjustCut(_ change: (CGRect, CGSize) -> CGRect) {
        guard var pending = newCut else { return }
        pending.cut = change(pending.cut, pending.picture.pixelSize)
        newCut = pending
    }

    /// Wear `face`, a cut already kept — the Face of the Monster the Pawn is — in place of
    /// whatever the editor holds.
    mutating func take(_ face: PawnFace) {
        kept = face
        newCut = nil
        isRecut = false
    }

    /// Take the Face away: its wearer is drawn in its colour again, which was never touched.
    mutating func remove() {
        kept = nil
        newCut = nil
        isRecut = false
    }

    /// The Face the committed edit leaves: a new cut kept in `library`, or else the Face the
    /// editor opened with, if it was not removed.
    ///
    /// A cut that cannot be kept — no Workspace, or a write that failed — leaves the Face the
    /// editor opened with, rather than naming a file never written.
    func resolved(keepingIn library: FaceLibrary?) -> PawnFace? {
        guard let pending = newCut, let library,
              let face = try? library.keep(pending.picture, cut: pending.cut) else { return kept }
        return face
    }
}

/// A Face picked and cut in an editor and not yet kept: the picture, and the square
/// of it the DM has chosen, in its pixels.
///
/// The picture itself rather than where it came from, read once when it was chosen: OK then
/// cuts exactly what the DM was shown, even if the file has been moved or deleted since.
struct PendingFaceCut: Equatable {
    let picture: CGImage
    var cut: CGRect

    /// The same picture, not merely an equal one: two reads of a file are two pictures.
    static func == (lhs: PendingFaceCut, rhs: PendingFaceCut) -> Bool {
        lhs.picture === rhs.picture && lhs.cut == rhs.cut
    }
}

extension CGImage {
    /// The picture's size in pixels — the space a Face's cut is measured in.
    var pixelSize: CGSize { CGSize(width: width, height: height) }
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
