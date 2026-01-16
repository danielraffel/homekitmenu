import Foundation
import Combine

#if targetEnvironment(macCatalyst)
import UIKit
import ObjectiveC

/// Controls the macOS status bar menu item using AppKit via dynamic loading
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: AnyObject?
    private var statusBarMenu: AnyObject?
    private weak var homeKitManager: HomeKitManager?
    private weak var preferences: UserPreferences?
    private var refreshTimer: Timer?
    private var menuActions: [Int: () -> Void] = [:]
    private var nextTag = 1

    static let shared = StatusBarController()

    private override init() {
        super.init()
    }

    func setup(homeKitManager: HomeKitManager, preferences: UserPreferences) {
        self.homeKitManager = homeKitManager
        self.preferences = preferences

        createStatusItem()
        updateMenu()

        // Set up periodic refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenu()
            }
        }

        // Observe accessory updates for immediate menu refresh
        NotificationCenter.default.addObserver(
            forName: .homeKitAccessoriesDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenu()
            }
        }
    }

    private func createStatusItem() {
        // Load AppKit framework
        guard let appKitBundle = Bundle(path: "/System/Library/Frameworks/AppKit.framework"),
              appKitBundle.load() else {
            print("Failed to load AppKit")
            return
        }

        // Get NSStatusBar class and system status bar
        guard let statusBarClass = NSClassFromString("NSStatusBar") else {
            print("Failed to get NSStatusBar class")
            return
        }

        let systemStatusBarSelector = NSSelectorFromString("systemStatusBar")
        guard statusBarClass.responds(to: systemStatusBarSelector),
              let systemStatusBar = (statusBarClass as AnyObject).perform(systemStatusBarSelector)?.takeUnretainedValue() else {
            print("Failed to get system status bar")
            return
        }

        // Create status item with variable length (-1)
        let statusItemSelector = NSSelectorFromString("statusItemWithLength:")
        let variableLength: CGFloat = -1

        let inv = (systemStatusBar as AnyObject).method(for: statusItemSelector)
        typealias StatusItemFunc = @convention(c) (AnyObject, Selector, CGFloat) -> AnyObject?
        let statusItemFunc = unsafeBitCast(inv, to: StatusItemFunc.self)

        guard let item = statusItemFunc(systemStatusBar as AnyObject, statusItemSelector, variableLength) else {
            print("Failed to create status item")
            return
        }
        statusItem = item

        // Set up the button with house icon
        let buttonSelector = NSSelectorFromString("button")
        if let button = (item as AnyObject).perform(buttonSelector)?.takeUnretainedValue() {
            setImage(on: button, symbolName: "house.fill")
        }

        // Create menu
        if let menuClass = NSClassFromString("NSMenu") {
            let menu = (menuClass as AnyObject).perform(NSSelectorFromString("new"))?.takeUnretainedValue()
            statusBarMenu = menu

            // Set delegate to self for menu validation
            _ = (menu as AnyObject?)?.perform(NSSelectorFromString("setDelegate:"), with: self)

            let setMenuSelector = NSSelectorFromString("setMenu:")
            _ = (item as AnyObject).perform(setMenuSelector, with: menu)
        }
    }

    private func setImage(on target: AnyObject, symbolName: String) {
        guard let imageClass = NSClassFromString("NSImage") else { return }

        let imageSelector = NSSelectorFromString("imageWithSystemSymbolName:accessibilityDescription:")
        if imageClass.responds(to: imageSelector) {
            let inv = (imageClass as AnyObject).method(for: imageSelector)
            typealias ImageFunc = @convention(c) (AnyObject, Selector, NSString, NSString?) -> AnyObject?
            let imageFunc = unsafeBitCast(inv, to: ImageFunc.self)

            if let image = imageFunc(imageClass as AnyObject, imageSelector, symbolName as NSString, nil) {
                _ = target.perform(NSSelectorFromString("setImage:"), with: image)
            }
        }
    }

    /// Creates a circular badge image with icon inside (like Bluetooth menu)
    /// - isOn: true = blue circle with white icon, false = gray circle with dark icon
    private func createBadgeImage(symbolName: String, isOn: Bool) -> AnyObject? {
        guard let imageClass = NSClassFromString("NSImage"),
              let colorClass = NSClassFromString("NSColor"),
              let bezierPathClass = NSClassFromString("NSBezierPath") else { return nil }

        // Get the symbol image first
        let imageSelector = NSSelectorFromString("imageWithSystemSymbolName:accessibilityDescription:")
        guard imageClass.responds(to: imageSelector) else { return nil }

        let inv = (imageClass as AnyObject).method(for: imageSelector)
        typealias ImageFunc = @convention(c) (AnyObject, Selector, NSString, NSString?) -> AnyObject?
        let imageFunc = unsafeBitCast(inv, to: ImageFunc.self)

        guard let symbolImage = imageFunc(imageClass as AnyObject, imageSelector, symbolName as NSString, nil) else { return nil }

        // Badge size
        let badgeSize: CGFloat = 20
        let iconSize: CGFloat = 12

        // Create the composite image
        let initSelector = NSSelectorFromString("initWithSize:")
        guard let newImage = (imageClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }

        let sizeInv = (newImage as AnyObject).method(for: initSelector)
        typealias InitSizeFunc = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject
        let initSizeFunc = unsafeBitCast(sizeInv, to: InitSizeFunc.self)
        let compositeImage = initSizeFunc(newImage as AnyObject, initSelector, CGSize(width: badgeSize, height: badgeSize))

        // Lock focus to draw
        _ = (compositeImage as AnyObject).perform(NSSelectorFromString("lockFocus"))

        // Get colors
        let circleColor: AnyObject?
        let iconColor: AnyObject?

        if isOn {
            // Blue circle, white icon
            circleColor = (colorClass as AnyObject).perform(NSSelectorFromString("systemBlueColor"))?.takeUnretainedValue()
            iconColor = (colorClass as AnyObject).perform(NSSelectorFromString("whiteColor"))?.takeUnretainedValue()
        } else {
            // Subtle gray circle, medium gray icon (matches macOS menu bar style)
            let graySelector = NSSelectorFromString("colorWithWhite:alpha:")
            let grayInv = (colorClass as AnyObject).method(for: graySelector)
            typealias GrayColorFunc = @convention(c) (AnyObject, Selector, CGFloat, CGFloat) -> AnyObject?
            let grayColorFunc = unsafeBitCast(grayInv, to: GrayColorFunc.self)
            // Lighter circle background for subtle appearance
            circleColor = grayColorFunc(colorClass as AnyObject, graySelector, 0.68, 1.0)

            // Medium gray icon for good contrast without being too dark
            let darkGrayColor = grayColorFunc(colorClass as AnyObject, graySelector, 0.35, 1.0)
            iconColor = darkGrayColor
        }

        // Draw circle background
        if let color = circleColor {
            _ = (color as AnyObject).perform(NSSelectorFromString("setFill"))

            let ovalSelector = NSSelectorFromString("bezierPathWithOvalInRect:")
            let ovalInv = (bezierPathClass as AnyObject).method(for: ovalSelector)
            typealias OvalFunc = @convention(c) (AnyObject, Selector, CGRect) -> AnyObject?
            let ovalFunc = unsafeBitCast(ovalInv, to: OvalFunc.self)

            let circleRect = CGRect(x: 0, y: 0, width: badgeSize, height: badgeSize)
            if let path = ovalFunc(bezierPathClass as AnyObject, ovalSelector, circleRect) {
                _ = (path as AnyObject).perform(NSSelectorFromString("fill"))
            }
        }

        // Tint and draw the icon centered
        if let tintColor = iconColor {
            // Create tinted copy of symbol
            let tintSelector = NSSelectorFromString("imageWithSymbolConfiguration:")

            if let configClass = NSClassFromString("NSImageSymbolConfiguration") as? NSObject.Type {
                // Create configuration with color
                let configSelector = NSSelectorFromString("configurationWithHierarchicalColor:")
                if configClass.responds(to: configSelector) {
                    let configInv = (configClass as AnyObject).method(for: configSelector)
                    typealias ConfigFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
                    let configFunc = unsafeBitCast(configInv, to: ConfigFunc.self)

                    if let config = configFunc(configClass as AnyObject, configSelector, tintColor) {
                        // Apply configuration to image
                        if (symbolImage as AnyObject).responds(to: tintSelector) {
                            let tintInv = (symbolImage as AnyObject).method(for: tintSelector)
                            typealias TintFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
                            let tintFunc = unsafeBitCast(tintInv, to: TintFunc.self)

                            if let tintedImage = tintFunc(symbolImage as AnyObject, tintSelector, config) {
                                // Draw tinted image centered
                                let iconX = (badgeSize - iconSize) / 2
                                let iconY = (badgeSize - iconSize) / 2
                                let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

                                let drawSelector = NSSelectorFromString("drawInRect:fromRect:operation:fraction:")
                                let drawInv = (tintedImage as AnyObject).method(for: drawSelector)
                                typealias DrawFunc = @convention(c) (AnyObject, Selector, CGRect, CGRect, Int, CGFloat) -> Void
                                let drawFunc = unsafeBitCast(drawInv, to: DrawFunc.self)
                                drawFunc(tintedImage as AnyObject, drawSelector, iconRect, CGRect.zero, 2, 1.0) // 2 = NSCompositingOperationSourceOver
                            }
                        }
                    }
                }
            }
        }

        // Unlock focus
        _ = (compositeImage as AnyObject).perform(NSSelectorFromString("unlockFocus"))

        return compositeImage
    }

    private func updateStatusBarTitle() {
        guard let item = statusItem,
              let homeKitManager = homeKitManager,
              let preferences = preferences else { return }

        // Get pinned sensors
        let pinnedSensors = homeKitManager.accessories.filter {
            preferences.isPinned($0) && !$0.sensorReadings.isEmpty
        }

        // Get the button
        let buttonSelector = NSSelectorFromString("button")
        guard let button = (item as AnyObject).perform(buttonSelector)?.takeUnretainedValue() else { return }

        if pinnedSensors.isEmpty {
            // Just show the house icon
            _ = (button as AnyObject).perform(NSSelectorFromString("setTitle:"), with: "" as NSString)
        } else {
            // Show sensor values next to the icon
            var titleParts: [String] = []
            for sensor in pinnedSensors.prefix(3) { // Limit to 3 to avoid too long title
                for reading in sensor.sensorReadings.prefix(2) {
                    titleParts.append(reading.displayString)
                }
            }
            let title = " " + titleParts.joined(separator: " | ")
            _ = (button as AnyObject).perform(NSSelectorFromString("setTitle:"), with: title as NSString)
        }
    }

    func updateMenu() {
        guard let menu = statusBarMenu,
              let homeKitManager = homeKitManager,
              let preferences = preferences else {
            return
        }

        // Clear actions
        menuActions.removeAll()
        nextTag = 1

        // Remove all items
        _ = (menu as AnyObject).perform(NSSelectorFromString("removeAllItems"))

        // Update status bar title with pinned sensors
        updateStatusBarTitle()

        // Get selected accessories
        let selectedAccessories = homeKitManager.accessories.filter {
            preferences.isSelected($0)
        }

        // Add sensors section at top if enabled and any accessories have sensor readings
        if preferences.showSensorsInMenu {
            let allSensors = homeKitManager.accessories.filter { !$0.sensorReadings.isEmpty }
            let sensorsWithReadings = allSensors.filter { preferences.isSensorSelected($0) }
            if !sensorsWithReadings.isEmpty {
                addMenuItem(to: menu, title: "Sensors", enabled: false, iconName: nil, action: nil)

                for sensor in sensorsWithReadings {
                    let isPinned = preferences.isPinned(sensor)
                    let readingText = sensor.sensorReadings.map { $0.displayString }.joined(separator: " | ")
                    let pinIndicator = isPinned ? "📌 " : ""
                    let title = "\(pinIndicator)\(sensor.name): \(readingText)"

                    addMenuItem(
                        to: menu,
                        title: title,
                        enabled: true,
                        iconName: sensor.sensorReadings.first?.icon ?? "sensor.fill"
                    ) { [weak self, weak preferences] in
                        preferences?.togglePinned(sensor)
                        self?.updateMenu()
                    }
                }

                addSeparator(to: menu)
            }
        }

        if selectedAccessories.isEmpty {
            addMenuItem(to: menu, title: "No devices selected", enabled: false, iconName: nil, keyEquivalent: "", action: nil)
        } else if preferences.groupByRoom {
            // Group by room
            let grouped = Dictionary(grouping: selectedAccessories) { $0.roomName ?? "No Room" }
            let sortedRooms = grouped.keys.sorted()

            for roomName in sortedRooms {
                guard let roomAccessories = grouped[roomName] else { continue }

                // Add room header
                addMenuItem(to: menu, title: roomName, enabled: false, iconName: nil, action: nil)

                // Sort by preference
                let sorted: [HomeAccessory]
                if preferences.sortByOnState {
                    sorted = roomAccessories.sorted { a, b in
                        if a.isOn != b.isOn { return a.isOn }
                        return a.name < b.name
                    }
                } else {
                    sorted = roomAccessories.sorted { $0.name < $1.name }
                }

                for accessory in sorted {
                    addAccessoryMenuItem(to: menu, accessory: accessory, preferences: preferences, homeKitManager: homeKitManager)
                }

                addSeparator(to: menu)
            }
        } else {
            // Flat list - sort by preference
            let sorted: [HomeAccessory]
            if preferences.sortByOnState {
                sorted = selectedAccessories.sorted { a, b in
                    if a.isOn != b.isOn { return a.isOn }
                    return a.name < b.name
                }
            } else {
                sorted = selectedAccessories.sorted { $0.name < $1.name }
            }

            for accessory in sorted {
                addAccessoryMenuItem(to: menu, accessory: accessory, preferences: preferences, homeKitManager: homeKitManager)
            }
        }

        // Add scenes section if available and enabled
        if preferences.showScenesInMenu, let home = homeKitManager.currentHome, !home.actionSets.isEmpty {
            // Get favorite/non-built-in scenes and filter by selection
            let allScenes = home.actionSets.filter { !$0.name.hasPrefix("com.apple") }
            let scenes = allScenes.filter { preferences.isSceneSelected($0.name) }

            if !scenes.isEmpty {
                addSeparator(to: menu)
                addMenuItem(to: menu, title: "Scenes", enabled: false, iconName: nil, action: nil)

                for scene in scenes {
                    let shortcut = KeyboardShortcutManager.shared.shortcut(for: scene.name)
                    let keyEquiv = shortcut?.displayString ?? ""

                    addMenuItem(
                        to: menu,
                        title: scene.name,
                        enabled: true,
                        iconName: "theatermasks.fill",
                        keyEquivalent: keyEquiv
                    ) { [weak homeKitManager] in
                        guard let home = homeKitManager?.currentHome else { return }
                        home.executeActionSet(scene) { error in
                            if let error = error {
                                print("Failed to execute scene: \(error)")
                            }
                        }
                    }
                }
            }
        }

        // Add Apple Shortcuts section if enabled
        if preferences.showAppleShortcuts {
            let allShortcuts = AppleShortcutsManager.shared.allShortcuts
            let selectedShortcuts = allShortcuts.filter { preferences.isShortcutSelected($0) }

            if !selectedShortcuts.isEmpty {
                addSeparator(to: menu)
                addMenuItem(to: menu, title: "Shortcuts", enabled: false, iconName: nil, action: nil)

                for shortcutName in selectedShortcuts.sorted() {
                    addMenuItem(
                        to: menu,
                        title: shortcutName,
                        enabled: true,
                        iconName: "bolt.fill"
                    ) {
                        // Run the shortcut via URL scheme
                        let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName
                        if let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") {
                            #if targetEnvironment(macCatalyst)
                            UIApplication.shared.open(url)
                            #endif
                        }
                    }
                }
            }
        }

        // Add separator
        addSeparator(to: menu)

        // Add "Open App" item with Cmd+O shortcut
        addMenuItem(to: menu, title: "Open HomeBar Menu Bar...", enabled: true, iconName: nil, keyEquivalent: "o") {
            // First activate the app
            if let nsAppClass = NSClassFromString("NSApplication") as? NSObject.Type,
               let sharedApp = nsAppClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() {
                _ = (sharedApp as AnyObject).perform(NSSelectorFromString("activateIgnoringOtherApps:"), with: true as AnyObject)
            }

            // Try to show existing NSWindow
            var foundWindow = false
            if let nsAppClass = NSClassFromString("NSApplication") as? NSObject.Type,
               let sharedApp = nsAppClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() {
                if let windows = (sharedApp as AnyObject).value(forKey: "windows") as? [AnyObject], !windows.isEmpty {
                    for window in windows {
                        _ = (window as AnyObject).perform(NSSelectorFromString("makeKeyAndOrderFront:"), with: nil)
                        foundWindow = true
                    }
                }
            }

            // If no window found, create new scene
            if !foundWindow {
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
            }

            // Also try UIKit approach
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                window.isHidden = false
                window.makeKeyAndVisible()
            }
        }

        // Add Quit item
        addMenuItem(to: menu, title: "Quit", enabled: true, iconName: nil) {
            exit(0)
        }
    }

    private func addMenuItem(to menu: AnyObject, title: String, enabled: Bool, iconName: String?, keyEquivalent: String = "", isOn: Bool = false, useBadgeStyle: Bool = false, action: (() -> Void)?) {
        guard let menuItemClass = NSClassFromString("NSMenuItem") else { return }

        // Create menu item using alloc/init
        guard let item = (menuItemClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return }

        let initSelector = NSSelectorFromString("initWithTitle:action:keyEquivalent:")
        let inv = (item as AnyObject).method(for: initSelector)
        typealias InitFunc = @convention(c) (AnyObject, Selector, NSString, Selector?, NSString) -> AnyObject
        let initFunc = unsafeBitCast(inv, to: InitFunc.self)

        // Set action selector if we have an action
        let actionSel: Selector? = action != nil ? NSSelectorFromString("menuItemClicked:") : nil
        let initializedItem = initFunc(item as AnyObject, initSelector, title as NSString, actionSel, keyEquivalent as NSString)

        // Set target to self if we have an action
        if action != nil {
            _ = (initializedItem as AnyObject).perform(NSSelectorFromString("setTarget:"), with: self)

            // Set tag and store action
            let tag = nextTag
            nextTag += 1
            setTag(on: initializedItem, tag: tag)
            menuActions[tag] = action
        }

        // Set enabled state
        setEnabled(on: initializedItem, enabled: enabled)

        // Set icon if provided
        if let iconName = iconName {
            if useBadgeStyle {
                // Use circular badge style (like Bluetooth menu)
                if let badgeImage = createBadgeImage(symbolName: iconName, isOn: isOn) {
                    _ = (initializedItem as AnyObject).perform(NSSelectorFromString("setImage:"), with: badgeImage)
                }
            } else {
                // Use regular SF Symbol
                setImage(on: initializedItem as AnyObject, symbolName: iconName)
            }
        }

        // Add to menu
        _ = (menu as AnyObject).perform(NSSelectorFromString("addItem:"), with: initializedItem)
    }

    private func setTag(on item: AnyObject, tag: Int) {
        let selector = NSSelectorFromString("setTag:")
        let inv = (item as AnyObject).method(for: selector)
        typealias SetTagFunc = @convention(c) (AnyObject, Selector, Int) -> Void
        let setTagFunc = unsafeBitCast(inv, to: SetTagFunc.self)
        setTagFunc(item as AnyObject, selector, tag)
    }

    private func setEnabled(on item: AnyObject, enabled: Bool) {
        let selector = NSSelectorFromString("setEnabled:")
        let inv = (item as AnyObject).method(for: selector)
        typealias SetEnabledFunc = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setEnabledFunc = unsafeBitCast(inv, to: SetEnabledFunc.self)
        setEnabledFunc(item as AnyObject, selector, enabled)
    }

    private func addSeparator(to menu: AnyObject) {
        guard let menuItemClass = NSClassFromString("NSMenuItem") else { return }

        let separatorSelector = NSSelectorFromString("separatorItem")
        if let separator = (menuItemClass as AnyObject).perform(separatorSelector)?.takeUnretainedValue() {
            _ = (menu as AnyObject).perform(NSSelectorFromString("addItem:"), with: separator)
        }
    }

    private func addAccessoryMenuItem(to menu: AnyObject, accessory: HomeAccessory, preferences: UserPreferences, homeKitManager: HomeKitManager) {
        let iconName = preferences.customIcon(for: accessory) ?? accessory.effectiveIcon

        // Get keyboard shortcut if assigned
        let shortcut = KeyboardShortcutManager.shared.shortcut(for: accessory.uniqueIdentifier.uuidString)
        let keyEquiv = shortcut?.displayString ?? ""

        addMenuItem(
            to: menu,
            title: accessory.name,
            enabled: true,
            iconName: iconName,
            keyEquivalent: keyEquiv,
            isOn: accessory.isOn,
            useBadgeStyle: true
        ) { [weak self, weak homeKitManager] in
            guard let homeKitManager = homeKitManager else { return }
            Task {
                await homeKitManager.toggleAccessory(accessory)
                await MainActor.run {
                    self?.updateMenu()
                }
            }
        }
    }

    // MARK: - Menu Action Handler

    @objc func menuItemClicked(_ sender: AnyObject) {
        // Get tag from sender
        let tagSelector = NSSelectorFromString("tag")
        let inv = (sender as AnyObject).method(for: tagSelector)
        typealias TagFunc = @convention(c) (AnyObject, Selector) -> Int
        let tagFunc = unsafeBitCast(inv, to: TagFunc.self)
        let tag = tagFunc(sender as AnyObject, tagSelector)

        // Execute stored action
        if let action = menuActions[tag] {
            action()
        }
    }

    // MARK: - Menu Validation (NSMenuDelegate)

    @objc func validateMenuItem(_ menuItem: AnyObject) -> Bool {
        // Always return true to enable items
        return true
    }
}

#else

// Stub for non-Catalyst builds
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()
    private override init() { super.init() }
    func setup(homeKitManager: HomeKitManager, preferences: UserPreferences) {}
    func updateMenu() {}
}

#endif
