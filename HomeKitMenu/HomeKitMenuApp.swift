import SwiftUI
import HomeKit

@main
struct HomeKitMenuApp: App {
    @State private var homeKitManager = HomeKitManager()
    @State private var preferences = UserPreferences()
    @State private var statusBarSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                homeKitManager: homeKitManager,
                preferences: preferences
            )
            .task {
                // Setup status bar, keyboard shortcuts, and automations after a brief delay
                if !statusBarSetup {
                    statusBarSetup = true
                    try? await Task.sleep(for: .milliseconds(500))
                    StatusBarController.shared.setup(
                        homeKitManager: homeKitManager,
                        preferences: preferences
                    )
                    KeyboardShortcutManager.shared.setup(homeKitManager: homeKitManager)
                    AutomationManager.shared.setup(homeKitManager: homeKitManager)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                StatusBarController.shared.updateMenu()
            }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 400, height: 600)
        #endif
    }
}

/// Main content view that shows either menu bar dropdown or preferences
struct ContentView: View {
    let homeKitManager: HomeKitManager
    let preferences: UserPreferences
    @State private var showingPreferences = false
    @State private var showingShortcuts = false
    @State private var showingAutomations = false
    @State private var showingMenuItems = false
    @State private var showingAppleShortcuts = false

    var body: some View {
        NavigationStack {
            MenuBarContentView(
                homeKitManager: homeKitManager,
                preferences: preferences,
                showingPreferences: $showingPreferences
            )
            .navigationTitle("HomeBar Menu Bar")
            #if targetEnvironment(macCatalyst)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingPreferences = true
                        } label: {
                            Label("Select Devices", systemImage: "checklist")
                        }

                        Button {
                            showingMenuItems = true
                        } label: {
                            Label("Sensors & Scenes", systemImage: "list.bullet")
                        }

                        Divider()

                        Button {
                            showingShortcuts = true
                        } label: {
                            Label("Keyboard Shortcuts", systemImage: "keyboard")
                        }

                        Button {
                            showingAutomations = true
                        } label: {
                            Label("Automations", systemImage: "bolt.fill")
                        }

                        Button {
                            showingAppleShortcuts = true
                        } label: {
                            Label("Shortcuts", systemImage: "bolt.square.fill")
                        }
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(
                homeKitManager: homeKitManager,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showingShortcuts) {
            ShortcutsView(
                homeKitManager: homeKitManager,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showingAutomations) {
            AutomationsView(homeKitManager: homeKitManager)
        }
        .sheet(isPresented: $showingMenuItems) {
            MenuItemsSelectionView(
                homeKitManager: homeKitManager,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showingAppleShortcuts) {
            ShortcutsSelectionView(preferences: preferences)
        }
    }
}

/// The main content showing accessories
struct MenuBarContentView: View {
    let homeKitManager: HomeKitManager
    @Bindable var preferences: UserPreferences
    @Binding var showingPreferences: Bool
    @State private var showingSettings = false

    private var filteredAccessories: [HomeAccessory] {
        var result = homeKitManager.accessories.filter { preferences.isSelected($0) }
        if preferences.showOnlyOn {
            result = result.filter { $0.isOn }
        }
        return result
    }

    private var onCount: Int {
        filteredAccessories.filter { $0.isOn }.count
    }

    var body: some View {
        Group {
            if homeKitManager.isSyncing {
                // Syncing state - show loading indicator
                ContentUnavailableView {
                    Label("Connecting to HomeKit", systemImage: "house.circle")
                } description: {
                    Text(homeKitManager.authorizationStatus)
                    ProgressView()
                        .padding(.top, 8)
                }
            } else if !homeKitManager.isAuthorized {
                // Not authorized state - check if it's permission or sync issue
                let needsPermission = homeKitManager.authorizationStatus.contains("permission")
                ContentUnavailableView {
                    Label(needsPermission ? "No HomeKit Access" : "Connection Issue", systemImage: "house.circle")
                } description: {
                    Text(homeKitManager.authorizationStatus)
                    if needsPermission {
                        Text("Open System Settings to grant HomeKit access")
                    }
                } actions: {
                    if needsPermission {
                        Button("Open Privacy Settings") {
                            openPrivacySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Retry") {
                            homeKitManager.retryConnection()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if homeKitManager.accessories.isEmpty {
                // No accessories found
                ContentUnavailableView {
                    Label("No Devices", systemImage: "lightbulb.slash")
                } description: {
                    Text("No HomeKit devices found")
                } actions: {
                    Button("Refresh") {
                        homeKitManager.refreshAccessories()
                    }
                }
            } else if filteredAccessories.isEmpty {
                // No accessories selected or visible
                ContentUnavailableView {
                    Label(preferences.showOnlyOn ? "No Devices On" : "No Devices Selected",
                          systemImage: preferences.showOnlyOn ? "lightbulb.slash" : "checklist.unchecked")
                } description: {
                    Text(preferences.showOnlyOn ? "No devices are currently on" : "Tap the gear icon to select devices to show")
                } actions: {
                    if preferences.showOnlyOn {
                        Button("Show All") {
                            preferences.showOnlyOn = false
                        }
                    } else {
                        Button("Select Devices") {
                            showingPreferences = true
                        }
                    }
                }
            } else {
                // Accessories list
                List {
                    Section {
                        ForEach(filteredAccessories) { accessory in
                            AccessoryRow(
                                accessory: accessory,
                                customIcon: preferences.customIcon(for: accessory)
                            ) {
                                Task {
                                    await homeKitManager.toggleAccessory(accessory)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Devices")
                            Spacer()
                            if onCount > 0 {
                                Text("\(onCount) on")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Show selected shortcuts preview if enabled
                    if preferences.showAppleShortcuts {
                        let allShortcuts = AppleShortcutsManager.shared.allShortcuts
                        let selectedShortcuts = allShortcuts.filter { preferences.isShortcutSelected($0) }

                        Section {
                            if selectedShortcuts.isEmpty {
                                Text("No shortcuts selected")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(selectedShortcuts.sorted(), id: \.self) { shortcut in
                                    HStack(spacing: 12) {
                                        Image(systemName: "bolt.fill")
                                            .foregroundStyle(.orange)
                                        Text(shortcut)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Shortcuts in Menu")
                                Spacer()
                                Text("\(selectedShortcuts.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Button {
                            homeKitManager.refreshAccessories()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
            }
        }
        .onAppear {
            homeKitManager.refreshAccessories()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(preferences: preferences)
        }
    }

    private func openPrivacySettings() {
        #if targetEnvironment(macCatalyst)
        // Open System Settings to Privacy & Security > HomeKit
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_HomeKit") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
