import SwiftUI

#if targetEnvironment(macCatalyst)

/// View for selecting which Apple Shortcuts to show in the menu bar
struct ShortcutsSelectionView: View {
    @Bindable var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shortcutsManager = AppleShortcutsManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if shortcutsManager.isLoading {
                    ProgressView("Loading Shortcuts...")
                } else if shortcutsManager.allShortcuts.isEmpty {
                    ContentUnavailableView {
                        Label("No Shortcuts Found", systemImage: "bolt.slash")
                    } description: {
                        Text("Create shortcuts in the Shortcuts app first.")
                    } actions: {
                        Button("Refresh") {
                            shortcutsManager.loadShortcuts()
                        }
                    }
                } else {
                    List {
                        // Enable/Disable toggle at top
                        Section {
                            Toggle(isOn: $preferences.showAppleShortcuts) {
                                Label("Show in Menu Bar", systemImage: "menubar.rectangle")
                            }
                        }

                        if !preferences.showAppleShortcuts {
                            Section {
                                Text("Enable \"Show in Menu Bar\" above to see your selected shortcuts in the menu bar dropdown.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Folders section (if any folders exist)
                        if !shortcutsManager.folders.isEmpty {
                            Section {
                                ForEach(shortcutsManager.folders) { folder in
                                    FolderRow(
                                        folder: folder,
                                        preferences: preferences
                                    )
                                }
                            } header: {
                                HStack {
                                    Text("Folders")
                                    Spacer()
                                    Text("Tap to expand")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        // All Shortcuts list
                        Section {
                            // Select All/None buttons at the top
                            HStack {
                                Button {
                                    preferences.selectAllShortcuts()
                                    StatusBarController.shared.updateMenu()
                                } label: {
                                    Label("Select All", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)

                                Spacer()

                                Button {
                                    preferences.deselectAllShortcuts()
                                    StatusBarController.shared.updateMenu()
                                } label: {
                                    Label("Select None", systemImage: "circle")
                                }
                                .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                            ForEach(shortcutsManager.allShortcuts, id: \.self) { shortcut in
                                AppleShortcutRow(
                                    name: shortcut,
                                    isSelected: preferences.isShortcutSelected(shortcut),
                                    onToggle: {
                                        preferences.toggleShortcutSelection(shortcut)
                                        StatusBarController.shared.updateMenu()
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                Text("All Shortcuts")
                                Spacer()
                                Text("\(selectedCount) of \(shortcutsManager.allShortcuts.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shortcutsManager.loadShortcuts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 400, minHeight: 500)
        #endif
        .onChange(of: preferences.showAppleShortcuts) { _, _ in
            StatusBarController.shared.updateMenu()
        }
    }

    private var selectedCount: Int {
        if let selected = preferences.selectedShortcutNames {
            return selected.count
        }
        return shortcutsManager.allShortcuts.count // nil means all selected
    }
}

/// Row for a folder with expand/collapse and selection
struct FolderRow: View {
    let folder: ShortcutFolder
    @Bindable var preferences: UserPreferences
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)

                    Text(folder.displayName)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Quick select buttons (only when expanded)
                    if isExpanded {
                        HStack(spacing: 8) {
                            Button {
                                selectAllInFolder()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)

                            Button {
                                deselectAllInFolder()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("\(selectedInFolder)/\(folder.shortcuts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 30, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Shortcuts in this folder with dividers
                    ForEach(Array(folder.shortcuts.enumerated()), id: \.element) { index, shortcut in
                        VStack(spacing: 0) {
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                            AppleShortcutRow(
                                name: shortcut,
                                isSelected: preferences.isShortcutSelected(shortcut),
                                onToggle: {
                                    preferences.toggleShortcutSelection(shortcut)
                                    StatusBarController.shared.updateMenu()
                                }
                            )
                            .padding(.leading, 24)
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
    }

    private var selectedInFolder: Int {
        folder.shortcuts.filter { preferences.isShortcutSelected($0) }.count
    }

    private func selectAllInFolder() {
        // If selectedShortcutNames is nil (all selected), we don't need to do anything
        guard preferences.selectedShortcutNames != nil else { return }

        for shortcut in folder.shortcuts {
            if !preferences.isShortcutSelected(shortcut) {
                preferences.toggleShortcutSelection(shortcut)
            }
        }
        StatusBarController.shared.updateMenu()
    }

    private func deselectAllInFolder() {
        // If selectedShortcutNames is nil, we need to initialize it first with all shortcuts
        // then remove the ones in this folder
        if preferences.selectedShortcutNames == nil {
            // Start with all shortcuts selected, then deselect this folder
            let allShortcuts = AppleShortcutsManager.shared.allShortcuts
            let shortcutsNotInFolder = Set(allShortcuts).subtracting(Set(folder.shortcuts))
            preferences.selectedShortcutNames = shortcutsNotInFolder
        } else {
            for shortcut in folder.shortcuts {
                if preferences.isShortcutSelected(shortcut) {
                    preferences.toggleShortcutSelection(shortcut)
                }
            }
        }
        StatusBarController.shared.updateMenu()
    }
}

/// Row for a single Apple Shortcut
struct AppleShortcutRow: View {
    let name: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Image(systemName: "bolt.fill")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                Text(name)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#else

struct ShortcutsSelectionView: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        Text("Shortcuts not available")
    }
}

#endif
