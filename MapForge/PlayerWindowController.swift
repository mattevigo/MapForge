import AppKit
import SwiftUI

/// Owns the borderless Player Display window. POC: plain borderless window covering the screen.
@MainActor
final class PlayerWindowController {
    private var window: NSWindow?
    private var hasContentView = false

    func present(appState: AppState, on screen: NSScreen) {
        moveBuriedWindows(offPlayerScreen: screen)
        let w = window ?? makeWindow(on: screen)
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
    private func moveBuriedWindows(offPlayerScreen screen: NSScreen) {
        let otherScreens = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        for w in NSApp.windows where w !== window && w.isVisible && !(w is NSPanel) {
            if let rescue = WindowLayout.controlWindowRelocation(controlFrame: w.frame,
                                                                 playerScreenFrame: screen.frame,
                                                                 otherScreenFrames: otherScreens) {
                w.setFrame(rescue, display: true)
            }
        }
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        // Above the menu bar: with "displays have separate Spaces" the external
        // screen carries its own menu bar, which floats over normal-level windows.
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        w.animationBehavior = .none
        window = w
        return w
    }
}
