import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    private var firedThresholds: [String: Set<Int>] = [:]
    private let isAvailable: Bool

    init() {
        // UNUserNotificationCenter crashes without a proper app bundle (e.g. swift run).
        // Guard all access behind this flag.
        self.isAvailable = Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func checkThresholds(usage: UsageResponse, settings: SettingsManager) {
        guard settings.notificationsEnabled else { return }

        if let fiveHour = usage.fiveHour {
            checkBucket(key: "session", label: "Session", bucket: fiveHour, settings: settings)
        }
        if let sevenDay = usage.sevenDay {
            checkBucket(key: "weekly_all", label: "Weekly (All)", bucket: sevenDay, settings: settings)
        }
        if let sonnet = usage.sevenDaySonnet {
            checkBucket(key: "weekly_sonnet", label: "Sonnet Weekly", bucket: sonnet, settings: settings)
        }
        if let opus = usage.sevenDayOpus {
            checkBucket(key: "weekly_opus", label: "Opus Weekly", bucket: opus, settings: settings)
        }
    }

    func resetAllTracking() {
        firedThresholds = [:]
    }

    // MARK: - Private

    private func checkBucket(
        key: String, label: String, bucket: UsageBucket, settings: SettingsManager
    ) {
        let utilization = bucket.utilization
        let fired = firedThresholds[key] ?? []

        for threshold in settings.enabledThresholds.sorted() {
            guard utilization >= Double(threshold), !fired.contains(threshold) else { continue }
            fireNotification(key: key, label: label, threshold: threshold,
                             utilization: utilization, bucket: bucket)
            firedThresholds[key, default: []].insert(threshold)
        }

        // Reset tracking when utilization drops (window reset)
        if let lowestFired = fired.min(), utilization < Double(lowestFired) {
            firedThresholds[key] = []
        }
    }

    private func fireNotification(
        key: String, label: String, threshold: Int,
        utilization: Double, bucket: UsageBucket
    ) {
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(label) at \(threshold)%"

        let level = UsageLevel.from(utilization)
        let remaining = bucket.resetTimeRemaining ?? "unknown"

        switch level {
        case .low:
            content.body = "\(label) at \(Int(utilization))%. Resets in \(remaining)."
        case .medium:
            content.body = "\(label) halfway. Resets in \(remaining)."
        case .high:
            content.body = "Approaching limit. Consider pausing for \(remaining)."
        }

        content.sound = level == .high ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: "tokencap-\(key)-\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
