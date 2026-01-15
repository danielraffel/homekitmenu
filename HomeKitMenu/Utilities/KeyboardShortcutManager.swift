import Foundation
import Combine

#if targetEnvironment(macCatalyst)
import UIKit

/// Represents a keyboard shortcut binding
struct KeyboardShortcut: Codable, Equatable, Identifiable {
    var id: String { targetID }
    let targetID: String // UUID string for accessory or scene name
    let targetType: TargetType
    let keyCode: UInt16
    let modifierFlags: UInt // NSEvent.ModifierFlags raw value

    enum TargetType: String, Codable {
        case accessory
        case scene
    }

    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags

        if flags & (1 << 17) != 0 { parts.append("⌃") } // Control
        if flags & (1 << 19) != 0 { parts.append("⌥") } // Option
        if flags & (1 << 20) != 0 { parts.append("⇧") } // Shift
        if flags & (1 << 20) != 0 || flags & (1 << 8) != 0 { } // Command check below
        if flags & (1 << 20) == 0 && modifierFlags & 0x100000 != 0 { parts.append("⌘") }

        // Simplified - just show the modifier symbols and key
        let keyChar = keyCodeToString(keyCode)
        parts.append(keyChar)

        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        // Common key codes to characters
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return keyMap[code] ?? "?"
    }
}

/// Manages global keyboard shortcuts for controlling HomeKit devices and scenes
@MainActor
final class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()

    @Published var shortcuts: [KeyboardShortcut] = []
    @Published var isRecording = false
    @Published var recordingTargetID: String?

    private var globalMonitor: AnyObject?
    private var localMonitor: AnyObject?
    private let shortcutsKey = "keyboardShortcuts"

    weak var homeKitManager: HomeKitManager?

    private init() {
        loadShortcuts()
    }

    func setup(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager
        startGlobalMonitoring()
    }

    // MARK: - Shortcut Management

    func shortcut(for targetID: String) -> KeyboardShortcut? {
        shortcuts.first { $0.targetID == targetID }
    }

    func setShortcut(_ shortcut: KeyboardShortcut) {
        // Remove existing shortcut for this target
        shortcuts.removeAll { $0.targetID == shortcut.targetID }
        shortcuts.append(shortcut)
        saveShortcuts()
    }

    func removeShortcut(for targetID: String) {
        shortcuts.removeAll { $0.targetID == targetID }
        saveShortcuts()
    }

    // MARK: - Recording

    func startRecording(for targetID: String, type: KeyboardShortcut.TargetType) {
        recordingTargetID = targetID
        isRecording = true
        startLocalMonitoring(targetID: targetID, type: type)
    }

    func stopRecording() {
        isRecording = false
        recordingTargetID = nil
        stopLocalMonitoring()
    }

    // MARK: - Global Monitoring

    private func startGlobalMonitoring() {
        guard let nsEventClass = NSClassFromString("NSEvent") else { return }

        // Add global monitor for key down events
        let addMonitorSelector = NSSelectorFromString("addGlobalMonitorForEventsMatchingMask:handler:")
        guard nsEventClass.responds(to: addMonitorSelector) else { return }

        let mask: UInt64 = 1 << 10 // NSEvent.EventTypeMask.keyDown

        let handler: @convention(block) (AnyObject) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalKeyEvent(event)
            }
        }

        let inv = (nsEventClass as AnyObject).method(for: addMonitorSelector)
        typealias MonitorFunc = @convention(c) (AnyObject, Selector, UInt64, AnyObject) -> AnyObject?
        let monitorFunc = unsafeBitCast(inv, to: MonitorFunc.self)

        globalMonitor = monitorFunc(nsEventClass as AnyObject, addMonitorSelector, mask, handler as AnyObject)
    }

    private func stopGlobalMonitoring() {
        guard let monitor = globalMonitor,
              let nsEventClass = NSClassFromString("NSEvent") else { return }

        let removeSelector = NSSelectorFromString("removeMonitor:")
        _ = (nsEventClass as AnyObject).perform(removeSelector, with: monitor)
        globalMonitor = nil
    }

    private func startLocalMonitoring(targetID: String, type: KeyboardShortcut.TargetType) {
        guard let nsEventClass = NSClassFromString("NSEvent") else { return }

        let addMonitorSelector = NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:")
        guard nsEventClass.responds(to: addMonitorSelector) else { return }

        let mask: UInt64 = 1 << 10 // keyDown

        let handler: @convention(block) (AnyObject) -> AnyObject? = { [weak self] event in
            Task { @MainActor in
                self?.handleRecordingKeyEvent(event, targetID: targetID, type: type)
            }
            return nil // Consume the event
        }

        let inv = (nsEventClass as AnyObject).method(for: addMonitorSelector)
        typealias LocalMonitorFunc = @convention(c) (AnyObject, Selector, UInt64, AnyObject) -> AnyObject?
        let localMonitorFunc = unsafeBitCast(inv, to: LocalMonitorFunc.self)

        localMonitor = localMonitorFunc(nsEventClass as AnyObject, addMonitorSelector, mask, handler as AnyObject)
    }

    private func stopLocalMonitoring() {
        guard let monitor = localMonitor,
              let nsEventClass = NSClassFromString("NSEvent") else { return }

        let removeSelector = NSSelectorFromString("removeMonitor:")
        _ = (nsEventClass as AnyObject).perform(removeSelector, with: monitor)
        localMonitor = nil
    }

    // MARK: - Event Handling

    private func handleGlobalKeyEvent(_ event: AnyObject) {
        guard !isRecording else { return }

        // Get key code
        let keyCodeSelector = NSSelectorFromString("keyCode")
        let keyCodeInv = event.method(for: keyCodeSelector)
        typealias KeyCodeFunc = @convention(c) (AnyObject, Selector) -> UInt16
        let keyCodeFunc = unsafeBitCast(keyCodeInv, to: KeyCodeFunc.self)
        let keyCode = keyCodeFunc(event, keyCodeSelector)

        // Get modifier flags
        let modifierSelector = NSSelectorFromString("modifierFlags")
        let modifierInv = event.method(for: modifierSelector)
        typealias ModifierFunc = @convention(c) (AnyObject, Selector) -> UInt
        let modifierFunc = unsafeBitCast(modifierInv, to: ModifierFunc.self)
        let modifiers = modifierFunc(event, modifierSelector)

        // Find matching shortcut
        for shortcut in shortcuts {
            if shortcut.keyCode == keyCode && shortcut.modifierFlags == modifiers {
                executeShortcut(shortcut)
                break
            }
        }
    }

    private func handleRecordingKeyEvent(_ event: AnyObject, targetID: String, type: KeyboardShortcut.TargetType) {
        // Get key code
        let keyCodeSelector = NSSelectorFromString("keyCode")
        let keyCodeInv = event.method(for: keyCodeSelector)
        typealias KeyCodeFunc = @convention(c) (AnyObject, Selector) -> UInt16
        let keyCodeFunc = unsafeBitCast(keyCodeInv, to: KeyCodeFunc.self)
        let keyCode = keyCodeFunc(event, keyCodeSelector)

        // Get modifier flags
        let modifierSelector = NSSelectorFromString("modifierFlags")
        let modifierInv = event.method(for: modifierSelector)
        typealias ModifierFunc = @convention(c) (AnyObject, Selector) -> UInt
        let modifierFunc = unsafeBitCast(modifierInv, to: ModifierFunc.self)
        let modifiers = modifierFunc(event, modifierSelector)

        // Skip if no modifier keys are pressed (require at least one modifier)
        let modifierMask: UInt = 0x1F0000 // Control, Option, Shift, Command, Function
        if modifiers & modifierMask == 0 {
            return
        }

        // Ignore modifier-only key presses
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Shift, Control, Option, Command keys
        if modifierOnlyKeyCodes.contains(keyCode) {
            return
        }

        // Create and save the shortcut
        let shortcut = KeyboardShortcut(
            targetID: targetID,
            targetType: type,
            keyCode: keyCode,
            modifierFlags: modifiers & modifierMask
        )

        setShortcut(shortcut)
        stopRecording()
    }

    private func executeShortcut(_ shortcut: KeyboardShortcut) {
        guard let homeKitManager = homeKitManager else { return }

        switch shortcut.targetType {
        case .accessory:
            if let uuid = UUID(uuidString: shortcut.targetID),
               let accessory = homeKitManager.accessories.first(where: { $0.uniqueIdentifier == uuid }) {
                Task {
                    await homeKitManager.toggleAccessory(accessory)
                    StatusBarController.shared.updateMenu()
                }
            }

        case .scene:
            if let home = homeKitManager.currentHome,
               let scene = home.actionSets.first(where: { $0.name == shortcut.targetID }) {
                home.executeActionSet(scene) { error in
                    if let error = error {
                        print("Failed to execute scene: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: shortcutsKey),
           let loaded = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            shortcuts = loaded
        }
    }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: shortcutsKey)
        }
    }
}

#else

// Stub for non-Catalyst builds
@MainActor
final class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()
    @Published var shortcuts: [String] = []
    @Published var isRecording = false
    @Published var recordingTargetID: String?
    weak var homeKitManager: HomeKitManager?
    func setup(homeKitManager: HomeKitManager) {}
    func shortcut(for targetID: String) -> String? { nil }
    func startRecording(for targetID: String, type: String) {}
    func stopRecording() {}
    func removeShortcut(for targetID: String) {}
}

#endif
