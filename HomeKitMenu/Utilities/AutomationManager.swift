import Foundation
import Combine

#if targetEnvironment(macCatalyst)
import UIKit

/// Automation trigger types
enum AutomationTrigger: String, Codable, CaseIterable, Identifiable {
    case screenUnlock = "Screen Unlock"
    case screenLock = "Screen Lock"
    case appLaunch = "App Launch"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .screenUnlock: return "lock.open.fill"
        case .screenLock: return "lock.fill"
        case .appLaunch: return "app.badge.fill"
        }
    }

    var description: String {
        switch self {
        case .screenUnlock: return "When your Mac wakes or is unlocked"
        case .screenLock: return "When your Mac sleeps or is locked"
        case .appLaunch: return "When HomeKit Menu is launched"
        }
    }
}

/// Represents an automation rule
struct AutomationRule: Codable, Identifiable, Equatable {
    var id: String { "\(trigger.rawValue)-\(sceneName)" }
    let trigger: AutomationTrigger
    let sceneName: String
    var isEnabled: Bool
}

/// Manages automation triggers for HomeKit scenes
@MainActor
final class AutomationManager: ObservableObject {
    static let shared = AutomationManager()

    @Published var rules: [AutomationRule] = []

    private let rulesKey = "automationRules"
    private var screenWakeObserver: AnyObject?
    private var screenSleepObserver: AnyObject?

    weak var homeKitManager: HomeKitManager?

    private init() {
        loadRules()
    }

    func setup(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager
        setupNotificationObservers()

        // Check for app launch automations
        executeAutomations(for: .appLaunch)
    }

    // MARK: - Rule Management

    func addRule(_ rule: AutomationRule) {
        // Remove existing rule for same trigger+scene
        rules.removeAll { $0.trigger == rule.trigger && $0.sceneName == rule.sceneName }
        rules.append(rule)
        saveRules()
    }

    func removeRule(_ rule: AutomationRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    func toggleRule(_ rule: AutomationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled.toggle()
            saveRules()
        }
    }

    func rule(for trigger: AutomationTrigger, sceneName: String) -> AutomationRule? {
        rules.first { $0.trigger == trigger && $0.sceneName == sceneName }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Use NSWorkspace notifications via dynamic loading
        guard let workspaceClass = NSClassFromString("NSWorkspace") else { return }

        // Get shared workspace
        let sharedSelector = NSSelectorFromString("sharedWorkspace")
        guard let workspace = (workspaceClass as AnyObject).perform(sharedSelector)?.takeUnretainedValue() else { return }

        // Get notification center
        let notifCenterSelector = NSSelectorFromString("notificationCenter")
        guard let notifCenter = (workspace as AnyObject).perform(notifCenterSelector)?.takeUnretainedValue() else { return }

        // Screen wake notification
        let wakeNotificationName = NSNotification.Name("NSWorkspaceScreensDidWakeNotification")
        screenWakeObserver = NotificationCenter.default.addObserver(
            forName: wakeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.executeAutomations(for: .screenUnlock)
            }
        }

        // Also observe distributed notification for more reliable unlock detection
        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(handleScreenUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        // Screen sleep notification
        let sleepNotificationName = NSNotification.Name("NSWorkspaceScreensDidSleepNotification")
        screenSleepObserver = NotificationCenter.default.addObserver(
            forName: sleepNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.executeAutomations(for: .screenLock)
            }
        }

        distributedCenter.addObserver(
            self,
            selector: #selector(handleScreenLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
    }

    @objc private func handleScreenUnlock(_ notification: Notification) {
        Task { @MainActor in
            executeAutomations(for: .screenUnlock)
        }
    }

    @objc private func handleScreenLock(_ notification: Notification) {
        Task { @MainActor in
            executeAutomations(for: .screenLock)
        }
    }

    // MARK: - Execution

    private func executeAutomations(for trigger: AutomationTrigger) {
        guard let homeKitManager = homeKitManager,
              let home = homeKitManager.currentHome else { return }

        let enabledRules = rules.filter { $0.trigger == trigger && $0.isEnabled }

        for rule in enabledRules {
            if let scene = home.actionSets.first(where: { $0.name == rule.sceneName }) {
                home.executeActionSet(scene) { error in
                    if let error = error {
                        print("Automation failed for \(rule.sceneName): \(error)")
                    } else {
                        print("Automation executed: \(rule.sceneName) on \(trigger.rawValue)")
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let loaded = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            rules = loaded
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }
}

#else

// Stub for non-Catalyst builds
@MainActor
final class AutomationManager: ObservableObject {
    static let shared = AutomationManager()
    @Published var rules: [String] = []
    weak var homeKitManager: HomeKitManager?
    func setup(homeKitManager: HomeKitManager) {}
}

enum AutomationTrigger: String, CaseIterable, Identifiable {
    case screenUnlock = "Screen Unlock"
    var id: String { rawValue }
    var icon: String { "lock.open.fill" }
    var description: String { "" }
}

struct AutomationRule: Identifiable, Equatable {
    var id: String { "" }
    let trigger: AutomationTrigger
    let sceneName: String
    var isEnabled: Bool
}

#endif
