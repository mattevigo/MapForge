import SwiftUI

/// What the Stat Block editor is pointed at, as a fight starts and stops.
enum CombatSelectionPolicy {
    /// The selection that survives an Encounter ending.
    ///
    /// None of it. A selection made during a fight is a row in the Order, and when the fight
    /// stops there is no Order to be a row of. Left alone, the editor went on offering the
    /// last Combatant's hit points under a heading that said the fight was over, and a DM
    /// who typed into it was editing a Pawn they had not chosen *here*. The idle roster's
    /// rows are selectable in their own right, and show it — so the DM who wants that Pawn
    /// again clicks it, and the one who does not is not left editing it by accident.
    ///
    /// Stopping a fight neither heals anyone nor clears their Conditions (`CONTEXT.md`,
    /// **Encounter**); this clears what is *pointed at*, not anything pointed to.
    static func afterEncounterEnds() -> Pawn.ID? { nil }
}

/// The Initiative Tracker: the Order of Combatants and the controls that drive a fight.
///
/// Reads its numbers from the `Encounter`, which derives them from its Combat Log — so
/// what this draws is what the file says, with no third copy in between.
struct CombatPanel: View {
    @EnvironmentObject private var appState: AppState

    /// Which row the Stat Block editor is pointed at. Independent of whose Turn it is: a DM
    /// edits the monster the party just hit, not the one acting.
    @Binding var selection: Pawn.ID?

    /// Asks for the Roll sheet. A callback rather than a sheet of this panel's own: the
    /// sheet is the same one the live row opens, and two presentations of one sheet is two
    /// places for its dismissal to go wrong.
    var onRoll: (Pawn, RollKind) -> Void = { _, _ in }

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
        // Watched here rather than cleared in `stopEncounter`, because the selection is this
        // panel's and `AppState` does not know the editor exists. Covers every way a fight
        // can end — the button, closing the Map, switching Workspace — since all of them
        // arrive as `encounter` becoming nil.
        .onChange(of: appState.encounter == nil) { _, ended in
            if ended { selection = CombatSelectionPolicy.afterEncounterEnds() }
        }
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
                .disabled(!hasRosteredCombatants || appState.encounterRefusal != nil)
                .help(appState.encounterRefusal
                      ?? "Roll Initiative for everyone on the Map and begin.")
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

    /// Whether anything on the Map could fight at all, roster aside.
    private var hasCombatants: Bool {
        appState.fog.pawns.contains { $0.kind != .treasure }
    }

    /// Whether pressing play would start anything. A Map full of Pawns with every one of
    /// them ticked out is a Map with no fight in it.
    private var hasRosteredCombatants: Bool {
        appState.fog.pawns.contains { $0.kind != .treasure && appState.isInCombat($0.id) }
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
        // Everything on the Map that is not taking Turns: left off the roster before the
        // fight, Benched during it, placed since it began, or Treasure. One honest list of
        // "here but not fighting" beats several that mean nearly the same thing.
        let benched = appState.notInCombat
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
            //
            // Edited in place. The players call their numbers out down this column as the
            // fight starts, and overtyping them here — Tab from one to the next — is the
            // whole job; the Stat Block editor's "Init" is the *bonus*. Committed on Return
            // or on leaving the field, and **not** re-sorted: ties and their order are the
            // DM's, so the row stays put until it is dragged (`CONTEXT.md`, **Initiative**).
            NumberField(value: encounter.initiative(of: id),
                        identifier: "combatant-initiative",
                        width: 30,
                        isPlain: true) { new in
                // Cleared is not zero: an emptied field means the DM backed out.
                if let new { appState.setInitiative(new, for: id) }
            }
                .font(.system(.body, design: .rounded).weight(.semibold))
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

            // A Roll is recorded from the row the DM is already looking at. Styled as
            // `bench` is, and like it these identifiers are swallowed by the row's
            // `.combine` below — the behaviour is held down by `RollRoutingTests` instead,
            // which is where it is worth testing anyway.
            if let pawn = appState.fog.pawns.first(where: { $0.id == id }) {
                Button {
                    onRoll(pawn, .savingThrow)
                } label: {
                    Image(systemName: "bolt.shield")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("combatant-saving-throw")
                .help("Record a Saving Throw for \(encounter.name(of: id) ?? "this Combatant").")

                Button {
                    onRoll(pawn, .abilityCheck)
                } label: {
                    Image(systemName: "figure.run")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("combatant-ability-check")
                .help("Record an Ability Check for \(encounter.name(of: id) ?? "this Combatant").")
            }

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

    /// One Pawn of the roster, before the fight — selectable, so the Stat Block editor
    /// below can be pointed at it.
    ///
    /// Prep is when a Stat Block most needs an editor and for a long time had none: the
    /// initiative bonus is what Play is about to roll with, and hit points typed after the
    /// fight starts are typed while six people wait. The bonus is shown on the row because
    /// it is the one number here the DM cannot see anywhere else before rolling. Clicking
    /// the selected row again lets go of it.
    private func rosterRow(_ pawn: Pawn) -> some View {
        let block = appState.statBlock(for: pawn.id)
        return HStack(spacing: 4) {
            kindMark(pawn.kind)
            Text(pawn.label).lineLimit(1)
            Spacer(minLength: 8)
            Text(block.initiativeBonus < 0 ? "−\(-block.initiativeBonus)"
                                           : "+\(block.initiativeBonus)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Initiative bonus")
            hitPoints(block)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selection == pawn.id ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = selection == pawn.id ? nil : pawn.id }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("roster-row")
        .accessibilityLabel(Text(pawn.label))
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

    /// Before a fight: who would roll if the DM pressed play.
    ///
    /// Shown rather than left to be discovered, because the roster is set in the Scene tab
    /// and a DM should not have to switch back to find out who is in. The count is the
    /// thing that catches "why is the barkeep rolling".
    private var idle: some View {
        let rostered = appState.fog.pawns.filter {
            $0.kind != .treasure && appState.isInCombat($0.id)
        }
        return VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            // Why Play is grey, where the DM is looking when they wonder.
            if let refusal = appState.encounterRefusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("encounter-refusal")
            }
            if rostered.isEmpty {
                Text(hasCombatants
                     ? "Nobody on the Map is in the next fight"
                     : "Nobody on the Map to fight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if hasCombatants {
                    Text("Tick them in the Scene tab.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("^[\(rostered.count) Pawn](inflect: true) ready to roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rostered) { pawn in
                        rosterRow(pawn)
                    }
                }
                .accessibilityIdentifier("roster-preview")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
