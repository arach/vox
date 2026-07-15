import Carbon.HIToolbox
import AppKit
import SwiftUI

enum MinivoxAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct DictationShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let title: String

    init(keyCode: UInt32, modifiers: UInt32, title: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.title = title
    }

    static let optionSpace = DictationShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        title: "⌥Space"
    )

    static let controlSpace = DictationShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey),
        title: "⌃Space"
    )

    static let optionShiftSpace = DictationShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | shiftKey),
        title: "⌥⇧Space"
    )

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        var modifierTitle = ""

        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
            modifierTitle += "⌃"
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
            modifierTitle += "⌥"
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
            modifierTitle += "⇧"
        }
        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
            modifierTitle += "⌘"
        }

        guard let keyTitle = Self.keyTitle(for: event),
              carbonModifiers != 0 || Self.isFunctionKey(event.keyCode) else {
            return nil
        }

        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        title = modifierTitle + keyTitle
    }

    private static func keyTitle(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            let value = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return value?.isEmpty == false ? value : nil
        }
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
             kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class GlobalShortcutController {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    controller.performAction()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    isolated deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func register(_ shortcut: DictationShortcut?) -> Bool {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        guard let shortcut else { return true }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x4D_56_4F_58, id: 1) // MVOX
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr else { return false }
        hotKey = reference
        return true
    }

    private func performAction() {
        action()
    }
}
