import Foundation
import ServiceManagement

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    static let allThresholds = [10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 85, 90]

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    @Published var pollInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollInterval, forKey: "pollInterval") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var enabledThresholds: Set<Int> {
        didSet { UserDefaults.standard.set(Array(enabledThresholds), forKey: "enabledThresholds") }
    }

    @Published var analyticsEnabled: Bool {
        didSet { UserDefaults.standard.set(analyticsEnabled, forKey: "analyticsEnabled") }
    }

    @Published var customConfigDir: String? {
        didSet { UserDefaults.standard.set(customConfigDir, forKey: "customConfigDir") }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "launchAtLogin": false,
            "pollInterval": 60.0,
            "notificationsEnabled": true,
            "enabledThresholds": [50, 75, 80, 90],
            "analyticsEnabled": true,
        ])

        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.pollInterval = defaults.double(forKey: "pollInterval")
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")

        self.analyticsEnabled = defaults.bool(forKey: "analyticsEnabled")
        self.customConfigDir = defaults.string(forKey: "customConfigDir")

        if let saved = defaults.array(forKey: "enabledThresholds") as? [Int] {
            self.enabledThresholds = Set(saved)
        } else {
            self.enabledThresholds = [50, 75, 80, 90]
        }
    }

    /// The resolved path to `.credentials.json`.
    /// Priority: user-set custom dir > auto-detected dir > default `~/.claude`.
    var credentialsPath: String {
        if let custom = customConfigDir, !custom.isEmpty {
            return "\(custom)/.credentials.json"
        }
        if let detected = detectedConfigDir {
            return "\(detected)/.credentials.json"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/.credentials.json"
    }

    /// Searches known locations where Claude Code stores `.credentials.json`.
    /// Returns the first directory that contains valid credentials, or nil.
    var detectedConfigDir: String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let candidates = [
            "\(home)/.claude",
            "\(home)/.config/claude",
        ]

        for dir in candidates {
            if fm.fileExists(atPath: "\(dir)/.credentials.json") {
                return dir
            }
        }

        return nil
    }

    func toggleThreshold(_ threshold: Int) {
        if enabledThresholds.contains(threshold) {
            enabledThresholds.remove(threshold)
        } else {
            enabledThresholds.insert(threshold)
        }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item error: \(error)")
        }
    }
}
