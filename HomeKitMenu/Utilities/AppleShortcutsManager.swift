import Foundation
import UIKit

#if targetEnvironment(macCatalyst)

/// Represents a shortcut folder with its contents
struct ShortcutFolder: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String // For display (handles empty names)
    var shortcuts: [String]
}

/// Manages fetching and running Apple Shortcuts
@MainActor
final class AppleShortcutsManager: ObservableObject {
    static let shared = AppleShortcutsManager()

    @Published var allShortcuts: [String] = []
    @Published var folders: [ShortcutFolder] = []
    @Published var isLoading = false

    private init() {
        loadShortcuts()
    }

    /// Loads all shortcuts and folders from the system
    func loadShortcuts() {
        isLoading = true

        Task.detached { [weak self] in
            // Get all shortcuts
            let allShortcuts = await self?.fetchShortcutsList() ?? []

            // Get folder names
            let folderNames = await self?.fetchFoldersList() ?? []

            // Get shortcuts for each folder
            var folders: [ShortcutFolder] = []
            for folderName in folderNames {
                let shortcutsInFolder = await self?.fetchShortcutsInFolder(folderName) ?? []
                let displayName = folderName.isEmpty ? "Shortcuts" : folderName
                folders.append(ShortcutFolder(
                    name: folderName,
                    displayName: displayName,
                    shortcuts: shortcutsInFolder
                ))
            }

            await MainActor.run {
                self?.allShortcuts = allShortcuts
                self?.folders = folders
                self?.isLoading = false
            }
        }
    }

    /// Fetches the list of all shortcuts
    private func fetchShortcutsList() async -> [String] {
        return await runShellCommand("/usr/bin/shortcuts list")
    }

    /// Fetches the list of folder names
    private func fetchFoldersList() async -> [String] {
        return await runShellCommand("/usr/bin/shortcuts list --folders")
    }

    /// Fetches shortcuts in a specific folder
    private func fetchShortcutsInFolder(_ folderName: String) async -> [String] {
        // Escape for AppleScript's do shell script - need to escape both for AppleScript and shell
        // First escape backslashes, then escape quotes for the shell, then escape quotes for AppleScript
        let escapedName = folderName
            .replacingOccurrences(of: "\\", with: "\\\\\\\\")  // \ -> \\\\ (double escape for AppleScript + shell)
            .replacingOccurrences(of: "\"", with: "\\\\\\\"")  // " -> \\\" (escape for both)

        return await runShellCommand("/usr/bin/shortcuts list --folder-name \\\"\(escapedName)\\\"")
    }

    /// Runs a shell command via AppleScript and returns the output lines
    private func runShellCommand(_ command: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let appleScriptClass = NSClassFromString("NSAppleScript") as? NSObject.Type else {
                    continuation.resume(returning: [])
                    return
                }

                // Use a unique delimiter to preserve line separation
                let delimiter = "|||SHORTCUT_DELIM|||"
                let modifiedCommand = "\(command) | /usr/bin/tr '\\n' '\\0' | /usr/bin/xargs -0 -I {} /bin/echo '{}' | /usr/bin/paste -sd '\(delimiter)' -"

                // Simpler approach: just run the command and split carefully
                let scriptSource = "do shell script \"\(command)\""

                // Create the AppleScript
                let initSelector = NSSelectorFromString("initWithSource:")
                guard let script = appleScriptClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else {
                    continuation.resume(returning: [])
                    return
                }

                let initInv = (script as AnyObject).method(for: initSelector)
                typealias InitFunc = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
                let initFunc = unsafeBitCast(initInv, to: InitFunc.self)

                guard let initializedScript = initFunc(script as AnyObject, initSelector, scriptSource as NSString) else {
                    continuation.resume(returning: [])
                    return
                }

                // Execute the script
                let executeSelector = NSSelectorFromString("executeAndReturnError:")
                var errorDict: NSDictionary?

                let executeInv = (initializedScript as AnyObject).method(for: executeSelector)
                typealias ExecuteFunc = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSDictionary?>) -> AnyObject?
                let executeFunc = unsafeBitCast(executeInv, to: ExecuteFunc.self)

                let result = executeFunc(initializedScript as AnyObject, executeSelector, &errorDict)

                if let result = result {
                    // Get the string value from the result
                    let stringValueSelector = NSSelectorFromString("stringValue")
                    if let stringValue = (result as AnyObject).perform(stringValueSelector)?.takeUnretainedValue() as? String {
                        // AppleScript converts newlines to \r, so handle that
                        let normalizedString = stringValue
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")

                        let lines = normalizedString.components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        continuation.resume(returning: lines)
                        return
                    }
                }

                continuation.resume(returning: [])
            }
        }
    }

    /// Runs a shortcut by name
    func runShortcut(named name: String) {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") {
            UIApplication.shared.open(url)
        }
    }
}

#else

struct ShortcutFolder: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    var shortcuts: [String]
}

@MainActor
final class AppleShortcutsManager: ObservableObject {
    static let shared = AppleShortcutsManager()
    @Published var allShortcuts: [String] = []
    @Published var folders: [ShortcutFolder] = []
    @Published var isLoading = false
    func loadShortcuts() {}
    func runShortcut(named name: String) {}
}

#endif
