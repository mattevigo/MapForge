import SwiftUI

/// The sheet a DM records a d20 in.
///
/// A modal for `EditPawnSheet`'s reason — a form is what justifies one — and a sheet rather
/// than a popover because a popover dismisses on an outside click, which is hostile in the
/// middle of typing a Modifier.
///
/// It writes to a Log and never to a Stat Block. It does not apply what the result implies:
/// a failed Dexterity save means half damage and the app does not know how much, so the DM
/// applies it with the Hit field that already exists. One control, one action. See
/// `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
struct RollSheet: View {
    @State var draft: RollDraft
    let onCommit: (RollDraft) -> Void
    let onCancel: () -> Void

    /// The four a DM reaches for. The free field beside them takes anything else, and
    /// clearing it is how a Roll is recorded with no Difficulty Class at all.
    private static let commonDifficultyClasses = [5, 10, 15, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            difficultyClassRow
            subjectRow
            d20Row
            modifierRow
            Divider()
            summary
            footer
        }
        .padding(20)
        .frame(width: draft.kind == .abilityCheck ? 560 : 500)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(draft.kind.title).font(.headline)
            Text(draft.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The Difficulty Class

    private var difficultyClassRow: some View {
        HStack(spacing: 10) {
            Text("Difficulty Class:")
            Picker("", selection: Binding(
                get: { draft.difficultyClass },
                set: { draft.difficultyClass = $0 }
            )) {
                ForEach(Self.commonDifficultyClasses, id: \.self) {
                    Text("\($0)").tag(Int?.some($0))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            NumberField("DC", value: $draft.difficultyClass, width: 60)
                .help("Clear this to record the Roll without a Difficulty Class — the Log "
                      + "then reports the total and no verdict.")
        }
    }

    // MARK: The subject

    @ViewBuilder
    private var subjectRow: some View {
        switch draft.kind {
        case .savingThrow:
            HStack(spacing: 10) {
                Text("Ability:")
                Picker("", selection: $draft.ability) {
                    ForEach(Ability.allCases, id: \.self) {
                        Text($0.abbreviation).tag(Ability?.some($0))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .help("Which Ability the save uses.")
            }
        case .abilityCheck:
            VStack(alignment: .leading, spacing: 6) {
                Text("Skill:")
                // A visible grid rather than a menu: eighteen items in a menu is two clicks
                // and a scroll, and the grid doubles as the reminder of which Skill uses
                // which Ability — the thing a DM actually forgets.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                         count: 3),
                          spacing: 6) {
                    ForEach(Skill.allCases, id: \.self) { skill in
                        Button {
                            draft.skill = skill
                        } label: {
                            HStack(spacing: 6) {
                                Text(skill.title)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(skill.ability.abbreviation)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(draft.skill == skill ? .accentColor : .secondary)
                    }
                }
            }
        }
    }

    // MARK: The die

    private var d20Row: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("d20 roll:")
                .padding(.top, 6)
            // Twenty faces, not a stepper: the DM clicks the number the die showed, which is
            // one gesture and is itself the record. The app never generates it.
            VStack(spacing: 4) {
                face(1...10)
                face(11...20)
            }
        }
    }

    private func face(_ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(range), id: \.self) { value in
                Button("\(value)") { draft.d20 = value }
                    .buttonStyle(.bordered)
                    .tint(draft.d20 == value ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .monospacedDigit()
            }
        }
    }

    // MARK: The Modifier

    private var modifierRow: some View {
        HStack(spacing: 10) {
            Text("Modifier:")
            NumberField("modifier", value: Binding(
                get: { Optional(draft.modifier) },
                set: { draft.modifier = $0 ?? 0 }
            ), width: 60)
            Text("ability bonus, proficiency, active effects")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: The summary

    private var summary: some View {
        HStack(spacing: 10) {
            Text("Total")
                .foregroundStyle(.secondary)
            if let roll = draft.roll {
                Text("\(roll.total)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text(roll.difficultyClass.map {
                    "(\(LogRowText.arithmetic(of: roll))) vs DC \($0)"
                } ?? "(\(LogRowText.arithmetic(of: roll)))")
                    .foregroundStyle(.secondary)
            } else {
                Text("—").font(.title.weight(.semibold))
                Text(draft.d20 == nil ? "choose the d20 result" : draft.kind.prompt.lowercased())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            verdict
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var verdict: some View {
        switch draft.roll?.succeeded {
        case .some(true):
            pill("Succeeded", .green)
        case .some(false):
            pill("Failed", .red)
        case nil:
            // No verdict: either nothing is rolled yet, or there is no Difficulty Class to
            // have one against.
            pill(draft.roll == nil ? "Pending" : "Recorded", .secondary)
        }
    }

    private func pill(_ text: String, _ tint: some ShapeStyle) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private var footer: some View {
        HStack {
            Text("Return to record · Esc to cancel")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Record roll") { onCommit(draft) }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.roll == nil)
        }
    }
}

/// A number that may be absent, committed on Return and on focus loss.
///
/// `StatEditor` has one of these for its stat fields; this is the same contract for a value
/// whose absence is meaningful — an empty Difficulty Class is a Roll with no DC, not a zero.
private struct NumberField: View {
    let placeholder: String
    @Binding var value: Int?
    let width: CGFloat
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, value: Binding<Int?>, width: CGFloat) {
        self.placeholder = placeholder
        self._value = value
        self.width = width
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: value) { _, new in
                // Follow the model when it changes from elsewhere — the DC segmented control
                // writes the same value this field shows.
                let rendered = new.map(String.init) ?? ""
                if Int(text) != new { text = rendered }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Empty means absent, which is a value here rather than a refusal.
        value = trimmed.isEmpty ? nil : Int(trimmed)
        text = value.map(String.init) ?? ""
    }
}
