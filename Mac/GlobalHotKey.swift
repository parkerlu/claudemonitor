import AppKit
import Carbon.HIToolbox

/// A system-wide hot key.
///
/// Carbon's `RegisterEventHotKey` is used rather than `NSEvent`'s global
/// monitor because the latter needs Accessibility permission just to observe
/// keys. We do ask for Accessibility later, to paste — but summoning the
/// composer should work the moment the app launches, before any prompt.
final class GlobalHotKey {

    /// ⌥Space. Chosen because ⌘Space and ⌃Space belong to Spotlight and input
    /// switching, which matters more than usual here — this app is for people
    /// typing Chinese, who use the input switcher constantly.
    static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1
        Self.callbacks[id] = onFire

        // 'ENDR'
        let hotKeyID = EventHotKeyID(signature: 0x454E_4452, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr else {
            Self.callbacks[id] = nil
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.callbacks[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var firedID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &firedID
                )
                GlobalHotKey.callbacks[firedID.id]?()
                return noErr
            },
            1, &spec, nil, nil
        )
    }
}
