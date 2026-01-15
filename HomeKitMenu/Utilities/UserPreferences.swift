import Foundation
import SwiftUI
import ServiceManagement

/// Manages user preferences for which accessories to show in the menu bar
@Observable
final class UserPreferences {
    private let selectedAccessoriesKey = "selectedAccessories"
    private let launchAtLoginKey = "launchAtLogin"
    private let showOnlyOnKey = "showOnlyOn"
    private let customIconsKey = "customIcons"
    private let pinnedSensorsKey = "pinnedSensors"
    private let showSensorsInMenuKey = "showSensorsInMenu"
    private let showScenesInMenuKey = "showScenesInMenu"
    private let groupByRoomKey = "groupByRoom"
    private let selectedSensorsKey = "selectedSensors"
    private let selectedScenesKey = "selectedScenes"
    private let sortByOnStateKey = "sortByOnState"
    private let showAppleShortcutsKey = "showAppleShortcuts"
    private let appleShortcutFoldersKey = "appleShortcutFolders"
    private let appleShortcutsKey = "appleShortcuts"
    private let expandedFoldersKey = "expandedFolders"

    /// UUIDs of accessories selected to appear in the menu bar
    var selectedAccessoryIDs: Set<UUID> {
        didSet {
            saveSelectedAccessories()
        }
    }

    /// Whether to show only accessories that are currently on
    var showOnlyOn: Bool {
        didSet {
            UserDefaults.standard.set(showOnlyOn, forKey: showOnlyOnKey)
        }
    }

    /// Custom icons for accessories (keyed by UUID string)
    var customIcons: [String: String] {
        didSet {
            saveCustomIcons()
        }
    }

    /// UUIDs of sensors pinned to show in menu bar title
    var pinnedSensorIDs: Set<UUID> {
        didSet {
            savePinnedSensors()
        }
    }

    /// Whether to show sensors section in menu bar dropdown
    var showSensorsInMenu: Bool {
        didSet {
            UserDefaults.standard.set(showSensorsInMenu, forKey: showSensorsInMenuKey)
        }
    }

    /// Whether to show scenes section in menu bar dropdown
    var showScenesInMenu: Bool {
        didSet {
            UserDefaults.standard.set(showScenesInMenu, forKey: showScenesInMenuKey)
        }
    }

    /// Whether to group devices by room in menu bar dropdown
    var groupByRoom: Bool {
        didSet {
            UserDefaults.standard.set(groupByRoom, forKey: groupByRoomKey)
        }
    }

    /// Whether to sort devices by on/off state (on first) vs alphabetically
    var sortByOnState: Bool {
        didSet {
            UserDefaults.standard.set(sortByOnState, forKey: sortByOnStateKey)
        }
    }

    /// Whether to show Apple Shortcuts section in menu bar dropdown
    var showAppleShortcuts: Bool {
        didSet {
            UserDefaults.standard.set(showAppleShortcuts, forKey: showAppleShortcutsKey)
        }
    }

    /// Folder names for organizing shortcuts
    var shortcutFolders: Set<String> {
        didSet {
            saveShortcutFolders()
        }
    }

    /// Selected shortcut names to show in menu (nil = show all)
    var selectedShortcutNames: Set<String>? {
        didSet {
            saveSelectedShortcuts()
        }
    }

    /// Folders that are expanded (visible) in the menu
    var expandedFolders: Set<String> {
        didSet {
            saveExpandedFolders()
        }
    }

    /// Whether to launch the app at login
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
            updateLaunchAtLogin()
        }
    }

    /// UUIDs of sensors selected to show in menu (nil = show all)
    var selectedSensorIDs: Set<UUID>? {
        didSet {
            saveSelectedSensors()
        }
    }

    /// Names of scenes selected to show in menu (nil = show all)
    var selectedSceneNames: Set<String>? {
        didSet {
            saveSelectedScenes()
        }
    }

    init() {
        // Load show only on preference
        showOnlyOn = UserDefaults.standard.bool(forKey: showOnlyOnKey)

        // Load visibility preferences (default to true)
        showSensorsInMenu = UserDefaults.standard.object(forKey: showSensorsInMenuKey) as? Bool ?? true
        showScenesInMenu = UserDefaults.standard.object(forKey: showScenesInMenuKey) as? Bool ?? true
        groupByRoom = UserDefaults.standard.object(forKey: groupByRoomKey) as? Bool ?? true
        sortByOnState = UserDefaults.standard.object(forKey: sortByOnStateKey) as? Bool ?? false
        showAppleShortcuts = UserDefaults.standard.object(forKey: showAppleShortcutsKey) as? Bool ?? false
        launchAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)

        // Load selected accessories
        if let data = UserDefaults.standard.data(forKey: selectedAccessoriesKey),
           let uuids = try? JSONDecoder().decode([UUID].self, from: data) {
            selectedAccessoryIDs = Set(uuids)
        } else {
            selectedAccessoryIDs = []
        }

        // Load custom icons
        if let data = UserDefaults.standard.data(forKey: customIconsKey),
           let icons = try? JSONDecoder().decode([String: String].self, from: data) {
            customIcons = icons
        } else {
            customIcons = [:]
        }

        // Load pinned sensors
        if let data = UserDefaults.standard.data(forKey: pinnedSensorsKey),
           let uuids = try? JSONDecoder().decode([UUID].self, from: data) {
            pinnedSensorIDs = Set(uuids)
        } else {
            pinnedSensorIDs = []
        }

        // Load selected sensors (nil = show all)
        if let data = UserDefaults.standard.data(forKey: selectedSensorsKey),
           let uuids = try? JSONDecoder().decode([UUID].self, from: data) {
            selectedSensorIDs = Set(uuids)
        } else {
            selectedSensorIDs = nil
        }

        // Load selected scenes (nil = show all)
        if let data = UserDefaults.standard.data(forKey: selectedScenesKey),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            selectedSceneNames = Set(names)
        } else {
            selectedSceneNames = nil
        }

        // Load shortcut folders
        if let data = UserDefaults.standard.data(forKey: appleShortcutFoldersKey),
           let folders = try? JSONDecoder().decode([String].self, from: data) {
            shortcutFolders = Set(folders)
        } else {
            shortcutFolders = []
        }

        // Load selected shortcuts (nil = show all)
        if let data = UserDefaults.standard.data(forKey: appleShortcutsKey),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            selectedShortcutNames = Set(names)
        } else {
            selectedShortcutNames = nil
        }

        // Load expanded folders
        if let data = UserDefaults.standard.data(forKey: expandedFoldersKey),
           let folders = try? JSONDecoder().decode([String].self, from: data) {
            expandedFolders = Set(folders)
        } else {
            expandedFolders = []
        }
    }

    func isSelected(_ accessory: HomeAccessory) -> Bool {
        selectedAccessoryIDs.contains(accessory.uniqueIdentifier)
    }

    func toggleSelection(_ accessory: HomeAccessory) {
        if selectedAccessoryIDs.contains(accessory.uniqueIdentifier) {
            selectedAccessoryIDs.remove(accessory.uniqueIdentifier)
        } else {
            selectedAccessoryIDs.insert(accessory.uniqueIdentifier)
        }
    }

    func selectAll(_ accessories: [HomeAccessory]) {
        selectedAccessoryIDs = Set(accessories.map { $0.uniqueIdentifier })
    }

    func deselectAll() {
        selectedAccessoryIDs = []
    }

    func customIcon(for accessory: HomeAccessory) -> String? {
        customIcons[accessory.uniqueIdentifier.uuidString]
    }

    func setCustomIcon(_ icon: String?, for accessory: HomeAccessory) {
        if let icon {
            customIcons[accessory.uniqueIdentifier.uuidString] = icon
        } else {
            customIcons.removeValue(forKey: accessory.uniqueIdentifier.uuidString)
        }
    }

    private func saveSelectedAccessories() {
        if let data = try? JSONEncoder().encode(Array(selectedAccessoryIDs)) {
            UserDefaults.standard.set(data, forKey: selectedAccessoriesKey)
        }
    }

    private func saveCustomIcons() {
        if let data = try? JSONEncoder().encode(customIcons) {
            UserDefaults.standard.set(data, forKey: customIconsKey)
        }
    }

    // MARK: - Pinned Sensors

    func isPinned(_ accessory: HomeAccessory) -> Bool {
        pinnedSensorIDs.contains(accessory.uniqueIdentifier)
    }

    func togglePinned(_ accessory: HomeAccessory) {
        if pinnedSensorIDs.contains(accessory.uniqueIdentifier) {
            pinnedSensorIDs.remove(accessory.uniqueIdentifier)
        } else {
            pinnedSensorIDs.insert(accessory.uniqueIdentifier)
        }
    }

    private func savePinnedSensors() {
        if let data = try? JSONEncoder().encode(Array(pinnedSensorIDs)) {
            UserDefaults.standard.set(data, forKey: pinnedSensorsKey)
        }
    }

    // MARK: - Sensor Selection

    func isSensorSelected(_ accessory: HomeAccessory) -> Bool {
        guard let selected = selectedSensorIDs else { return true } // nil means show all
        return selected.contains(accessory.uniqueIdentifier)
    }

    func toggleSensorSelection(_ accessory: HomeAccessory) {
        if selectedSensorIDs == nil {
            selectedSensorIDs = Set([accessory.uniqueIdentifier])
        } else if selectedSensorIDs!.contains(accessory.uniqueIdentifier) {
            selectedSensorIDs!.remove(accessory.uniqueIdentifier)
        } else {
            selectedSensorIDs!.insert(accessory.uniqueIdentifier)
        }
    }

    func selectAllSensors(_ accessories: [HomeAccessory]) {
        selectedSensorIDs = nil // nil means show all
    }

    func deselectAllSensors() {
        selectedSensorIDs = Set()
    }

    private func saveSelectedSensors() {
        if let ids = selectedSensorIDs {
            if let data = try? JSONEncoder().encode(Array(ids)) {
                UserDefaults.standard.set(data, forKey: selectedSensorsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: selectedSensorsKey)
        }
    }

    // MARK: - Scene Selection

    func isSceneSelected(_ sceneName: String) -> Bool {
        guard let selected = selectedSceneNames else { return true } // nil means show all
        return selected.contains(sceneName)
    }

    func toggleSceneSelection(_ sceneName: String) {
        if selectedSceneNames == nil {
            selectedSceneNames = Set([sceneName])
        } else if selectedSceneNames!.contains(sceneName) {
            selectedSceneNames!.remove(sceneName)
        } else {
            selectedSceneNames!.insert(sceneName)
        }
    }

    func selectAllScenes() {
        selectedSceneNames = nil // nil means show all
    }

    func deselectAllScenes() {
        selectedSceneNames = Set()
    }

    private func saveSelectedScenes() {
        if let names = selectedSceneNames {
            if let data = try? JSONEncoder().encode(Array(names)) {
                UserDefaults.standard.set(data, forKey: selectedScenesKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: selectedScenesKey)
        }
    }

    // MARK: - Apple Shortcuts

    func isShortcutSelected(_ name: String) -> Bool {
        guard let selected = selectedShortcutNames else { return true } // nil means show all
        return selected.contains(name)
    }

    func toggleShortcutSelection(_ name: String) {
        if selectedShortcutNames == nil {
            // First time selecting - start with just this one
            selectedShortcutNames = Set([name])
        } else if selectedShortcutNames!.contains(name) {
            selectedShortcutNames!.remove(name)
        } else {
            selectedShortcutNames!.insert(name)
        }
    }

    func selectAllShortcuts() {
        selectedShortcutNames = nil // nil means show all
    }

    func deselectAllShortcuts() {
        selectedShortcutNames = Set()
    }

    func isFolderExpanded(_ folder: String) -> Bool {
        expandedFolders.contains(folder)
    }

    func toggleFolderExpanded(_ folder: String) {
        if expandedFolders.contains(folder) {
            expandedFolders.remove(folder)
        } else {
            expandedFolders.insert(folder)
        }
    }

    private func saveShortcutFolders() {
        if let data = try? JSONEncoder().encode(Array(shortcutFolders)) {
            UserDefaults.standard.set(data, forKey: appleShortcutFoldersKey)
        }
    }

    private func saveSelectedShortcuts() {
        if let names = selectedShortcutNames {
            if let data = try? JSONEncoder().encode(Array(names)) {
                UserDefaults.standard.set(data, forKey: appleShortcutsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: appleShortcutsKey)
        }
    }

    private func saveExpandedFolders() {
        if let data = try? JSONEncoder().encode(Array(expandedFolders)) {
            UserDefaults.standard.set(data, forKey: expandedFoldersKey)
        }
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
