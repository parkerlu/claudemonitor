import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A panel that can take keyboard focus. `NSPanel` refuses to become key by
/// default, and this one is nothing but a text field.
final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the floating composer: summoning it, returning focus to whatever you
/// were typing in, and putting the English there.
///
/// The Mac has no Messages extension point — `Messages.framework` is
/// `API_UNAVAILABLE(macos)` — so there is no in-app surface to live in. Pasting
/// into the frontmost app is the substitute, and it has the side benefit of
/// working in Slack, Mail and the browser rather than Messages alone.
@MainActor
final class ComposerController: NSObject, NSWindowDelegate {

    private let viewModel = ComposeViewModel()
    private let ui = ComposerUIState()
    private var panel: ComposerPanel?
    private var hotKey: GlobalHotKey?
    private var cancellables = Set<AnyCancellable>()

    /// Whatever was frontmost when we were summoned. We hand focus back to it
    /// before pasting, otherwise the keystroke lands on our own panel.
    private var previousApp: NSRunningApplication?

    func start() {
        hotKey = GlobalHotKey(
            keyCode: GlobalHotKey.optionSpace.keyCode,
            modifiers: GlobalHotKey.optionSpace.modifiers
        ) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }

        // 左右排列要的是「窗口更宽」，光换视图排布不够，得把窗口一起改掉。
        ui.$isSideBySide
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyWindowSize() }
            }
            .store(in: &cancellables)
    }

    var hotKeyRegistered: Bool { hotKey != nil }

    // MARK: - Showing

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.reloadSettings()

        let panel = panel ?? makePanel()
        self.panel = panel

        positionNearMouse(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> ComposerPanel {
        let panel = ComposerPanel(
            contentRect: NSRect(origin: .zero, size: ui.windowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        panel.contentView = NSHostingView(
            rootView: ComposerView(
                viewModel: viewModel,
                ui: ui,
                onInsert: { [weak self] text in self?.insert(text) },
                onDismiss: { [weak self] in self?.hide() }
            )
        )
        return panel
    }

    /// Put it under the pointer rather than dead centre — you summoned it while
    /// looking at a conversation, and that is where your eyes already are.
    private func positionNearMouse(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }

        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24)
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
    }

    /// 改尺寸时锚住左上角。默认行为是锚左下角，切换排布时窗口会整个往上蹿。
    private func applyWindowSize() {
        guard let panel else { return }
        let size = ui.windowSize
        var frame = panel.frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        frame.size = size
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)

        if let visible = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 12), visible.maxX - size.width - 12)
            frame.origin.y = min(max(frame.minY, visible.minY + 12), visible.maxY - size.height - 12)
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Inserting

    private func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        viewModel.reset()
        // 钉住的意义就是连着写下一句，这时收起来等于白钉。
        if !ui.isPinned { hide() }
        previousApp?.activate()

        guard AXIsProcessTrusted() else {
            // No Accessibility permission: the text is on the clipboard, which
            // is still useful — say so rather than appearing to do nothing.
            Self.notifyClipboardOnly()
            return
        }

        // Give the app we just reactivated a moment to take focus; a paste sent
        // into the switch lands nowhere.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.sendCommandV()
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func notifyClipboardOnly() {
        let alert = NSAlert()
        alert.messageText = "英文已复制到剪贴板"
        alert.informativeText = """
        要让它自动粘贴，需要在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 EnDraft。
        在那之前按 ⌘V 即可。
        """
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开设置")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away means you went back to what you were doing — unless you
        // pinned the panel, which is exactly the request not to do this.
        guard !ui.isPinned else { return }
        hide()
    }
}
