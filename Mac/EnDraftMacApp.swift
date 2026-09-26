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
            SettingsLink { Text("设置…") }
            Divider()
            Button("退出 EnDraft") { NSApplication.shared.terminate(nil) }
        }

        Settings {
            MacSettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composer = ComposerController()

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
