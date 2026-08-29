import AppKit
import SwiftUI

/// Owns the borderless Player Display window. POC: plain borderless window covering the screen.
@MainActor
final class PlayerWindowController {
    private var window: NSWindow?

    func present(appState: AppState, on screen: NSScreen) {
        let w = window ?? makeWindow(on: screen)
        w.setFrame(screen.frame, display: true)
        w.contentView = NSHostingView(rootView: PlayerView().environmentObject(appState))
        w.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
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
