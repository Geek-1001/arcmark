import AppKit
import Carbon.HIToolbox

@MainActor
protocol GlobalHotkeyServiceDelegate: AnyObject {
    func hotkeyServiceDidTrigger(_ service: GlobalHotkeyService)
}

// File-scope C-compatible callback for Carbon event handler
private func hotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        GlobalHotkeyService.shared.handleHotkeyEvent()
    }
    return noErr
}

@MainActor
final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()

    weak var delegate: GlobalHotkeyServiceDelegate?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Signature: "ARMK"
    private let hotkeySignature: OSType = 0x41524D4B
    private let hotkeyId: UInt32 = 1

    private init() {}

    func register(shortcut: KeyboardShortcut) {
        unregister()

        // Install event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // Register hotkey
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: hotkeyId)

        Carbon.RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func handleHotkeyEvent() {
        delegate?.hotkeyServiceDidTrigger(self)
    }
}
