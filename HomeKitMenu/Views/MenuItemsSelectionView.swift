import SwiftUI

/// View for selecting which sensors and scenes appear in the menu bar
struct MenuItemsSelectionView: View {
    let homeKitManager: HomeKitManager
    @Bindable var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    private var sensorsWithReadings: [HomeAccessory] {
        homeKitManager.accessories.filter { !$0.sensorReadings.isEmpty }
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
                // Sensors section
                if !sensorsWithReadings.isEmpty {
                    Section {
                        ForEach(sensorsWithReadings) { sensor in
                            let isSelected = preferences.isSensorSelected(sensor)
                            Button {
                                preferences.toggleSensorSelection(sensor)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .secondary)

                                    Image(systemName: sensor.sensorReadings.first?.icon ?? "sensor.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading) {
                                        Text(sensor.name)
                                        Text(sensor.sensorReadings.map { $0.displayString }.joined(separator: " | "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Sensors")
                            Spacer()
                            Menu {
                                Button("Select All") {
                                    preferences.selectAllSensors(sensorsWithReadings)
                                }
                                Button("Select None") {
                                    preferences.deselectAllSensors()
                                }
                            } label: {
                                Text("Edit")
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Scenes section
                if !scenes.isEmpty {
                    Section {
                        ForEach(scenes, id: \.self) { sceneName in
                            let isSelected = preferences.isSceneSelected(sceneName)
                            Button {
                                preferences.toggleSceneSelection(sceneName)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .secondary)

                                    Image(systemName: "theatermasks.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    Text(sceneName)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Scenes")
                            Spacer()
                            Menu {
                                Button("Select All") {
                                    preferences.selectAllScenes()
                                }
                                Button("Select None") {
                                    preferences.deselectAllScenes()
                                }
                            } label: {
                                Text("Edit")
                                    .font(.caption)
                            }
                        }
                    }
                }

                if sensorsWithReadings.isEmpty && scenes.isEmpty {
                    Section {
                        Text("No sensors or scenes available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Menu Items")
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
