import AppKit
import SwiftUI

/// Menu-bar app. There is no Messages extension point on macOS —
/// `Messages.framework` is `API_UNAVAILABLE(macos)` — so instead of living
/// inside Messages we float above whatever you are typing in and paste into it.
/// Which also means this works in Slack, Mail and the browser, not just
/// Messages.
@main
struct EnDraftMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("EnDraft", systemImage: "character.bubble") {
            Button("写一句…  ⌥Space") { delegate.composer.show() }
            Divider()
            Button("设置…") { delegate.showSettings() }
            Divider()
            Button("退出 EnDraft") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composer = ComposerController()

    private var settingsWindow: NSWindow?

    /// Owns the settings window directly instead of using SwiftUI's `Settings`
    /// scene and `SettingsLink`.
    ///
    /// LSUIElement apps are not activated by clicking a menu-bar item, and this
    /// SDK's SettingsLink has no preAction/postAction hook to activate from — so
    /// the scene's window opened without ever coming to the front, which looks
    /// exactly like the menu item doing nothing. An NSWindow we activate
    /// ourselves is the same pattern the composer panel already uses.
    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EnDraft 设置"
        window.contentView = NSHostingView(rootView: MacSettingsView())
        // Closing settings must not destroy the window, or reopening it crashes.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        composer.start()

        if !composer.hotKeyRegistered {
            warnHotKeyTaken()
        }

        // Ask for Accessibility up front rather than at the moment of the first
        // paste — being interrupted mid-sentence by a permission dialog is
        // worse than being asked once at launch. Declining is fine; the text
        // still reaches the clipboard.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func warnHotKeyTaken() {
        let alert = NSAlert()
        alert.messageText = "⌥Space 已被别的 App 占用"
        alert.informativeText = "EnDraft 仍然可以从菜单栏图标里打开。"
        alert.runModal()
    }
}
