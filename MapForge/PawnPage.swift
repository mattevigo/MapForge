import AppKit
import SwiftUI

/// A page of the DM's notes, as the Stat Block editor's popover and a pinned panel show it:
/// a Monster's, or a Character's.
///
/// Named by what it is a page *of*, not by the Pawn it was opened from — every Ogre on the
/// Map has the one Ogre's page, and a page pinned in its own panel outlives the Pawn that
/// opened it. Read from the notes each time it is drawn (ADR-0020), so a pinned page follows
/// an edit to its note the way the popover does.
///
/// Built from a Pawn only for one that has a page — a Creature that is a Monster, or a Pawn
/// Stamped from a Character — so the editor offers the button exactly when there is something
/// behind it. A plain Pawn has no page, and no button saying it might.
struct PawnPage: View {
    enum Source: Hashable {
        /// The name the Pawns remember, looked up in the Bestiary.
        case monster(String)
        /// The Character the Pawns were Stamped from.
        case character(UUID)
    }

    let source: Source

    @EnvironmentObject private var appState: AppState

    init(source: Source) {
        self.source = source
    }

    init?(pawn: Pawn, appState: AppState) {
        if let monsterName = pawn.monsterName {
            source = .monster(monsterName)
        } else if let id = pawn.characterID, appState.characterPage(forCharacter: id) != nil {
            source = .character(id)
        } else {
            return nil
        }
    }

    var body: some View {
        switch source {
        case .monster(let monsterName):
            MonsterReferenceView(monsterName: monsterName, bestiary: appState.bestiary,
                                 unit: appState.distanceUnit)
        case .character(let id):
            if let page = appState.characterPage(forCharacter: id) {
                CharacterReferenceView(page: page, unit: appState.distanceUnit)
            } else {
                // Pinned, then deleted from the Party: the panel stays where the DM put it
                // and says why it is empty, rather than vanishing from under them.
                ReferenceCaption(text: Text("This Character is no longer in the Party."))
                    .accessibilityIdentifier("character-reference-gone")
            }
        }
    }

    /// What a pinned panel's title bar calls the page.
    static func title(of source: Source, in appState: AppState) -> String {
        switch source {
        case .monster(let monsterName):
            return monsterName
        case .character(let id):
            return appState.character(id: id)?.name ?? "?"
        }
    }

    // MARK: In the popover

    /// Wide enough for an action's line to read as a sentence, not a column.
    static let width: CGFloat = 380
    /// Between the page and the popover's edge.
    static let padding: CGFloat = 12
    /// Between the popover and the top and bottom of the screen — room for its arrow and its
    /// shadow, so it reads as a popover and not as a second window.
    static let screenMargin: CGFloat = 48
    /// The cap when there is no screen to measure.
    static let fallbackMaxHeight: CGFloat = 560

    /// The tallest the page may be: nearly the screen, so a Monster with a long list of
    /// actions is read whole rather than scrolled three lines at a time, and past that it
    /// scrolls inside the popover rather than running it off the screen. A short page is
    /// as tall as its text — this caps it, and never pads it out.
    ///
    /// `visibleHeight` is the screen's visible frame, already short of the menu bar and the
    /// Dock; it is given rather than read so the arithmetic can be tested without a screen.
    static func maxHeight(onScreenOfHeight visibleHeight: CGFloat?) -> CGFloat {
        guard let visibleHeight else { return fallbackMaxHeight }
        return max(visibleHeight - 2 * screenMargin - 2 * padding, fallbackMaxHeight / 2)
    }

    /// The page as the popover holds it: its width, its cap and its margin — and, given
    /// `pin`, the button that moves it into a panel of its own.
    ///
    /// In the corner rather than on a row of its own: a row would cost every page a line, to
    /// hold one button most pages are never pinned with.
    func inPopover(onScreenOfHeight visibleHeight: CGFloat?, pin: (() -> Void)? = nil) -> some View {
        frame(width: Self.width)
            .frame(maxHeight: Self.maxHeight(onScreenOfHeight: visibleHeight))
            .padding(Self.padding)
            .overlay(alignment: .topTrailing) {
                if let pin {
                    Button(action: pin) {
                        Image(systemName: "pin")
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                    .accessibilityIdentifier("pin-page")
                    .help("Pin this page in its own window, to keep it open")
                }
            }
    }

    // MARK: In a panel

    /// The narrowest a pinned panel is let go: past this an action wraps a word to a line.
    static let minimumPanelSize = CGSize(width: 260, height: 120)

    /// The page as a pinned panel holds it: filling whatever the DM resizes it to, and
    /// scrolling inside that.
    var inPanel: some View {
        frame(minWidth: Self.minimumPanelSize.width, maxWidth: .infinity,
              minHeight: Self.minimumPanelSize.height, maxHeight: .infinity,
              alignment: .topLeading)
            .padding(Self.padding)
    }
}

/// The pages pinned out of the popover, each in a panel of its own the DM can move and resize.
///
/// One panel per page, not per pin: the second Ogre's pin brings the first Ogre's panel
/// forward, since it would only open the same page twice.
///
/// Panels rather than windows: they float over the Control Window, step aside when the DM
/// switches to another app, and — `fullScreenAuxiliary` — open over a Control Window in full
/// screen instead of on a Space of their own. Never on the Player Display: a page is the DM's
/// reference, and each opens beside the Control Window.
@MainActor
final class PinnedPages: NSObject, NSWindowDelegate {
    private var panels: [PawnPage.Source: NSPanel] = [:]

    /// The pages pinned now.
    var pinned: Set<PawnPage.Source> { Set(panels.keys) }

    /// The panel `source`'s page is pinned in, if it is.
    func panel(for source: PawnPage.Source) -> NSPanel? { panels[source] }

    /// Opens `source`'s page in a panel of its own, or brings forward the one it already has.
    func pin(_ source: PawnPage.Source, appState: AppState) {
        if let panel = panels[source] {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let control = Self.controlWindow
        let screen = control?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = PawnPage.title(of: source, in: appState)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentMinSize = PawnPage.minimumPanelSize
        panel.delegate = self

        let host = NSHostingView(rootView: Self.environment(PawnPage(source: source).inPanel,
                                                            appState))
        // The page decides only how small the panel may go; how big is the DM's to drag.
        host.sizingOptions = [.minSize]
        panel.contentView = host

        // It opens at the popover's size, so pinning looks like the popover staying put.
        let size = NSHostingView(rootView: Self.environment(
            PawnPage(source: source).inPopover(onScreenOfHeight: visible.height), appState)).fittingSize
        let content = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        panel.setFrame(Self.frame(of: content, beside: control?.frame, within: visible,
                                  cascade: panels.count),
                       display: false)

        panels[source] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        // Copied first: each close removes its panel through `windowWillClose`.
        for panel in Array(panels.values) { panel.close() }
        panels.removeAll()
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panels = panels.filter { $0.value !== panel }
    }

    /// Where a new panel of `size` opens: right of the Control Window, top-aligned with it,
    /// when the screen has room there; otherwise inside the screen's right edge — which is
    /// where it goes over a Control Window in full screen. Each further pin steps down and
    /// in, so a new panel never lands exactly on the last. Always within `visible`.
    static func frame(of size: CGSize, beside control: NSRect?, within visible: NSRect,
                      cascade: Int) -> NSRect {
        let gap: CGFloat = 8
        let step = CGFloat(cascade) * 24
        let width = min(size.width, visible.width - 2 * gap)
        let height = min(size.height, visible.height - 2 * gap)
        let top = min(control?.maxY ?? visible.maxY, visible.maxY) - step

        var x: CGFloat
        if let control, control.maxX + gap + width <= visible.maxX {
            x = control.maxX + gap + step
        } else {
            x = visible.maxX - gap - width - step
        }
        x = min(max(x, visible.minX + gap), visible.maxX - gap - width)
        let y = min(max(top - height, visible.minY + gap), visible.maxY - gap - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The window MapForge's controls are in — found as `AppState` finds it when it closes.
    /// Not the key window: while the popover is up, the popover's own window is key.
    private static var controlWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("control") == true }
    }

    /// What the Control Window gives its views, which a panel's root does not inherit.
    private static func environment(_ view: some View, _ appState: AppState) -> some View {
        view.environmentObject(appState)
            .environment(\.locale, .interface)
    }
}
