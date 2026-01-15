import SwiftUI

/// Settings view with display options, license, privacy, and third-party software info
struct SettingsView: View {
    @Bindable var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    private let baseURL = "https://www.generouscorp.com/homekitmenu-releases/"

    var body: some View {
        NavigationStack {
            List {
                Section("Display Options") {
                    Toggle("Group by room in menu", isOn: $preferences.groupByRoom)
                    Toggle("Sort \"on\" devices first", isOn: $preferences.sortByOnState)
                    Toggle("Show sensors in menu", isOn: $preferences.showSensorsInMenu)
                    Toggle("Show scenes in menu", isOn: $preferences.showScenesInMenu)
                    Toggle("Show Apple Shortcuts in menu", isOn: $preferences.showAppleShortcuts)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Developer")
                        Spacer()
                        Text("Generous Corp")
                            .foregroundStyle(.secondary)
                    }

                    #if targetEnvironment(macCatalyst)
                    Button {
                        SparkleUpdateManager.shared.checkForUpdates()
                    } label: {
                        HStack {
                            Text("Check for Updates")
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    #endif
                }

                Section("Legal") {
                    Link(destination: URL(string: "\(baseURL)license.html")!) {
                        HStack {
                            Text("License")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "\(baseURL)privacy.html")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "\(baseURL)terms.html")!) {
                        HStack {
                            Text("Terms of Use")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sparkle")
                            .font(.headline)
                        Text("Update framework for macOS applications")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("github.com/sparkle-project/Sparkle", destination: URL(string: "https://github.com/sparkle-project/Sparkle")!)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Third-Party Software")
                }

                Section {
                    Text("HomeKit is a registered trademark of Apple Inc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
