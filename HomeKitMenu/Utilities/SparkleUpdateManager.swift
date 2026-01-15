import Foundation

#if targetEnvironment(macCatalyst)
import UIKit

/// Manages updates for HomeKit Menu with in-app download
@MainActor
final class SparkleUpdateManager: NSObject {
    static let shared = SparkleUpdateManager()

    private let appcastURL = "https://www.generouscorp.com/homekitmenu-releases/appcast/release.xml"
    private var downloadTask: URLSessionDownloadTask?
    private var progressAlert: UIAlertController?
    private var pendingVersion: String?

    private override init() {
        super.init()
    }

    /// Returns whether updates can be checked
    var canCheckForUpdates: Bool { true }

    /// Checks for updates and shows alert if available
    func checkForUpdates() {
        Task {
            await checkForUpdatesAsync()
        }
    }

    private func checkForUpdatesAsync() async {
        guard let url = URL(string: appcastURL) else {
            showErrorAlert(message: "Could not check for updates.")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = AppcastParser()
            if let latestVersion = parser.parseLatestVersion(from: data) {
                let currentVersion = getCurrentVersion()

                if isVersion(latestVersion.version, newerThan: currentVersion) {
                    showUpdateAlert(newVersion: latestVersion.version, downloadURL: latestVersion.downloadURL)
                } else {
                    showUpToDateAlert()
                }
            } else {
                showErrorAlert(message: "Could not parse update information.")
            }
        } catch {
            showErrorAlert(message: "Could not connect to update server.\n\n\(error.localizedDescription)")
        }
    }

    private func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func isVersion(_ newVersion: String, newerThan currentVersion: String) -> Bool {
        let new = newVersion.split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(new.count, current.count) {
            let newPart = i < new.count ? new[i] : 0
            let currentPart = i < current.count ? current[i] : 0
            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }

    private func showUpdateAlert(newVersion: String, downloadURL: String?) {
        guard let rootVC = getRootViewController() else { return }

        let alert = UIAlertController(
            title: "Update Available",
            message: "HomeKit Menu \(newVersion) is available. Would you like to download and install it?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Install Update", style: .default) { [weak self] _ in
            if let downloadURL = downloadURL {
                self?.pendingVersion = newVersion
                self?.downloadUpdate(from: downloadURL, version: newVersion)
            }
        })

        alert.addAction(UIAlertAction(title: "Later", style: .cancel))

        rootVC.present(alert, animated: true)
    }

    private func downloadUpdate(from urlString: String, version: String) {
        guard let url = URL(string: urlString),
              let rootVC = getRootViewController() else { return }

        // Show progress alert
        let alert = UIAlertController(
            title: "Downloading Update",
            message: "Downloading HomeKit Menu \(version)...\n\n",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.downloadTask?.cancel()
            self?.downloadTask = nil
        })

        rootVC.present(alert, animated: true)
        progressAlert = alert

        // Start download
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    private func handleDownloadedFile(at location: URL, version: String) {
        // Use caches directory (always writable in sandbox) instead of Downloads
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dmgPath = cachesURL.appendingPathComponent("HomeKitMenu-\(version).dmg")

        do {
            // Remove existing file if present
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: location, to: dmgPath)

            // Open the DMG - this mounts it and shows in Finder
            showInstallInstructions(dmgPath: dmgPath, version: version)

        } catch {
            showErrorAlert(message: "Failed to save update: \(error.localizedDescription)")
        }
    }

    private func showInstallInstructions(dmgPath: URL, version: String) {
        guard let rootVC = getRootViewController() else { return }

        let alert = UIAlertController(
            title: "Update Downloaded",
            message: "HomeKit Menu \(version) has been downloaded.\n\nClick \"Open & Install\" to:\n1. Open the disk image\n2. Drag HomeKit Menu to Applications\n3. Relaunch the app",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Open & Install", style: .default) { _ in
            // Open the DMG file - macOS will mount it and show Finder
            UIApplication.shared.open(dmgPath, options: [:]) { success in
                if success {
                    // Show reminder to quit and relaunch
                    Task { @MainActor in
                        self.showRelanchReminder()
                    }
                }
            }
        })

        alert.addAction(UIAlertAction(title: "Later", style: .cancel))

        rootVC.present(alert, animated: true)
    }

    private func showRelanchReminder() {
        guard let rootVC = getRootViewController() else { return }

        let alert = UIAlertController(
            title: "Installation",
            message: "After dragging HomeKit Menu to Applications:\n\n1. Quit this app (⌘Q)\n2. Launch the new version from Applications",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Quit Now", style: .destructive) { _ in
            exit(0)
        })

        alert.addAction(UIAlertAction(title: "Later", style: .cancel))

        rootVC.present(alert, animated: true)
    }

    private func showUpToDateAlert() {
        guard let rootVC = getRootViewController() else { return }

        let alert = UIAlertController(
            title: "You're Up to Date",
            message: "HomeKit Menu \(getCurrentVersion()) is the latest version.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        rootVC.present(alert, animated: true)
    }

    private func showErrorAlert(message: String) {
        guard let rootVC = getRootViewController() else { return }

        let alert = UIAlertController(
            title: "Update Error",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        rootVC.present(alert, animated: true)
    }

    private func getRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else {
            return nil
        }

        // Find the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - URLSessionDownloadDelegate
extension SparkleUpdateManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let version = Task { @MainActor in pendingVersion ?? "latest" }

        // Copy file to a temp location we control (the original is deleted after this callback)
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        try? FileManager.default.copyItem(at: location, to: tempCopy)

        Task { @MainActor in
            progressAlert?.dismiss(animated: true)
            progressAlert = nil

            let ver = await version.value
            handleDownloadedFile(at: tempCopy, version: ver)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let percent = Int(progress * 100)
                let downloaded = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)

                progressAlert?.message = "Downloading HomeKit Menu...\n\(downloaded) of \(total) (\(percent)%)"
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error, (error as NSError).code != NSURLErrorCancelled {
                progressAlert?.dismiss(animated: true)
                progressAlert = nil
                showErrorAlert(message: "Download failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Simple XML parser for Sparkle appcast
private class AppcastParser: NSObject, XMLParserDelegate {
    struct VersionInfo {
        let version: String
        let downloadURL: String?
    }

    private var currentElement = ""
    private var latestVersion: String?
    private var latestDownloadURL: String?
    private var inItem = false

    func parseLatestVersion(from data: Data) -> VersionInfo? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let version = latestVersion {
            return VersionInfo(version: version, downloadURL: latestDownloadURL)
        }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            inItem = true
        }

        if elementName == "enclosure" && inItem {
            if let version = attributeDict["sparkle:shortVersionString"] {
                if latestVersion == nil || isVersion(version, newerThan: latestVersion!) {
                    latestVersion = version
                    latestDownloadURL = attributeDict["url"]
                }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            inItem = false
        }
    }

    private func isVersion(_ newVersion: String, newerThan currentVersion: String) -> Bool {
        let new = newVersion.split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(new.count, current.count) {
            let newPart = i < new.count ? new[i] : 0
            let currentPart = i < current.count ? current[i] : 0
            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }
}

#else

@MainActor
final class SparkleUpdateManager: NSObject {
    static let shared = SparkleUpdateManager()
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}

#endif
