import SwiftUI

/// The Initiative Tracker: the Order of Combatants and the controls that drive a fight.
///
/// Reads its numbers from the `Encounter`, which derives them from its Combat Log — so
/// what this draws is what the file says, with no third copy in between.
struct CombatPanel: View {
    @EnvironmentObject private var appState: AppState

    /// Which row the Stat Block editor is pointed at. Independent of whose Turn it is: a DM
    /// edits the monster the party just hit, not the one acting.
    @Binding var selection: Pawn.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let encounter = appState.encounter {
                order(encounter)
            } else {
                idle
            }
            // Below the list, as the spec asks: the numbers a DM changes mid-fight, and
            // the box they type a note into. Edits reflect into the rows above because
            // both read the same folded state.
            StatEditor(combatant: selection ?? appState.encounter?.activeCombatantID)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }

    // MARK: The header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            if let encounter = appState.encounter {
                if let target = encounter.correctionTarget {
                    correctingBar(encounter, target: target)
                } else {
                    HStack(spacing: 6) {
                        Text("Round \(encounter.round)")
                            .font(.headline)
                            .accessibilityIdentifier("round-number")
                        Spacer(minLength: 0)
                    }
                }
            }
            controls
        }
        .padding(8)
    }

    /// The correcting state, over-signalled on purpose.
    ///
    /// ADR-0010 names this the most dangerous interaction in the feature: an edit made in
    /// the wrong mode is silent and wrong. A coloured bar naming the Turn being amended is
    /// the cheapest way to make the mode impossible to miss.
    private func correctingBar(_ encounter: Encounter, target: Encounter.TurnRef) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
            Text("Correcting Round \(target.round) — \(encounter.name(of: target.combatantID) ?? "?")")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange))
        .accessibilityIdentifier("correcting-bar")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            if appState.encounter == nil {
                Button {
                    appState.startEncounter()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .accessibilityIdentifier("encounter-play")
                .disabled(!hasCombatants)
                .help("Roll Initiative for everyone on the Map and begin.")
            } else {
                Button {
                    appState.stepBackForCorrection()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityIdentifier("encounter-previous")
                .help("Go back to correct an earlier Turn. The fight does not rewind.")

                Button {
                    appState.endTurn()
                } label: {
                    Label("Next", systemImage: "forward.fill")
                }
                .accessibilityIdentifier("encounter-next")
                .help(appState.encounter?.isCorrecting == true
                      ? "Return towards the live Turn. A Turn cannot be ended while correcting."
                      : "End this Turn and write it to the Combat Log.")

                Spacer(minLength: 0)

                Button {
                    isConfirmingReroll = true
                } label: {
                    Image(systemName: "dice.fill")
                }
                .accessibilityIdentifier("encounter-reroll")
                .help("Re-roll every Initiative. The Round does not reset.")

                Button {
                    isConfirmingStop = true
                } label: {
                    Image(systemName: "stop.fill")
                }
                .accessibilityIdentifier("encounter-stop")
                .help("End the fight and close its Combat Log.")
            }
        }
        .buttonStyle(.bordered)
        .confirmationDialog("Re-roll every Initiative?", isPresented: $isConfirmingReroll) {
            Button("Re-roll", role: .destructive) { appState.rerollInitiative() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Order you have now is replaced. The Round stays where it is.")
        }
        .confirmationDialog("End this encounter?", isPresented: $isConfirmingStop) {
            Button("End Encounter", role: .destructive) { appState.stopEncounter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Combat Log is closed. Nobody is healed and no Condition is cleared.")
        }
    }

    @State private var isConfirmingReroll = false
    @State private var isConfirmingStop = false

    private var hasCombatants: Bool {
        appState.fog.pawns.contains { $0.kind != .treasure }
    }

    // MARK: The Order

    private func order(_ encounter: Encounter) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(encounter.order, id: \.self) { id in
                    row(encounter, id: id)
                }
                bench(encounter)
            }
            .padding(6)
        }
    }

    /// What is on the Map but out of the Order — see `CONTEXT.md`, **Benched**.
    ///
    /// Under the Order rather than hidden behind a disclosure, because a DM needs to see
    /// the whole room: the goblin bleeding out on the floor is still a thing in the fight
    /// even while it takes no Turns.
    @ViewBuilder
    private func bench(_ encounter: Encounter) -> some View {
        // Everything on the Map that is not taking Turns, not only what was benched out of
        // the Order: a Treasure, and anything placed since the fight began. One honest list
        // of "here but not fighting" beats two lists that mean nearly the same thing.
        let onMap = Set(appState.fog.pawns.map(\.id))
        let inOrder = Set(encounter.order)
        let benched = (encounter.benched.union(onMap.subtracting(inOrder)))
            .sorted { name(of: $0, in: encounter) < name(of: $1, in: encounter) }
        if !benched.isEmpty {
            Divider().padding(.vertical, 4)
            Text("Not in combat")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            ForEach(benched, id: \.self) { id in
                benchRow(encounter, id: id)
            }
        }
    }

    /// A Benched Pawn's name, from the Encounter if it was ever in it and from the Map
    /// otherwise — a Pawn stamped after the fight began has no Log entry to be named by.
    private func name(of id: Pawn.ID, in encounter: Encounter) -> String {
        encounter.name(of: id)
            ?? appState.fog.pawns.first { $0.id == id }?.label
            ?? "?"
    }

    private func kind(of id: Pawn.ID, in encounter: Encounter) -> PawnKind {
        encounter.kind(of: id)
            ?? appState.fog.pawns.first { $0.id == id }?.kind
            ?? .creature
    }

    private func benchRow(_ encounter: Encounter, id: Pawn.ID) -> some View {
        let block = encounter.blocks[id] ?? appState.statBlock(for: id)
        let kind = kind(of: id, in: encounter)
        return HStack(spacing: 6) {
            Button {
                appState.unbenchCombatant(id)
            } label: {
                Image(systemName: "arrow.uturn.up")
                    .font(.system(size: 9))
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("unbench")
            // A Treasure has nothing to do on its turn, so there is nowhere to put it back
            // to. Shown in the list because it is in the room; not offered a way in.
            .disabled(kind == .treasure)
            .opacity(kind == .treasure ? 0 : 1)
            .help("Roll Initiative and put back into the Order")

            kindMark(kind)

            Text(name(of: id, in: encounter))
                .lineLimit(1)

            Spacer(minLength: 0)
            hitPoints(block)
            conditions(block)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .onTapGesture { selection = id }
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selection == id ? Color.accentColor : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("benched-row")
        .accessibilityLabel(Text(encounter.name(of: id) ?? "?"))
    }

    private func row(_ encounter: Encounter, id: Pawn.ID) -> some View {
        let block = encounter.blocks[id] ?? StatBlock()
        let isActive = encounter.activeCombatantID == id && !encounter.isCorrecting

        return HStack(spacing: 6) {
            // On its own ground rather than as bold text beside the name: at the table
            // "13  2" read as one number and a stray digit, and the Initiative is the
            // column the DM's eye runs down.
            Text("\(encounter.initiative(of: id) ?? 0)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: 30)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 4))

            kindMark(encounter.kind(of: id) ?? .creature)

            Text(encounter.name(of: id) ?? "?")
                .lineLimit(1)

            Spacer(minLength: 0)

            hitPoints(block)
            armourClass(block)
            conditions(block)

            Button {
                appState.benchCombatant(id)
            } label: {
                Image(systemName: "arrow.uturn.down")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("bench")
            .help("Take out of the Order. Stays on the Map and can be put back.")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // Filled, not outlined: a DM reads this from across a table at a glance.
        .background(isActive ? Color.accentColor.opacity(0.30) : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selection == id ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = id }
        // Combined into one element, so the row is a row. Without this the identifier
        // propagates to every `Text` and `Image` inside it and a test counting rows counts
        // a dozen per Combatant.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("combatant-row")
        .accessibilityLabel(Text(encounter.name(of: id) ?? "?"))
    }

    /// Players and Creatures must be distinguishable at a glance, and never by colour
    /// alone — the disc and the square are the same distinction `PawnToken` already draws
    /// on the Map.
    @ViewBuilder
    private func kindMark(_ kind: PawnKind) -> some View {
        Group {
            switch kind {
            case .player:
                Image(systemName: "person.fill")
            case .creature:
                Image(systemName: "pawprint.fill")
            case .treasure:
                Image(systemName: "shippingbox.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(kind == .player ? Color.accentColor : Color.secondary)
        .frame(width: 14)
        .help(kind.title)
    }

    @ViewBuilder
    private func hitPoints(_ block: StatBlock) -> some View {
        if let current = block.currentHP, let max = block.maxHP {
            HStack(spacing: 1) {
                Text("\(current)")
                    .foregroundStyle(current <= 0 ? Color.red : .primary)
                if block.temporaryHP > 0 {
                    Text("+\(block.temporaryHP)").foregroundStyle(Color.teal)
                }
                Text("/\(max)").foregroundStyle(.secondary)
            }
            .font(.caption)
            .monospacedDigit()
        } else {
            // Flagged, never hidden: a forgotten Stat Block must not silently drop a
            // monster from the fight.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("No hit points yet — fill them in below.")
                .accessibilityIdentifier("incomplete-stat-block")
        }
    }

    private func armourClass(_ block: StatBlock) -> some View {
        HStack(spacing: 2) {
            // 8 points rendered as an indistinct grey dot on a real screen — checked by
            // eye, not by a test, because "is this legible" is not a thing a test knows.
            Image(systemName: "shield.fill").font(.system(size: 10))
            Text("\(block.armorClass)").monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Armour class \(block.armorClass)")
    }

    /// Icons, not words: fourteen Conditions will not fit as text in 320 points. Past
    /// three, the rest become a count — the DM opens the editor for the detail.
    @ViewBuilder
    private func conditions(_ block: StatBlock) -> some View {
        let shown = block.conditions.sorted { $0.rawValue < $1.rawValue }
        HStack(spacing: 2) {
            ForEach(shown.prefix(3), id: \.self) { condition in
                Image(systemName: condition.symbolName)
                    .font(.system(size: 9))
                    .help(condition.title)
            }
            if shown.count > 3 {
                Text("+\(shown.count - 3)").font(.system(size: 9))
            }
            if block.exhaustion > 0 {
                Text("E\(block.exhaustion)")
                    .font(.system(size: 9, weight: .semibold))
                    .help("Exhaustion \(block.exhaustion)")
            }
            if block.isConcentrating {
                Image(systemName: "circle.hexagonpath.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.purple)
                    .help("Concentrating")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(hasCombatants ? "No encounter yet" : "Nobody on the Map to fight")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }
}
