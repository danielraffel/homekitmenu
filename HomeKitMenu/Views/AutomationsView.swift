import SwiftUI

#if targetEnvironment(macCatalyst)

/// View for managing automation rules
struct AutomationsView: View {
    let homeKitManager: HomeKitManager
    @StateObject private var automationManager = AutomationManager.shared
    @Environment(\.dismiss) private var dismiss

    private var scenes: [String] {
        guard let home = homeKitManager.currentHome else { return [] }
        return home.actionSets
            .filter { !$0.name.hasPrefix("com.apple") }
            .map { $0.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if scenes.isEmpty {
                    Section {
                        Text("No scenes available. Create scenes in the Home app first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(AutomationTrigger.allCases) { trigger in
                        Section {
                            ForEach(scenes, id: \.self) { sceneName in
                                AutomationRuleRow(
                                    trigger: trigger,
                                    sceneName: sceneName,
                                    automationManager: automationManager
                                )
                            }
                        } header: {
                            HStack {
                                Image(systemName: trigger.icon)
                                Text(trigger.rawValue)
                            }
                        } footer: {
                            Text(trigger.description)
                        }
                    }
                }

                Section {
                    Text("Automations run when triggers occur while HomeBar Menu Bar is running. Keep the app open in the menu bar for automations to work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Automations")
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

struct AutomationRuleRow: View {
    let trigger: AutomationTrigger
    let sceneName: String
    @ObservedObject var automationManager: AutomationManager

    private var existingRule: AutomationRule? {
        automationManager.rule(for: trigger, sceneName: sceneName)
    }

    private var isEnabled: Bool {
        existingRule?.isEnabled ?? false
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                if newValue {
                    // Create/enable rule
                    let rule = AutomationRule(
                        trigger: trigger,
                        sceneName: sceneName,
                        isEnabled: true
                    )
                    automationManager.addRule(rule)
                } else if let rule = existingRule {
                    // Disable rule
                    automationManager.removeRule(rule)
                }
            }
        )) {
            HStack {
                Image(systemName: "theatermasks.fill")
                    .foregroundStyle(.secondary)
                Text(sceneName)
            }
        }
    }
}

#else

struct AutomationsView: View {
    let homeKitManager: HomeKitManager

    var body: some View {
        Text("Automations not available")
    }
}

#endif
