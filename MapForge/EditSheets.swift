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
struct EditPawnSheet: View {
    @State var draft: EditPawnDraft
    /// Whether a Grid has been declared. Sight is measured in Grid squares, so without one
    /// the number is inert — said plainly rather than by refusing the edit.
    let hasDeclaredGrid: Bool
    /// What the search box searches.
    var bestiary = Bestiary.closed
    /// The Map as it stands, for numbering a picked Monster's label.
    var pawns: [Pawn] = []
    /// The Pawn's Stat Block as it stands, for knowing whether a stamp would heal it.
    var statBlock = StatBlock()
    let onCommit: (EditPawnDraft) -> Void
    let onCancel: () -> Void

    /// Whether the DM is in the middle of a search. While they are, Return belongs to the
    /// search box — it picks a Monster, or does nothing when the query matches none — and
    /// must not also press OK on a half-typed name.
    @State private var isSearching = false
    /// The heal OK is waiting on the DM to confirm.
    @State private var confirming: MonsterStamp.Healing?

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
                                           monsterName: draft.monsterName,
                                           isSearching: $isSearching,
                                           onPick: { draft.pick($0, among: pawns) },
                                           onClear: { draft.clearMonster() })
                            .gridCellAnchor(.topLeading)
                            // Above the rows below it, which the open results float over.
                            .zIndex(1)
                    }
                }
                GridRow {
                    Text("Size")
                    Toggle("Big", isOn: $draft.isBig)
                        .help("Occupies 2×2 squares instead of 1×1. Visual only — its light and sight are unchanged.")
                }
                GridRow {
                    Text("Sight")
                    // A Pawn has one radius. The extra square the region fades over is not
                    // a second number the DM sets — it is there so the edge is not a hard
                    // cut — so it is not offered as one.
                    SquaresField($draft.sightSquares,
                                 unit: draft.kind.isDiscovered
                                     ? String(localized: "squares — unused, a \(draft.kind.title) emits no Light")
                                     : String(localized: "squares"))
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
        .alert("Heal \(draft.label)?",
               isPresented: Binding(get: { confirming != nil },
                                    set: { if !$0 { confirming = nil } }),
               presenting: confirming) { _ in
            Button("Become \(draft.monsterName ?? String(localized: "it"))") { onCommit(draft) }
            // Back to the open sheet, where the pick can be undone — not out of it.
            Button("Cancel", role: .cancel) {}
        } message: { healing in
            Text("Becoming a \(draft.monsterName ?? String(localized: "Monster")) means arriving whole: \(healing.before) becomes \(healing.after). Conditions and temporary hit points are kept.")
        }
    }

    /// OK. Asks first only when the stamp would overwrite hit points that exist — a dialog
    /// that appears when nothing can be lost is one the DM learns to click through.
    private func commit() {
        if let healing = draft.healing(over: statBlock, in: bestiary) {
            confirming = healing
        } else {
            onCommit(draft)
        }
    }
}

/// The search box beside the Kind: which Monster this Creature is.
///
/// The app's first search field. The results **float** beneath it, over the rows below, and
/// take no room of their own: a sheet that grew and shrank with every keystroke moved the OK
/// button under the DM's cursor as they typed. Drawn as an overlay rather than a popover,
/// which on macOS takes key focus from the field it belongs to — the DM would type one letter
/// and then be typing into nothing.
///
/// Holds no draft: it reports a pick or a clear and the sheet decides what that means.
private struct MonsterSearchField: View {
    let bestiary: Bestiary
    /// The Monster already chosen, shown instead of the field.
    let monsterName: String?
    @Binding var isSearching: Bool
    let onPick: (Monster) -> Void
    let onClear: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    /// As many as fit between the field and the sheet's bottom edge, which is where a
    /// floating list is clipped. Typing one more letter is quicker than scrolling a list in
    /// a modal.
    private static let resultLimit = 5
    private static let width: CGFloat = 250

    private var results: [Monster] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(bestiary.search(query).prefix(Self.resultLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let monsterName {
                chosen(monsterName)
            } else {
                field
                    .overlay(alignment: .topLeading) {
                        if !results.isEmpty {
                            list
                                .frame(width: Self.width)
                                .fixedSize(horizontal: false, vertical: true)
                                // Just under the field: its height and a small gap.
                                .offset(y: 26)
                        }
                    }
            }
            caption
        }
        .frame(width: Self.width, alignment: .leading)
        .onChange(of: query) { _, query in
            highlighted = 0
            isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .onDisappear { isSearching = false }
    }

    private func chosen(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pawprint.fill").foregroundStyle(.secondary)
            Text(name).lineLimit(1)
            if bestiary.unavailable == nil, bestiary.monster(named: name) == nil {
                Text("— not in the Bestiary").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: { onClear(); query = "" }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Forget the Monster. The Stat Block keeps its numbers.")
            .accessibilityIdentifier("monster-clear")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("monster-chosen")
    }

    private var field: some View {
        TextField("Search Monsters", text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(!bestiary.isAvailable)
            .accessibilityIdentifier("monster-search")
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.return) { pickHighlighted() }
            .onSubmit { _ = pickHighlighted() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, monster in
                Button { pick(monster) } label: {
                    HStack(spacing: 6) {
                        Text(monster.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text([monster.challengeRating.map { String(localized: "CR \($0)") }, monster.type]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(index == highlighted ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
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
                .accessibilityIdentifier("monster-result-\(index)")
            }
        }
        .padding(3)
        // Opaque, and lifted: it sits on top of other controls now, not between them.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    /// The Bestiary's one line, and the only place a skipped note is ever mentioned. Silent
    /// when everything was read.
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

    private func pick(_ monster: Monster) {
        onPick(monster)
        query = ""
    }
}

/// "37 Monsters · 1 file skipped", opening onto which files and why.
private struct SkippedNotesButton: View {
    let caption: String
    let skipped: [Bestiary.Skipped]
    @State private var isShowing = false

    var body: some View {
        Button(caption) { isShowing = true }
            .buttonStyle(.link)
            .font(.caption)
            .accessibilityIdentifier("bestiary-caption")
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes with a statblock the Bestiary could not take")
                        .font(.caption.weight(.semibold))
                    ForEach(skipped) { note in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.file).font(.caption.monospaced())
                            Text(note.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("The Bestiary is read when the Workspace opens.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
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
                    SquaresField($draft.brightSquares)
                }
                GridRow {
                    Text("Dim")
                    SquaresField($draft.dimSquares)
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

/// A distance in Grid squares, typed.
///
/// Shared by both sheets rather than written twice: the CGFloat↔Double bridge below is the
/// kind of incidental detail that drifts when it is duplicated, and a Pawn's sight and a
/// Light's radii are the same quantity in the same unit.
private struct SquaresField: View {
    @Binding private var squares: CGFloat
    private let unit: String

    init(_ squares: Binding<CGFloat>, unit: String = "squares") {
        _squares = squares
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 6) {
            // Bridged through Double: CGFloat is not a `BinaryFloatingPoint` that SwiftUI's
            // `.number` format accepts directly.
            TextField("squares", value: Binding(
                get: { Double(squares) },
                set: { squares = CGFloat($0) }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
