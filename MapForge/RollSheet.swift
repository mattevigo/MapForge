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
                // A DC of 13, or none at all, is not one of the four — and a segmented
                // control whose binding holds an untagged value draws with nothing
                // selected, which reads as "no DC" when a DC is set. This tag is never
                // shown; it is what the selection lands on so the four are honestly unlit.
                Text("").tag(Int?.none).hidden()
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            NumberField(value: draft.difficultyClass,
                        identifier: "roll-difficulty-class",
                        width: 60) { draft.difficultyClass = $0 }
                .help("Clear this to record the Roll without a Difficulty Class — the Log then reports the total and no verdict.")
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
                    ForEach(Skill.alphabetical(), id: \.self) { skill in
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
            NumberField(value: draft.modifier,
                        identifier: "roll-modifier",
                        width: 60) { draft.modifier = $0 ?? 0 }
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
                    String(localized: "(\(LogRowText.arithmetic(of: roll))) vs DC \($0)")
                } ?? "(\(LogRowText.arithmetic(of: roll)))")
                    .foregroundStyle(.secondary)
            } else {
                Text("—").font(.title.weight(.semibold))
                Text(draft.d20 == nil ? String(localized: "choose the d20 result")
                                     : draft.kind.caption)
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
            pill(String(localized: "Succeeded"), .green)
        case .some(false):
            pill(String(localized: "Failed"), .red)
        case nil:
            // No verdict: either nothing is rolled yet, or there is no Difficulty Class to
            // have one against.
            pill(draft.roll == nil ? String(localized: "Pending") : String(localized: "Recorded"),
                 .secondary)
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
