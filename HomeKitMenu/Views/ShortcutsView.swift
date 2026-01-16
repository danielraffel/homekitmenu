import SwiftUI

#if targetEnvironment(macCatalyst)

/// View for assigning keyboard shortcuts to accessories and scenes
struct ShortcutsView: View {
    let homeKitManager: HomeKitManager
    let preferences: UserPreferences
    @StateObject private var shortcutManager = KeyboardShortcutManager.shared
    @Environment(\.dismiss) private var dismiss

    private var selectedAccessories: [HomeAccessory] {
        homeKitManager.accessories.filter { preferences.isSelected($0) }
    }

    private var scenes: [String] {
        guard let home = homeKitManager.currentHome else { return [] }
        return home.actionSets
            .filter { !$0.name.hasPrefix("com.apple") }
            .map { $0.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedAccessories.isEmpty {
                    Section("Devices") {
                        ForEach(selectedAccessories) { accessory in
                            ShortcutRow(
                                name: accessory.name,
                                icon: preferences.customIcon(for: accessory) ?? accessory.smartIcon ?? accessory.type.icon,
                                targetID: accessory.uniqueIdentifier.uuidString,
                                targetType: .accessory,
                                shortcutManager: shortcutManager
                            )
                        }
                    }
                }

                if !scenes.isEmpty {
                    Section("Scenes") {
                        ForEach(scenes, id: \.self) { sceneName in
                            ShortcutRow(
                                name: sceneName,
                                icon: "theatermasks.fill",
                                targetID: sceneName,
                                targetType: .scene,
                                shortcutManager: shortcutManager
                            )
                        }
                    }
                }

                Section {
                    Text("Click \"Record\" and press your desired key combination (e.g., ⌘⇧L). Shortcuts require at least one modifier key (⌘, ⌥, ⌃, or ⇧).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 400, minHeight: 450)
        #endif
    }
}

struct ShortcutRow: View {
    let name: String
    let icon: String
    let targetID: String
    let targetType: KeyboardShortcut.TargetType
    @ObservedObject var shortcutManager: KeyboardShortcutManager

    private var currentShortcut: KeyboardShortcut? {
        shortcutManager.shortcut(for: targetID)
    }

    private var isRecording: Bool {
        shortcutManager.isRecording && shortcutManager.recordingTargetID == targetID
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(name)
                .lineLimit(1)

            Spacer()

            if isRecording {
                Text("Press keys...")
                    .foregroundStyle(.blue)
                    .font(.callout)

                Button("Cancel") {
                    shortcutManager.stopRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let shortcut = currentShortcut {
                Text(shortcut.displayString)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                Button("Clear") {
                    shortcutManager.removeShortcut(for: targetID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Record") {
                    shortcutManager.startRecording(for: targetID, type: targetType)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

#else

struct ShortcutsView: View {
    let homeKitManager: HomeKitManager
    let preferences: UserPreferences

    var body: some View {
        Text("Shortcuts not available")
    }
}

#endif
