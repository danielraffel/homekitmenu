import SwiftUI

/// The preferences view for selecting which accessories appear in the app
struct PreferencesView: View {
    let homeKitManager: HomeKitManager
    let preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var filterType: HomeAccessory.AccessoryType?

    private var filteredAccessories: [HomeAccessory] {
        var result = homeKitManager.accessories

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.roomName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if let filterType {
            result = result.filter { $0.type == filterType }
        }

        return result
    }

    private var groupedAccessories: [(String, [HomeAccessory])] {
        let grouped = Dictionary(grouping: filteredAccessories) { $0.roomName ?? "No Room" }
        return grouped.sorted { $0.key < $1.key }
    }

    private var selectedCount: Int {
        preferences.selectedAccessoryIDs.count
    }

    private func isRoomFullySelected(_ accessories: [HomeAccessory]) -> Bool {
        accessories.allSatisfy { preferences.isSelected($0) }
    }

    private func toggleRoom(_ accessories: [HomeAccessory]) {
        if isRoomFullySelected(accessories) {
            // Deselect all in room
            for accessory in accessories {
                if preferences.isSelected(accessory) {
                    preferences.toggleSelection(accessory)
                }
            }
        } else {
            // Select all in room
            for accessory in accessories {
                if !preferences.isSelected(accessory) {
                    preferences.toggleSelection(accessory)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if homeKitManager.accessories.isEmpty {
                    ContentUnavailableView {
                        Label("No Devices", systemImage: "house.circle")
                    } description: {
                        Text("No HomeKit accessories found")
                        Text("Make sure you have HomeKit accessories set up in the Home app.")
                    } actions: {
                        Button("Refresh") {
                            homeKitManager.refreshAccessories()
                        }
                    }
                } else if filteredAccessories.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No matching devices found")
                    }
                } else {
                    VStack(spacing: 0) {
                        // Select All/None buttons at the top
                        HStack(spacing: 12) {
                            Button {
                                preferences.selectAll(homeKitManager.accessories)
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Select All")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                preferences.deselectAll()
                            } label: {
                                HStack {
                                    Image(systemName: "circle")
                                    Text("Select None")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemGroupedBackground))

                        List {
                            ForEach(groupedAccessories, id: \.0) { roomName, accessories in
                                Section {
                                    ForEach(accessories) { accessory in
                                        AccessorySelectionRow(
                                            accessory: accessory,
                                            isSelected: preferences.isSelected(accessory),
                                            customIcon: preferences.customIcon(for: accessory),
                                            onToggle: {
                                                preferences.toggleSelection(accessory)
                                            },
                                            onIconChange: { icon in
                                                preferences.setCustomIcon(icon, for: accessory)
                                            }
                                        )
                                    }
                                } header: {
                                    HStack {
                                        Text(roomName)
                                        Spacer()
                                        Button {
                                            toggleRoom(accessories)
                                        } label: {
                                            Text(isRoomFullySelected(accessories) ? "Deselect All" : "Select All")
                                                .font(.caption)
                                                .textCase(.none)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Devices")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search devices")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All Types") {
                            filterType = nil
                        }
                        Divider()
                        ForEach(HomeAccessory.AccessoryType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                            Button {
                                filterType = type
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(selectedCount)")
                                .font(.caption)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
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
        .frame(minWidth: 450, minHeight: 550)
        #endif
    }
}
