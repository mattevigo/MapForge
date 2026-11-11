import AppKit
import SwiftUI

/// Editing a Pawn's fields, as a modal sheet on the Control Window.
///
/// **The app's first modal, deliberately.** `ControlView` carried a standing "this app has
/// no modals, and one text field does not justify introducing the first" — written when
/// every editor was one or two controls on a row above the preview that had to reserve
/// constant height or the Map jumped mid-click. A five-field form is the case that stance
/// was not written against, and a sheet sidesteps the height problem entirely rather than
/// working around it.
///
/// A popover was the alternative and was rejected: it dismisses on an outside click, which
/// is hostile in the middle of a text field. The cost of the sheet is accepted — while it
/// is up the DM cannot see their own Map, though the Player Display is a separate window
/// and carries on unaffected.
///
/// **Buffered.** The draft is edited and committed in one write on OK, because Live View
/// edits are not undoable (ADR-0013): Cancel is the only way back, so it has to discard
/// rather than un-apply.
///
/// **A Creature can be said to be a Monster here**, in a search box beside the Kind. That
/// makes OK stamp the Monster's numbers into the Stat Block as well — still one commit, and
/// still nothing on Cancel — and because a stamp arrives at full hit points, OK asks first
/// when that would overwrite hit points that exist. See ADR-0021.
///
/// **A Treasure can be said to be an Item** in the same place, from the Treasury (ADR-0031).
/// There are no numbers to stamp, so there is no heal to ask about, and OK is simply OK.
struct EditPawnSheet: View {
    @State var draft: EditPawnDraft
    /// Whether a Grid has been declared. Sight is measured in Grid squares, so without one
    /// the number is inert — said plainly rather than by refusing the edit.
    let hasDeclaredGrid: Bool
    /// What the sight is typed and shown in.
    let unit: DistanceUnit
    /// What the search box searches.
    var bestiary = Bestiary.closed
    /// What a Treasure's search box searches.
    var treasury = Treasury.closed
    /// The Map as it stands, for numbering a picked Monster's label.
    var pawns: [Pawn] = []
    /// The Pawn's Stat Block as it stands, for knowing whether a stamp would heal it.
    var statBlock = StatBlock()
    /// The unit every note in the Workspace agrees on, when it is not `unit`.
    let suggestedUnit: DistanceUnit?
    let onSwitchUnit: (DistanceUnit) -> Void
    /// Where the Pawn's Face is kept, for showing it. Nil with no Workspace open, when there
    /// is nowhere to keep a cut and so no picture is offered.
    var faceLibrary: FaceLibrary?
    /// What the sheet asks of the Monsters', Items' and Characters' Faces. Nil with no
    /// Workspace open.
    var definitionFaces: DefinitionFaces?
    let onCommit: (EditPawnDraft) -> Void
    let onCancel: () -> Void

    /// Whether the DM is in the middle of a search. While they are, Return belongs to the
    /// search box — it picks a Monster, or does nothing when the query matches none — and
    /// must not also press OK on a half-typed name.
    @State private var isSearching = false
    /// The heal OK is waiting on the DM to confirm.
    @State private var confirming: MonsterStamp.Healing?
    /// Whether OK is waiting on "only this Pawn, or every one?".
    @State private var askingWhomToRecut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Pawn").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Label")
                    TextField("label", text: $draft.label)
                        .accessibilityIdentifier("edit-pawn-label")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                GridRow {
                    Text("Colour")
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: draft.colorHex) ?? .red },
                        set: { draft.colorHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                // Aligned on the baseline rather than centred: the Monster's cell grows a
                // caption when the Bestiary has something to say, and a centred picker would
                // drift down beside it.
                GridRow(alignment: .firstTextBaseline) {
                    Text("Kind")
                    // A picker, not two toggles: the three kinds are mutually exclusive, and
                    // a pair of checkboxes would let a DM tick both and leave the token in a
                    // state the model cannot represent.
                    Picker("", selection: $draft.kind) {
                        ForEach(PawnKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .help("A Creature or a Treasure emits no Light and is hidden from players by darkness.")
                    // Only a Creature can be a Monster: a Player's numbers come from its
                    // Character, and a Treasure has none.
                    if draft.kind.canBeMonster {
                        MonsterSearchField(bestiary: bestiary,
                                           unit: unit,
                                           suggestedUnit: suggestedUnit,
                                           onSwitchUnit: onSwitchUnit,
                                           monsterName: draft.monsterName,
                                           isSearching: $isSearching,
                                           onPick: { draft.pick($0, among: pawns) },
                                           onClear: { draft.clearMonster() })
                            .gridCellAnchor(.topLeading)
                            // Above the rows below it, which the open results float over.
                            .zIndex(1)
                    } else if draft.kind.canBeItem {
                        // And only a Treasure can be an Item.
                        ItemSearchField(treasury: treasury,
                                        itemName: draft.itemName,
                                        isSearching: $isSearching,
                                        onPick: { draft.pick($0, among: pawns) },
                                        onClear: { draft.clearItem() })
                            .gridCellAnchor(.topLeading)
                            .zIndex(1)
                    }
                }
                GridRow {
                    Text("Size")
                    Toggle("Big", isOn: $draft.isBig)
                        .help("Occupies 2×2 squares instead of 1×1. Visual only — its light and sight are unchanged.")
                }
                GridRow(alignment: .top) {
                    Text("Face")
                    FaceEditor(face: $draft.face, kind: draft.kind, library: faceLibrary,
                               wearer: .pawn, recutPicture: recutPicture,
                               useMonsterFace: useMonsterFace, useItemFace: useItemFace)
                        // Across the Monster's column, as the Sight row is: the cut is the
                        // widest thing the sheet shows.
                        .gridCellColumns(2)
                }
                GridRow {
                    Text("Sight")
                    // A Pawn has one radius. The extra square the region fades over is not
                    // a second number the DM sets — it is there so the edge is not a hard
                    // cut — so it is not offered as one.
                    DistanceField($draft.sightSquares, unit: unit,
                                  caption: draft.kind.isDiscovered
                                      ? (draft.kind == .treasure
                                         ? String(localized: "\(unit.symbol) — unused, a Treasure emits no Light")
                                         : String(localized: "\(unit.symbol) — unused, a Creature emits no Light"))
                                      : unit.symbol)
                        // Across the Monster's column too, or this caption — the longest
                        // thing in the form — would set the second column's width and push
                        // the search box off the sheet.
                        .gridCellColumns(2)
                }
            }

            // Above the buttons as well, for the same reason.
            .zIndex(1)

            if !hasDeclaredGrid {
                Text("No Grid declared, so this sight has no physical size yet.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: commit)
                    // Return belongs to the search results while they are open.
                    .keyboardShortcut(isSearching ? nil : .defaultAction)
                    .accessibilityIdentifier("edit-pawn-ok")
            }
        }
        .padding(20)
        // Wider than the Light's sheet by the Monster's column.
        .frame(width: 540)
        // Never together with the heal below: a Pawn becoming another Monster takes that
        // Monster's Face, and so is never asked whom a re-cut is for.
        .alert("Who takes the new cut?", isPresented: $askingWhomToRecut) {
            Button(recutQuestion?.onlyThis ?? String(localized: "Only This Pawn")) {
                draft.recutsEvery = false
                onCommit(draft)
            }
            if let recutQuestion {
                Button(recutQuestion.every) {
                    draft.recutsEvery = true
                    onCommit(draft)
                }
            }
            // Back to the open sheet, as the heal's Cancel is.
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recutQuestion?.message ?? "")
        }
        .alert("Heal \(draft.label)?",
               isPresented: Binding(get: { confirming != nil },
                                    set: { if !$0 { confirming = nil } }),
               presenting: confirming) { _ in
            Button(draft.monsterName.map { String(localized: "Become \($0)") }
                   ?? String(localized: "Become a Monster")) { onCommit(draft) }
            // Back to the open sheet, where the pick can be undone — not out of it.
            Button("Cancel", role: .cancel) {}
        } message: { healing in
            // Whole sentences, never an article before a spliced name: a Monster's name has
            // a gender the app cannot know.
            Text(draft.monsterName.map {
                String(localized: "A Pawn that becomes \($0) arrives whole: \(healing.before) becomes \(healing.after). Conditions and temporary hit points are kept.")
            } ?? String(localized: "Becoming a Monster means arriving whole: \(healing.before) becomes \(healing.after). Conditions and temporary hit points are kept."))
        }
    }

    /// Gives the Pawn its Monster's Face, when the sheet offers it — false when the Face
    /// could not be had after all.
    private var useMonsterFace: (() -> Bool)? {
        let monster = bestiary.monster(named: draft.monsterName)
        guard let monster, let faces = definitionFaces, draft.offersMonsterFace(of: monster)
        else { return nil }
        return {
            guard let face = faces.monsterFace(monster) else { return false }
            draft.takeMonsterFace(face, of: monster.name)
            return true
        }
    }

    /// Gives the Treasure its Item's Face, when the sheet offers it — false when the Face
    /// could not be had after all.
    private var useItemFace: (() -> Bool)? {
        let item = treasury.item(named: draft.itemName)
        guard let item, let faces = definitionFaces, draft.offersItemFace(of: item)
        else { return nil }
        return {
            guard let face = faces.itemFace(item) else { return false }
            draft.takeItemFace(face, of: item.name)
            return true
        }
    }

    /// The picture the Face in the sheet was cut from, as its note names it now, for cutting
    /// it again — nil when it keeps none, as a Face cut by hand does.
    private var recutPicture: (() -> PendingFaceCut?)? {
        guard let source = draft.recutSource, let faces = definitionFaces,
              faces.canRecut(source) else { return nil }
        return { faces.recutPicture(source) }
    }

    /// "Only this Pawn, or every one?", asked of the Monster, Character or Item "every"
    /// re-cuts — nil when the Face came from none still defined, and there is nothing to ask.
    private var recutQuestion: RecutQuestion? {
        guard let source = draft.recutSource, let name = definitionFaces?.name(source)
        else { return nil }
        return RecutQuestion(source, named: name)
    }

    /// OK. Asks first only when the stamp would overwrite hit points that exist — a dialog
    /// that appears when nothing can be lost is one the DM learns to click through.
    private func commit() {
        if draft.asksWhomToRecut, recutQuestion != nil {
            askingWhomToRecut = true
        } else if let healing = draft.healing(over: statBlock, in: bestiary) {
            confirming = healing
        } else {
            onCommit(draft)
        }
    }
}

/// What the Edit Pawn sheet asks of the Faces Monsters, Items and Characters give, answered by
/// `AppState`, which holds the notes and the cuts.
struct DefinitionFaces {
    /// The Face of a Monster, its picture cut now if no Pawn has taken it yet. That cut is
    /// the Monster's, shared by every Pawn that takes its Face, so it is no litter if the
    /// sheet is cancelled.
    var monsterFace: (Monster) -> PawnFace?
    /// The Face of an Item, its picture cut now if no Treasure has taken it yet — shared as a
    /// Monster's is.
    var itemFace: (Item) -> PawnFace?
    /// Whether the source's note names a picture to cut again, without reading it.
    var canRecut: (FaceSource) -> Bool
    /// That picture, read, with the square to start from.
    var recutPicture: (FaceSource) -> PendingFaceCut?
    /// The name "every" is offered under, or nil when the definition has gone.
    var name: (FaceSource) -> String?
}

/// Choose a picture, cut a square of it, or take the Face away — for a Pawn in the Edit Pawn
/// sheet, or for a Character in the Party panel.
///
/// Nothing of the wearer's own is kept here: the cut is a draft until the editor's OK or Save,
/// and only that copies the square into the Workspace (`FaceDraft.resolved`), so Cancel leaves
/// no file behind. The one exception is "Use the Monster's Face", which may make the Monster's
/// shared cut — the cut the next Pawn to take that Face would make the same — and "Use the
/// Item's Face", which may make the Item's.
struct FaceEditor: View {
    @Binding var face: FaceDraft
    /// The shape the Face will be worn in.
    let kind: PawnKind
    /// Where the Face is kept, for showing it. Nil with no Workspace open, when there is
    /// nowhere to keep a cut and so no picture is offered.
    let library: FaceLibrary?
    let wearer: Wearer
    /// The picture the Face was cut from and its square, when it keeps one — a Face cut from
    /// a note's picture. Offers "Re-cut…" when there is one.
    var recutPicture: (() -> PendingFaceCut?)? = nil
    /// Gives the wearer the Face of the Monster it is, when it may take it, reporting whether
    /// it could. Offers "Use the Monster's Face" when there is one.
    var useMonsterFace: (() -> Bool)? = nil
    /// The same for a Treasure and the Item it is. Offers "Use the Item's Face".
    var useItemFace: (() -> Bool)? = nil

    /// Who will wear the Face, which is all that changes what the editor says.
    enum Wearer {
        case pawn, character

        fileprivate var identifier: String {
            switch self {
            case .pawn: "edit-pawn"
            case .character: "character"
            }
        }

        fileprivate var pickerMessage: String {
            switch self {
            case .pawn: String(localized: "Choose the picture to cut this Pawn's Face from.")
            case .character: String(localized: "Choose the picture to cut this Character's Face from.")
            }
        }

        fileprivate var caption: String {
            switch self {
            case .pawn: String(localized: "Covers the Pawn on both screens, colour and label alike.")
            case .character: String(localized: "Every Pawn stamped from it afterwards wears a copy.")
            }
        }
    }

    /// Whether the last picture chosen could not be read.
    @State private var pictureFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pending = face.newCut {
                FaceCutter(pending: pending, kind: kind,
                           identifier: "\(wearer.identifier)-face-cutter",
                           onCut: { face.setCut($0) },
                           onResize: { face.resizeCut(toSide: $0) })
            } else if let kept = face.kept, let image = library?.image(for: kept) {
                FaceThumbnail(image: Image(nsImage: image), kind: kind)
                    .accessibilityIdentifier("\(wearer.identifier)-face")
            }
            HStack {
                Button(face.hasFace ? String(localized: "Choose Another Picture…")
                                    : String(localized: "Choose Picture…"),
                       action: choosePicture)
                    .disabled(library == nil)
                    .accessibilityIdentifier("\(wearer.identifier)-choose-face")
                if face.newCut == nil, face.kept != nil, let recutPicture {
                    Button("Re-cut…") {
                        guard let source = recutPicture() else {
                            pictureFailed = true
                            return
                        }
                        pictureFailed = false
                        face.recut(source.picture, from: source.cut)
                    }
                    .accessibilityIdentifier("\(wearer.identifier)-recut-face")
                }
                if let useMonsterFace {
                    Button("Use the Monster's Face") { pictureFailed = !useMonsterFace() }
                    .accessibilityIdentifier("\(wearer.identifier)-monster-face")
                }
                if let useItemFace {
                    Button("Use the Item's Face") { pictureFailed = !useItemFace() }
                    .accessibilityIdentifier("\(wearer.identifier)-item-face")
                }
                if face.hasFace {
                    Button("Remove Face") { face.remove() }
                    .accessibilityIdentifier("\(wearer.identifier)-remove-face")
                }
            }
            if library == nil {
                Text("Open a Workspace to give a Pawn a Face: it is kept there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if pictureFailed {
                Text("That picture could not be read.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if face.hasFace {
                Text(wearer.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Asks for a picture from anywhere on the Mac. Only the square cut from it is kept, so it
    /// need not be inside the Workspace and may be deleted afterwards.
    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FacePicture.types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = wearer.pickerMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let picture = FacePicture.load(url) else {
            pictureFailed = true
            return
        }
        pictureFailed = false
        face.choosePicture(picture)
    }
}

/// The picture a Face is being cut from, with the square drawn over it: drag to move the
/// square, slide to resize it, and see beside it the token it will make.
///
/// Works on whole moves rather than step by step — each drag is measured from where the
/// square was when it began — because the square lands on whole pixels, and a picture shown
/// larger than its pixels would otherwise round every small step away to nothing.
struct FaceCutter: View {
    let pending: PendingFaceCut
    let kind: PawnKind
    let identifier: String
    let onCut: (CGRect) -> Void
    let onResize: (CGFloat) -> Void

    /// The square when the current drag began.
    @State private var dragStart: CGRect?

    /// The longest side the picture is shown at, in points.
    private static let maxShownSide: CGFloat = 220

    private var picture: CGImage { pending.picture }
    private var pictureSize: CGSize { pending.picture.pixelSize }
    private var cut: CGRect { pending.cut }

    var body: some View {
        let scale = min(Self.maxShownSide / pictureSize.width,
                        Self.maxShownSide / pictureSize.height)
        let shown = CGSize(width: pictureSize.width * scale, height: pictureSize.height * scale)
        let square = CGRect(x: cut.minX * scale, y: cut.minY * scale,
                            width: cut.width * scale, height: cut.height * scale)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: shown.width, height: shown.height)
                    // Everything outside the square is dimmed, so what is kept stands out.
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: shown))
                        path.addRect(square)
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: square.width, height: square.height)
                        .offset(x: square.minX, y: square.minY)
                }
                .frame(width: shown.width, height: shown.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? cut
                        dragStart = start
                        onCut(FaceCut.moved(start,
                                            by: CGSize(width: value.translation.width / scale,
                                                       height: value.translation.height / scale),
                                            in: pictureSize))
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityIdentifier(identifier)
                Slider(value: Binding(get: { cut.width }, set: { onResize($0) }),
                       in: FaceCut.minimumSide...max(FaceCut.minimumSide + 1,
                                                     min(pictureSize.width, pictureSize.height)))
                    .frame(width: shown.width)
                    .accessibilityLabel(Text("Face size"))
            }
            if let kept = picture.cropping(to: cut.integral) {
                FaceThumbnail(image: Image(decorative: kept, scale: 1), kind: kind)
            }
        }
    }
}

/// A Face at the size its editor shows it, in its Kind's outline: the token it makes.
private struct FaceThumbnail: View {
    let image: Image
    let kind: PawnKind

    private static let side: CGFloat = 56

    var body: some View {
        let outline = PawnToken.outline(for: kind, diameter: Self.side)
        image
            .resizable()
            .interpolation(.high)
            .frame(width: Self.side, height: Self.side)
            .background(PawnToken.faceGround(for: kind))
            .clipShape(outline)
            .overlay(outline.stroke(Color.black.opacity(0.6), lineWidth: 1.5))
    }
}

/// The search box beside the Kind: which Monster this Creature is.
///
/// Holds no draft: it reports a pick or a clear and the sheet decides what that means. Under
/// it, everything the Bestiary has to say about its notes.
private struct MonsterSearchField: View {
    let bestiary: Bestiary
    /// The unit in force, which the Monsters' notes are checked against.
    let unit: DistanceUnit
    let suggestedUnit: DistanceUnit?
    let onSwitchUnit: (DistanceUnit) -> Void
    /// The Monster already chosen, shown instead of the field.
    let monsterName: String?
    @Binding var isSearching: Bool
    let onPick: (Monster) -> Void
    let onClear: () -> Void

    var body: some View {
        DefinitionSearchField(
            prompt: "Search Monsters",
            identifier: "monster",
            chosenSymbol: "pawprint.fill",
            notFound: "— not in the Bestiary",
            clearHelp: "Forget the Monster. The Stat Block keeps its numbers.",
            isAvailable: bestiary.isAvailable,
            isRead: bestiary.unavailable == nil,
            chosenName: monsterName,
            exists: { bestiary.monster(named: $0) != nil },
            search: bestiary.search,
            detail: { monster in
                [monster.challengeRating.map { String(localized: "CR \($0)") }, monster.type]
                    .compactMap { $0 }.joined(separator: " · ")
            },
            isSearching: $isSearching,
            onPick: onPick,
            onClear: onClear
        ) {
            caption
        }
    }

    /// The Bestiary's one line, and the only place a skipped note is ever mentioned — then,
    /// under it, the Monsters whose notes are in the other unit. Silent when there is
    /// nothing to say.
    @ViewBuilder private var caption: some View {
        if let text = bestiary.caption {
            if bestiary.skipped.isEmpty {
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bestiary-caption")
            } else {
                SkippedNotesButton(caption: text, skipped: bestiary.skipped)
            }
        }
        OtherUnitNotesCaption(flagged: OtherUnitNotes(bestiary.monsters, current: unit),
                              suggestedUnit: suggestedUnit, onSwitchUnit: onSwitchUnit,
                              identifier: "bestiary-other-unit")
        PictureProblemsCaption(problems: bestiary.pictureProblems,
                               identifier: "bestiary-picture-problems")
    }
}

/// The search box beside the Kind for a Treasure: which Item it is. The Monster box's twin, so
/// a DM who knows one knows the other.
private struct ItemSearchField: View {
    let treasury: Treasury
    /// The Item already chosen, shown instead of the field.
    let itemName: String?
    @Binding var isSearching: Bool
    let onPick: (Item) -> Void
    let onClear: () -> Void

    var body: some View {
        DefinitionSearchField(
            prompt: "Search Items",
            identifier: "item",
            chosenSymbol: "bag.fill",
            notFound: "— not among the Items",
            clearHelp: "Forget the Item.",
            isAvailable: treasury.isAvailable,
            isRead: treasury.unavailable == nil,
            chosenName: itemName,
            exists: { treasury.item(named: $0) != nil },
            search: treasury.search,
            isSearching: $isSearching,
            onPick: onPick,
            onClear: onClear
        ) {
            caption
        }
    }

    /// The Treasury's one line, and the only place a skipped note is ever mentioned — then
    /// the Items whose picture gives no Face. Silent when there is nothing to say.
    @ViewBuilder private var caption: some View {
        if let text = treasury.caption {
            if treasury.skipped.isEmpty {
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("treasury-caption")
            } else {
                SkippedNotesButton(caption: text, skipped: treasury.skipped,
                                   title: String(localized: "Notes marked as Items that the app could not take"),
                                   identifier: "treasury-caption")
            }
        }
        PictureProblemsCaption(problems: treasury.pictureProblems,
                               identifier: "treasury-picture-problems")
    }
}

/// A definition read from the DM's notes that a search box offers, by its name.
protocol SearchableDefinition: Identifiable {
    var name: String { get }
}

extension Monster: SearchableDefinition {}
extension Item: SearchableDefinition {}

/// A search box for a definition read from the DM's notes — a Monster, an Item — with the one
/// chosen shown in its place.
///
/// The app's first search field. The results **float** beneath it, over the rows below, and
/// take no room of their own: a sheet that grew and shrank with every keystroke moved the OK
/// button under the DM's cursor as they typed. Drawn as an overlay rather than a popover,
/// which on macOS takes key focus from the field it belongs to — the DM would type one letter
/// and then be typing into nothing.
///
/// Holds no draft: it reports a pick or a clear and the sheet decides what that means.
private struct DefinitionSearchField<Definition: SearchableDefinition, Caption: View>: View {
    let prompt: LocalizedStringKey
    /// The accessibility identifiers' prefix: "monster" gives "monster-search".
    let identifier: String
    let chosenSymbol: String
    /// Said beside a chosen name the notes no longer define.
    let notFound: LocalizedStringKey
    let clearHelp: LocalizedStringKey
    /// Whether there is anything to search. The field is disabled without it.
    let isAvailable: Bool
    /// Whether the notes have been read, so a chosen name can be said to be missing.
    let isRead: Bool
    /// The definition already chosen, shown instead of the field.
    let chosenName: String?
    let exists: (String) -> Bool
    let search: (String) -> [Definition]
    /// The secondary text beside a result — a Monster's CR and type — or nil for none.
    var detail: ((Definition) -> String)? = nil
    @Binding var isSearching: Bool
    let onPick: (Definition) -> Void
    let onClear: () -> Void
    @ViewBuilder let caption: () -> Caption

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    /// As many as fit between the field and the sheet's bottom edge, which is where a
    /// floating list is clipped. Typing one more letter is quicker than scrolling a list in
    /// a modal.
    private var resultLimit: Int { 5 }
    private var width: CGFloat { 250 }

    private var results: [Definition] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(search(query).prefix(resultLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let chosenName {
                chosen(chosenName)
            } else {
                field
                    .overlay(alignment: .topLeading) {
                        if !results.isEmpty {
                            list
                                .frame(width: width)
                                .fixedSize(horizontal: false, vertical: true)
                                // Just under the field: its height and a small gap.
                                .offset(y: 26)
                        }
                    }
                    // Over the caption below it, which the results float across: a click
                    // meant for a result must never land on "Use feet" underneath.
                    .zIndex(1)
            }
            caption()
        }
        .frame(width: width, alignment: .leading)
        .onChange(of: query) { _, query in
            highlighted = 0
            isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .onDisappear { isSearching = false }
    }

    private func chosen(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: chosenSymbol).foregroundStyle(.secondary)
            Text(name).lineLimit(1)
            if isRead, !exists(name) {
                Text(notFound).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: { onClear(); query = "" }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(clearHelp)
            .accessibilityIdentifier("\(identifier)-clear")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("\(identifier)-chosen")
    }

    private var field: some View {
        TextField(prompt, text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(!isAvailable)
            .accessibilityIdentifier("\(identifier)-search")
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.return) { pickHighlighted() }
            .onSubmit { _ = pickHighlighted() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, definition in
                Button { pick(definition) } label: {
                    HStack(spacing: 6) {
                        Text(definition.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if let detail {
                            Text(detail(definition))
                                .font(.caption)
                                .foregroundStyle(index == highlighted ? .white.opacity(0.85) : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(index == highlighted ? .white : .primary)
                    .background(index == highlighted ? Color.accentColor : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier)-result-\(index)")
            }
        }
        .padding(3)
        // Opaque, and lifted: it sits on top of other controls now, not between them.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        highlighted = min(max(highlighted + step, 0), results.count - 1)
        return .handled
    }

    private func pickHighlighted() -> KeyPress.Result {
        guard results.indices.contains(highlighted) else { return .ignored }
        pick(results[highlighted])
        return .handled
    }

    private func pick(_ definition: Definition) {
        onPick(definition)
        query = ""
    }
}

/// "37 Monsters · 1 file skipped", opening onto which files and why. Also under the
/// Character note box, with its own `title`.
struct SkippedNotesButton: View {
    let caption: String
    let skipped: [SkippedNote]
    var title = String(localized: "Notes with a statblock the Bestiary could not take")
    var identifier = "bestiary-caption"
    @State private var isShowing = false

    var body: some View {
        Button(caption) { isShowing = true }
            .buttonStyle(.link)
            .font(.caption)
            .accessibilityIdentifier(identifier)
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    ForEach(skipped) { note in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.file).font(.caption.monospaced())
                            Text(note.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("The notes are read when the Workspace opens.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
            }
    }
}

/// "Some pictures give no Face", opening onto which notes and why — a picture missing from
/// the Workspace, or a bare name two pictures share (ADR-0028). Under the Monster search, the
/// Item search and the Character note box alike, beside the other things they say about their
/// notes; silent when there is nothing to say. Those notes are still offered: only their Face
/// is lost.
struct PictureProblemsCaption: View {
    let problems: [PictureProblem]
    let identifier: String
    @State private var isShowing = false

    var body: some View {
        if !problems.isEmpty {
            Button(String(localized: "Some pictures give no Face")) { isShowing = true }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier(identifier)
                .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes whose picture gives no Face")
                            .font(.caption.weight(.semibold))
                        ForEach(problems) { problem in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(problem.name).font(.caption)
                                Text(problem.file).font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(problem.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("The notes are read when the Workspace opens.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(width: 320, alignment: .leading)
                }
        }
    }
}

/// "3 notes in feet", opening onto which notes and where they are — and "Use feet" beside it
/// when every note in the Workspace agrees (ADR-0027). Under the Monster search and the
/// Character note box alike, as `SkippedNotesButton` is; silent when there is nothing to say.
///
/// It only informs: nothing here rewrites a note or keeps a Monster from being Stamped.
struct OtherUnitNotesCaption: View {
    let flagged: OtherUnitNotes?
    /// The unit every note agrees on, when it is not the one in force.
    let suggestedUnit: DistanceUnit?
    let onSwitchUnit: (DistanceUnit) -> Void
    let identifier: String
    @State private var isShowing = false

    var body: some View {
        if let flagged {
            HStack(spacing: 8) {
                Button(flagged.caption) { isShowing = true }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityIdentifier(identifier)
                    .popover(isPresented: $isShowing, arrowEdge: .bottom) { list(flagged) }
                if let suggestedUnit {
                    Button(switchTitle(suggestedUnit)) { onSwitchUnit(suggestedUnit) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityIdentifier("\(identifier)-switch")
                }
            }
        }
    }

    private func list(_ flagged: OtherUnitNotes) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(flagged.unit))
                .font(.caption.weight(.semibold))
            ForEach(flagged.notes) { note in
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.name).font(.caption)
                    Text(note.file).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            Text("The notes are read when the Workspace opens.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private func title(_ unit: DistanceUnit) -> String {
        switch unit {
        case .metres: String(localized: "Notes whose Speed or Senses are in metres")
        case .feet: String(localized: "Notes whose Speed or Senses are in feet")
        }
    }

    private func switchTitle(_ unit: DistanceUnit) -> String {
        switch unit {
        case .metres: String(localized: "Use metres")
        case .feet: String(localized: "Use feet")
        }
    }
}

/// Editing a Light's fields. Same contract as `EditPawnSheet` — buffered, OK commits,
/// Cancel and Escape discard.
///
/// Two radii where a Pawn has one, because a torch really does have a bright band and a dim
/// one, and both are the DM's to set. `EditLightDraft` carries the stored dim rather than
/// re-deriving it, so a dim deliberately set equal to bright is not silently doubled back.
struct EditLightSheet: View {
    @State var draft: EditLightDraft
    let hasDeclaredGrid: Bool
    /// What the radii are typed and shown in.
    let unit: DistanceUnit
    let onCommit: (EditLightDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Light").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .help("The DM's own. Never drawn on the Player Display.")
                }
                GridRow {
                    Text("Bright")
                    DistanceField($draft.brightSquares, unit: unit)
                }
                GridRow {
                    Text("Dim")
                    DistanceField($draft.dimSquares, unit: unit)
                }
                GridRow {
                    Text("Burning")
                    Toggle("", isOn: $draft.isOn).labelsHidden()
                }
            }

            if !hasDeclaredGrid {
                Text("No Grid declared, so these radii have no physical size yet.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") { onCommit(draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// A distance stored in Grid squares, typed and shown in the Distance Unit.
///
/// Shared by both sheets and the Party roster rather than written three times: the
/// squares↔unit bridge below is the kind of incidental detail that drifts when it is
/// duplicated, and a Pawn's sight, a Character's and a Light's radii are the same quantity.
/// `DistanceUnit.squares(entered:replacing:)` is what keeps a field the DM only tabbed through
/// from rewriting a stored value it can show only rounded.
struct DistanceField: View {
    @Binding private var squares: CGFloat
    private let unit: DistanceUnit
    private let caption: String
    private let width: CGFloat

    /// `caption` is what follows the field; the unit's symbol unless there is more to say.
    init(_ squares: Binding<CGFloat>, unit: DistanceUnit, caption: String? = nil,
         width: CGFloat = 60) {
        _squares = squares
        self.unit = unit
        self.caption = caption ?? unit.symbol
        self.width = width
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(unit.symbol, value: Binding(
                get: { unit.roundedDisplay(squares: squares) },
                set: { squares = unit.squares(entered: $0, replacing: squares) }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
            Text(caption).foregroundStyle(.secondary)
        }
    }
}
