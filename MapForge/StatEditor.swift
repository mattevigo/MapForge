import SwiftUI

/// The Stat Block editor and the notes box, below the Order.
///
/// Every edit goes through `AppState.editStatBlock`, which decides whether it becomes a
/// `Change` in the Turn, a Correction against a past one, or a straight write to
/// `stats.json` during prep. No view here writes a `StatBlock` — see ADR-0008.
struct StatEditor: View {
    @EnvironmentObject private var appState: AppState

    /// The row the editor is pointed at. Independent of whose Turn it is: a DM edits the
    /// monster the party just hit, not the one acting.
    let combatant: Pawn.ID?

    /// Typed into but not yet committed. Hit points want arithmetic at the table — "-7"
    /// beats working out 23 minus 7 while six people wait.
    @State private var damage = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let combatant, let pawn = pawn(combatant) {
                Divider()
                editor(for: combatant, named: pawn.label)
                // The Monster's page, for a Creature that is one — so the DM reads its
                // actions here rather than alt-tabbing to their notes mid-fight.
                if let monsterName = pawn.monsterName {
                    Divider()
                    MonsterReferenceView(monsterName: monsterName, bestiary: appState.bestiary,
                                         unit: appState.distanceUnit)
                } else if let page = appState.characterPage(for: pawn) {
                    // And the Character's, for a Pawn Stamped from one: "what's my spell
                    // save DC again?" without asking the player (ADR-0007, amended).
                    Divider()
                    CharacterReferenceView(page: page, unit: appState.distanceUnit)
                }
            }
            if appState.encounter != nil {
                Divider()
                notesBox
            }
        }
    }

    private func pawn(_ id: Pawn.ID) -> Pawn? {
        appState.fog.pawns.first { $0.id == id }
    }

    private func block(_ id: Pawn.ID) -> StatBlock {
        appState.encounter?.blocks[id] ?? appState.statBlock(for: id)
    }

    // MARK: The editor

    private func editor(for id: Pawn.ID, named name: String) -> some View {
        let current = block(id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 6) {
                field(String(localized: "HP", comment: "Hit points, as narrow as the field"), value: current.currentHP, id: "hp") { new in
                    appState.editStatBlock(for: id) { $0.currentHP = new }
                }
                Text("/").foregroundStyle(.secondary).padding(.top, 10)
                field(String(localized: "Max", comment: "Maximum hit points, as narrow as the field"), value: current.maxHP, id: "max-hp") { new in
                    appState.editStatBlock(for: id) { $0.maxHP = new }
                }
                field(String(localized: "Temp", comment: "Temporary hit points, as narrow as the field"), value: current.temporaryHP, id: "temp-hp") { new in
                    appState.editStatBlock(for: id) { $0.temporaryHP = new ?? 0 }
                }
            }

            HStack(spacing: 6) {
                // A damage box rather than mental arithmetic: type 7 to take 7 off, or -7
                // to give it back. The recorded Change is still before-and-after, whatever
                // the DM typed to get there.
                TextField("damage", text: $damage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .accessibilityIdentifier("damage-field")
                    .onSubmit { applyDamage(to: id) }
                Button("Hit") { applyDamage(to: id) }
                    .accessibilityIdentifier("apply-damage")
                Button("Heal") { applyDamage(to: id, healing: true) }
                    .accessibilityIdentifier("apply-healing")
            }
            .font(.caption)

            HStack(spacing: 6) {
                field(String(localized: "AC", comment: "Armour Class, abbreviated"), value: current.armorClass, id: "ac") { new in
                    appState.editStatBlock(for: id) {
                        $0.armorClass = new ?? StatBlock.defaultArmorClass
                    }
                }
                // The *bonus* — what the d20 is added to — because that is the number that
                // belongs to the Stat Block. The rolled Initiative is the Encounter's, and
                // is overtyped where it is read: in the Order's own column. This field was
                // the rolled number once, which left a Pawn's bonus with no editor at all.
                field(String(localized: "Init", comment: "Initiative bonus, as narrow as the field"), value: current.initiativeBonus, id: "initiative-bonus") { new in
                    appState.editStatBlock(for: id) { $0.initiativeBonus = new ?? 0 }
                }
                .help("Initiative bonus: added to the d20 when Initiative is rolled. The rolled number is edited in the Order.")
                field(String(localized: "Exh", comment: "Exhaustion level, as narrow as the field"), value: current.exhaustion, id: "exhaustion") { new in
                    appState.editStatBlock(for: id) { $0.exhaustion = new ?? 0 }
                }
                Toggle(isOn: Binding(
                    get: { current.isConcentrating },
                    set: { on in appState.editStatBlock(for: id) { $0.isConcentrating = on } }
                )) {
                    Image(systemName: "circle.hexagonpath.fill")
                }
                .toggleStyle(.button)
                .accessibilityIdentifier("concentration-toggle")
                .help("Concentrating")
            }

            conditionGrid(for: id, current: current)
        }
    }

    /// One labelled number field, committing on Return and on focus loss.
    ///
    /// Commit-on-keystroke would record 2, then 24, for a DM typing "24" — two Changes for
    /// one decision, and a Log nobody can read. `NumberField` holds the half-typed text.
    private func field(_ label: String,
                       value: Int?,
                       id: String,
                       commit: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            NumberField(value: value, identifier: id, commit: commit)
        }
    }

    private func applyDamage(to id: Pawn.ID, healing: Bool = false) {
        guard let amount = Int(damage.trimmingCharacters(in: .whitespaces)) else { return }
        let current = block(id).currentHP ?? block(id).maxHP ?? 0
        appState.editStatBlock(for: id) {
            $0.currentHP = healing ? current + amount : current - amount
        }
        damage = ""
    }

    /// Fourteen Conditions as a grid of icons: applying Prone must be one click, and a
    /// menu would make it three.
    private func conditionGrid(for id: Pawn.ID, current: StatBlock) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                  spacing: 2) {
            ForEach(Condition.alphabetical(), id: \.self) { condition in
                let isOn = current.conditions.contains(condition)
                Button {
                    appState.editStatBlock(for: id) {
                        if isOn { $0.conditions.remove(condition) } else { $0.conditions.insert(condition) }
                    }
                } label: {
                    Image(systemName: condition.symbolName)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, minHeight: 18)
                }
                .buttonStyle(.bordered)
                .tint(isOn ? .accentColor : .secondary)
                .accessibilityIdentifier("condition-\(condition.rawValue)")
                .help(condition.title)
            }
        }
    }

    // MARK: Notes

    @ViewBuilder
    private var notesBox: some View {
        if let encounter = appState.encounter {
            let subject = encounter.correctionTarget?.combatantID ?? encounter.activeCombatantID
            VStack(alignment: .leading, spacing: 4) {
                Text(noteLabel(encounter, subject: subject))
                    .font(.system(size: 9))
                    .foregroundStyle(encounter.isCorrecting ? Color.orange : .secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    TextField("what happened", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("note-field")
                        .onSubmit { commitNote() }
                        .keepsKeyboardOnReturn()
                    Button {
                        commitNote()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("add-note")
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func noteLabel(_ encounter: Encounter, subject: Pawn.ID?) -> String {
        let name = subject.flatMap { encounter.name(of: $0) } ?? "?"
        guard let target = encounter.correctionTarget else {
            return String(localized: "Note on \(name)'s Turn")
        }
        return String(localized: "Note on Round \(target.round) — \(name)")
    }

    private func commitNote() {
        appState.addNote(note)
        note = ""
    }
}

/// A number field that commits once, on Return or on losing focus.
///
/// Its own view because the half-typed text has to live somewhere: a DM typing "24" passes
/// through "2", and binding straight to the model would record a Combatant at 2 hit points
/// on the way to 24 — a Change that never happened, in a Log that cannot be edited.
///
/// The field also has to follow the model when something *else* moves the number — damage
/// applied from the box beside it, or a Correction — which is why the external value is
/// mirrored back in whenever it changes and the field is not being typed in.
/// A whole number that may be absent, committed on Return and on focus loss.
///
/// Not private: the Roll sheet's Difficulty Class and Modifier want exactly this contract,
/// and a second near-copy of it would be a second place for the two guards below to be
/// forgotten — both of which are here because a real bug reached the table.
struct NumberField: View {
    let value: Int?
    let identifier: String
    /// The field's width. 42 suits a Stat Block's two-digit numbers; a Difficulty Class
    /// typed beside a segmented control wants a little more.
    var width: CGFloat = 42
    /// Drawn without a border and centred, for a number edited in place — the Order's
    /// Initiative column — where the ground behind it is the caller's.
    var isPlain = false
    /// Called after a commit made with **Return**, and not after one made by leaving the
    /// field. The Initiative column settles the Order on Return and must not on Tab, or
    /// typing down the column would move the row out from under the next Tab. Declared
    /// before `commit` so a bare trailing closure still lands on `commit`.
    var submitted: (() -> Void)? = nil
    let commit: (Int?) -> Void

    @State private var text: String = ""
    /// What the field held when it last matched the model. A commit that would write the
    /// same thing back is skipped entirely.
    @State private var committed: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        field
            .frame(width: width)
            .monospacedDigit()
            .focused($isFocused)
            .accessibilityIdentifier(identifier)
            .onAppear { adopt(value) }
            .onChange(of: value) { _, new in
                // Held off only while the DM is mid-number. A focused field they have not
                // typed in has nothing to lose — and on macOS it stays focused through a
                // click on a segmented control or a button, so without this the Roll
                // sheet's DC field went on showing 15 after the DM picked 10 beside it.
                guard !isFocused || text == committed else { return }
                adopt(new)
            }
            .onChange(of: isFocused) { wasFocused, nowFocused in
                // Focus loss is a commit: a DM who types a number and clicks the next
                // field has decided, and requiring Return as well would lose it.
                if wasFocused && !nowFocused { commitText() }
            }
            .onSubmit {
                commitText()
                submitted?()
            }
    }

    /// Two styles cannot share one expression — `TextFieldStyle` is not existential.
    @ViewBuilder private var field: some View {
        if isPlain {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
        } else {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func adopt(_ value: Int?) {
        text = Self.string(value)
        committed = text
    }

    private func commitText() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Only when the DM actually changed something here. Without this, moving focus
        // away from a field they never typed in commits its current text — and a field
        // showing a Combatant who has no hit points yet commits "no hit points" over the
        // ones they just entered next door. That is how filling in Max wiped HP.
        guard trimmed != committed else {
            text = Self.string(value)
            return
        }
        commit(trimmed.isEmpty ? nil : Int(trimmed))
        adopt(value)
    }

    private static func string(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }
}
