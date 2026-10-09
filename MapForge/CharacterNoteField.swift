import SwiftUI

/// Which note is a Character's own, chosen in the roster's Character editor (ADR-0024).
///
/// Built as the Monster box in the Edit Pawn sheet is, so a DM who knows one knows the other:
/// type part of the name, pick from the list, and the chosen note replaces the field. The
/// results **float** over what lies below rather than pushing it down, so Save does not move
/// under the DM's cursor as they type — which is why the editor holding this sits above its
/// neighbours (`zIndex`).
///
/// Holds no Character: it reports a pick or a clear and the editor decides what that means.
/// Once chosen, the note's numbers are shown and cannot be typed — the note is the only
/// place they are written.
struct CharacterNoteField: View {
    let notes: CharacterNotes
    /// The note already chosen, by name, shown instead of the field.
    let noteName: String?
    /// False while the Workspace's notes are still being read, when nothing can be found and
    /// nothing should be said to be missing.
    let isRead: Bool
    /// The unit in force, which the notes are checked against.
    let unit: DistanceUnit
    /// The unit every note in the Workspace agrees on, when it is not `unit`.
    let suggestedUnit: DistanceUnit?
    let onSwitchUnit: (DistanceUnit) -> Void
    let onPick: (CharacterNote) -> Void
    let onClear: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    /// A party is a handful of heroes; five is more than a DM scrolls past.
    private static let resultLimit = 5

    private var results: [CharacterNote] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(notes.search(query).prefix(Self.resultLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let noteName {
                chosen(noteName)
                numbers(notes.note(named: noteName))
            } else {
                field
                    .overlay(alignment: .topLeading) {
                        if !results.isEmpty {
                            list
                                .fixedSize(horizontal: false, vertical: true)
                                // Just under the field: its height and a small gap.
                                .offset(y: 26)
                        }
                    }
                    // Above the caption that follows it, or the caption is drawn across the
                    // floating results: a later sibling paints over an earlier one's overlay.
                    .zIndex(1)
                Text("No note: its Pawns are stamped without numbers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            caption
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private func chosen(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(name).lineLimit(1)
            if isRead, notes.note(named: name) == nil {
                Text("— not found").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: { onClear(); query = "" }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Forget this note. The Character stamps no numbers until it has one.")
            .accessibilityIdentifier("character-note-clear")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("character-note-chosen")
    }

    /// The note's numbers, read-only. A dash for one the note lacks, never a default that
    /// would pass for the hero's own.
    @ViewBuilder private func numbers(_ note: CharacterNote?) -> some View {
        if let note {
            let armorClass = note.armorClass.map { "\($0)" } ?? "—"
            let hitPoints = note.maxHP.map { "\($0)" } ?? "—"
            let initiative = note.initiativeBonus
                .map { $0.formatted(.number.sign(strategy: .always())) } ?? "—"
            HStack(spacing: 6) {
                Text("AC \(armorClass) · HP \(hitPoints) · Initiative \(initiative)",
                     comment: "A Character's numbers as its note gives them, read-only")
                if note.isBig {
                    Text(verbatim: "·")
                    Text("Big")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("character-note-numbers")
        }
    }

    private var field: some View {
        TextField("Search Characters' notes", text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(notes.notes.isEmpty)
            .accessibilityIdentifier("character-note-search")
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.return) { pickHighlighted() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                Button { pick(note) } label: {
                    Text(note.name).lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(index == highlighted ? .white : .primary)
                        .background(index == highlighted ? Color.accentColor : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("character-note-result-\(index)")
            }
        }
        .padding(3)
        // Opaque, and lifted: it sits on top of other controls, not between them.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    /// The one place a Character note the app could not take is mentioned — then the notes
    /// in the other unit. Silent when every note was read and speaks the unit in force.
    @ViewBuilder private var caption: some View {
        if !notes.skipped.isEmpty {
            SkippedNotesButton(caption: String(localized: "\(notes.skipped.count) files skipped"),
                               skipped: notes.skipped,
                               title: String(localized: "Character notes the app could not take"),
                               identifier: "character-note-caption")
        }
        OtherUnitNotesCaption(flagged: OtherUnitNotes(notes.notes, current: unit),
                              suggestedUnit: suggestedUnit, onSwitchUnit: onSwitchUnit,
                              identifier: "character-note-other-unit")
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

    private func pick(_ note: CharacterNote) {
        onPick(note)
        query = ""
    }
}
