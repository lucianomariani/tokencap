import Foundation
import Combine

/// One compact segment shown in the menu bar (e.g. "P 40%").
struct MenuSegment: Identifiable {
    let id: UUID
    let abbrev: String
    let text: String
    let level: UsageLevel
}

/// Owns one `AccountMonitor` per configured account, keeps them in sync with
/// `SettingsManager.accounts`, drives polling for all, and exposes aggregate
/// values for the menu bar.
@MainActor
final class UsageCoordinator: ObservableObject {
    @Published private(set) var monitors: [AccountMonitor] = []

    private let settings: SettingsManager
    private let notifications: NotificationService
    private let devicePusher: DevicePusher
    private var pollTimer: Timer?
    private var currentInterval: TimeInterval = 60
    private var accountsObserver: AnyCancellable?
    /// Forwards each monitor's changes up so views observing the coordinator
    /// (menu bar, footer aggregates) refresh when any account's state changes.
    private var monitorObservers: [UUID: AnyCancellable] = [:]

    init(settings: SettingsManager, notifications: NotificationService, devicePusher: DevicePusher) {
        self.settings = settings
        self.notifications = notifications
        self.devicePusher = devicePusher
        sync(with: settings.accounts)
        accountsObserver = settings.$accounts
            .dropFirst()
            .sink { [weak self] accounts in
                Task { @MainActor in self?.sync(with: accounts) }
            }
    }

    // MARK: - Monitor lifecycle

    /// Reconciles the monitor list with the configured accounts, preserving
    /// existing monitors (and their state) by id. Newly added monitors are
    /// fetched immediately if polling is active.
    private func sync(with accounts: [Account]) {
        var existing = Dictionary(uniqueKeysWithValues: monitors.map { ($0.id, $0) })
        var rebuilt: [AccountMonitor] = []
        var added: [AccountMonitor] = []

        for account in accounts {
            if let monitor = existing.removeValue(forKey: account.id) {
                monitor.update(account: account)
                rebuilt.append(monitor)
            } else {
                let monitor = AccountMonitor(account: account)
                rebuilt.append(monitor)
                added.append(monitor)
            }
        }
        // Anything left in `existing` was removed from settings — dropped here.

        monitors = rebuilt

        // Rebuild change-forwarding subscriptions for the current monitor set.
        monitorObservers = Dictionary(uniqueKeysWithValues: rebuilt.map { monitor in
            (monitor.id, monitor.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            })
        })

        if pollTimer != nil {
            for monitor in added {
                Task { await self.fetch(monitor) }
            }
        }
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        currentInterval = interval

        Task { await fetchAll() }

        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.fetchAll() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func fetchAll(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for monitor in monitors {
                group.addTask { @MainActor in await self.fetch(monitor, force: force) }
            }
        }
    }

    /// Fetches one monitor, then runs its side-effects: per-account threshold
    /// notifications, and (for the primary Claude account only) the device push.
    func fetch(_ monitor: AccountMonitor, force: Bool = false) async {
        await monitor.fetchUsage(force: force)
        guard let usage = monitor.usage else { return }

        notifications.checkThresholds(usage: usage, account: monitor.account, settings: settings)

        if monitor.account.provider == .claude, monitor.id == primaryClaudeMonitor?.id {
            await devicePusher.push(usage: usage, to: settings.deviceHostnames)
        }
    }

    // MARK: - Aggregates for the menu bar

    /// Whether to prefix segments with account labels. A single account reads
    /// cleaner without a label (just "40%").
    var showLabels: Bool { monitors.count > 1 }

    var menuBarSegments: [MenuSegment] {
        monitors.map { monitor in
            MenuSegment(
                id: monitor.id,
                abbrev: monitor.account.menuAbbreviation,
                text: monitor.usage != nil ? "\(Int(monitor.headlineUtilization))%" : "--",
                level: monitor.usageLevel
            )
        }
    }

    /// Worst level across accounts that have data — drives the menu bar icon color.
    var worstLevel: UsageLevel {
        let levels = monitors.compactMap { $0.usage != nil ? $0.usageLevel : nil }
        if levels.contains(.high) { return .high }
        if levels.contains(.medium) { return .medium }
        return .low
    }

    var anyLoading: Bool { monitors.contains { $0.isLoading } }

    var latestUpdate: Date? {
        monitors.compactMap { $0.lastUpdated }.max()
    }

    /// True when every monitor is erroring with no usage to show.
    var allDisconnected: Bool {
        !monitors.isEmpty && monitors.allSatisfy { $0.error != nil && $0.usage == nil }
    }

    /// First Claude account — used to feed the hardware device push (wire schema v1).
    var primaryClaudeMonitor: AccountMonitor? {
        monitors.first { $0.account.provider == .claude }
    }

    func monitor(for id: UUID) -> AccountMonitor? {
        monitors.first { $0.id == id }
    }
}
