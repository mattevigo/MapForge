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
struct EditPawnSheet: View {
    @State var draft: EditPawnDraft
    /// Whether a Grid has been declared. Sight is measured in Grid squares, so without one
    /// the number is inert — said plainly rather than by refusing the edit.
    let hasDeclaredGrid: Bool
    let onCommit: (EditPawnDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Pawn").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Label")
                    TextField("label", text: $draft.label)
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
                GridRow {
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
                }
                GridRow {
                    Text("Size")
                    Toggle("Big", isOn: $draft.isBig)
                        .help("Occupies 2×2 squares instead of 1×1. Visual only — its light and sight are unchanged.")
                }
                GridRow {
                    Text("Sight")
                    HStack(spacing: 6) {
                        // Bridged through Double: CGFloat is not a `BinaryFloatingPoint`
                        // SwiftUI's `.number` format accepts directly.
                        TextField("range", value: Binding(
                            get: { Double(draft.sightSquares) },
                            set: { draft.sightSquares = CGFloat($0) }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        // A Pawn has one radius. The extra square the region fades over is
                        // not a second number the DM sets — it is there so the edge is not a
                        // hard cut — so it is not offered as one.
                        Text(draft.kind.isDiscovered
                             ? "squares — unused, a \(draft.kind.title) emits no Light"
                             : "squares")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !hasDeclaredGrid {
                Text("No Grid declared, so this sight has no physical size yet.")
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
                    radiusField($draft.brightSquares)
                }
                GridRow {
                    Text("Dim")
                    radiusField($draft.dimSquares)
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

    /// Bridged through Double: CGFloat is not a `BinaryFloatingPoint` SwiftUI's `.number`
    /// format accepts directly.
    private func radiusField(_ value: Binding<CGFloat>) -> some View {
        HStack(spacing: 6) {
            TextField("radius", value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = CGFloat($0) }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            Text("squares").foregroundStyle(.secondary)
        }
    }
}
