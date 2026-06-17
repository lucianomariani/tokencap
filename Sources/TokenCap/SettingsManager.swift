import Foundation
import Security
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

    /// Monitored accounts. Persisted as JSON. Migrated from the legacy
    /// single-account settings on first launch of this version.
    @Published var accounts: [Account] {
        didSet { persistAccounts() }
    }

    // Array from v1 — UI exposes one slot in M2/M3, fans out in M4.
    @Published var deviceHostnames: [String] {
        didSet { UserDefaults.standard.set(deviceHostnames, forKey: "deviceHostnames") }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "launchAtLogin": false,
            "pollInterval": 60.0,
            "notificationsEnabled": true,
            "enabledThresholds": [10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 85, 90],
            "analyticsEnabled": false,
            "deviceHostnames": [String](),
        ])

        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.pollInterval = defaults.double(forKey: "pollInterval")
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")

        self.analyticsEnabled = defaults.bool(forKey: "analyticsEnabled")
        self.customConfigDir = defaults.string(forKey: "customConfigDir")
        self.deviceHostnames = defaults.stringArray(forKey: "deviceHostnames") ?? []

        if let saved = defaults.array(forKey: "enabledThresholds") as? [Int] {
            self.enabledThresholds = Set(saved)
        } else {
            self.enabledThresholds = [50, 75, 80, 90]
        }

        // Load accounts, or migrate from the legacy single-account config.
        if let data = defaults.data(forKey: "accounts"),
           let decoded = try? JSONDecoder().decode([Account].self, from: data),
           !decoded.isEmpty {
            self.accounts = decoded
        } else {
            self.accounts = Self.migratedAccounts(customConfigDir: defaults.string(forKey: "customConfigDir"))
            // Persist the migrated default so it's stable across launches.
            if let data = try? JSONEncoder().encode(self.accounts) {
                defaults.set(data, forKey: "accounts")
            }
        }
    }

    /// Builds the default account list from the legacy single-account settings.
    /// A non-empty custom config dir becomes a `.directory` source; otherwise `.auto`.
    static func migratedAccounts(customConfigDir: String?) -> [Account] {
        let source: CredentialSource = (customConfigDir?.isEmpty == false)
            ? .directory(customConfigDir!)
            : .auto
        return [Account(label: "Personal", provider: .claude, source: source)]
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "accounts")
        }
    }

    /// Adds a new account with a sensible default label.
    func addAccount(provider: Provider = .claude) {
        let base = provider == .claude ? "Claude" : "Codex"
        accounts.append(Account(label: base, provider: provider, source: .auto))
    }

    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
    }

    /// Replaces an account in place (by id), preserving order.
    func updateAccount(_ account: Account) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
    }

    /// Searches known locations where Claude Code stores `.credentials.json`.
    /// Returns the first directory that contains valid credentials, or nil.
    /// Resolves symlinks so dotfile setups (e.g. `~/.claude` -> dotfiles repo) work correctly.
    var detectedConfigDir: String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let candidates = [
            "\(home)/.claude",
            "\(home)/.config/claude",
        ]

        for dir in candidates {
            let resolved = resolvingSymlinks("\(dir)/.credentials.json")
            if fm.fileExists(atPath: resolved) {
                return resolvingSymlinks(dir)
            }
        }

        return nil
    }

    /// Whether credentials exist in the macOS Keychain (Claude Code 1.0.33+).
    var hasKeychainCredentials: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
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
