import AppKit
import SwiftUI

/// Owns the borderless Player Display window. POC: plain borderless window covering the screen.
@MainActor
final class PlayerWindowController {
    private var window: NSWindow?
    private var hasContentView = false

    func present(appState: AppState, on screen: NSScreen) {
        // Any window still on the player screen after the rescue attempt would be
        // buried under a Map at menu-bar level with no way back — the "buttons don't
        // work" failure. The Map yields to it instead: presenting on the screen that
        // holds the controls is a preview convenience, never a real presentation.
        let stranded = moveBuriedWindows(offPlayerScreen: screen)
        let w = window ?? makeWindow(on: screen)
        w.level = stranded ? .normal : Self.aboveMenuBar
        // The hosting view observes AppState and updates itself; rebuilding it on
        // every present() (which fires per drag tick) would churn the whole hierarchy.
        if !hasContentView {
            w.contentView = NSHostingView(rootView: PlayerView().environmentObject(appState))
            hasContentView = true
        }
        if w.frame != screen.frame {
            w.setFrame(screen.frame, display: true)
        }
        if !w.isVisible {
            w.orderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// The Player window covers its screen above the menu bar: any app window left
    /// there (typically the Control Window) would be buried and unclickable —
    /// "the buttons don't work". Move such windows to another screen first.
    /// Returns true when a window remains on the player screen with nowhere to go.
    @discardableResult
    private func moveBuriedWindows(offPlayerScreen screen: NSScreen) -> Bool {
        let otherScreens = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        var stranded = false
        for w in NSApp.windows where w !== window && w.isVisible && !(w is NSPanel) {
            guard w.frame.intersects(screen.frame) else { continue }
            if let rescue = WindowLayout.controlWindowRelocation(controlFrame: w.frame,
                                                                 playerScreenFrame: screen.frame,
                                                                 otherScreenFrames: otherScreens) {
                w.setFrame(rescue, display: true)
            } else {
                stranded = true
            }
        }
        return stranded
    }

    /// With "displays have separate Spaces" the external screen carries its own menu
    /// bar, which floats over normal-level windows — the Map must sit above it.
    private static let aboveMenuBar = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = Self.aboveMenuBar
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        w.animationBehavior = .none
        window = w
        return w
    }
}
