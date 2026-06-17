import SwiftUI

@main
struct TokenCapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings: SettingsManager
    @StateObject private var coordinator: UsageCoordinator
    @StateObject private var updateService = UpdateService.shared
    @StateObject private var devicePusher = DevicePusher.shared
    @StateObject private var notifications: NotificationService

    init() {
        let settings = SettingsManager.shared
        let notifications = NotificationService()
        let coordinator = UsageCoordinator(
            settings: settings,
            notifications: notifications,
            devicePusher: DevicePusher.shared
        )
        _settings = StateObject(wrappedValue: settings)
        _notifications = StateObject(wrappedValue: notifications)
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator, settings: settings, updateService: updateService, notifications: notifications, devicePusher: devicePusher)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: menuBarIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarIconColor, .primary)
            menuBarSegmentsView
        }
        .onAppear {
            notifications.requestPermission()
            coordinator.startPolling(interval: settings.pollInterval)
            Task { await updateService.checkIfNeeded() }
            AnalyticsService.shared.track("app_launched", data: [
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "accounts": "\(settings.accounts.count)",
            ])
        }
        .onChange(of: settings.pollInterval) { _, newInterval in
            coordinator.startPolling(interval: newInterval)
        }
        .onChange(of: updateService.updateAvailable) { _, available in
            if available {
                notifications.notifyUpdateAvailable(version: updateService.latestVersion)
            }
        }
    }

    // MARK: - Menu Bar Segments

    @ViewBuilder
    private var menuBarSegmentsView: some View {
        let segments = coordinator.menuBarSegments
        if segments.isEmpty {
            Text("--%")
                .font(.caption.monospacedDigit())
        } else {
            // Cap to keep the menu bar narrow; overflow shown as "+N".
            let shown = Array(segments.prefix(3))
            HStack(spacing: 5) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, seg in
                    HStack(spacing: 2) {
                        if coordinator.showLabels {
                            Text(seg.abbrev)
                                .foregroundStyle(.secondary)
                        }
                        Text(seg.text)
                            .foregroundStyle(Color.statusColor(for: seg.level))
                    }
                    if idx < shown.count - 1 {
                        Text("·").foregroundStyle(.tertiary)
                    }
                }
                if segments.count > shown.count {
                    Text("+\(segments.count - shown.count)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption.monospacedDigit())
        }
    }

    // MARK: - Menu Bar Icon

    private var menuBarIcon: String {
        switch coordinator.worstLevel {
        case .low: return "gauge.with.needle"
        case .medium: return "gauge.with.needle"
        case .high: return "gauge.with.needle.fill"
        }
    }

    private var menuBarIconColor: Color {
        switch coordinator.worstLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // MenuBarExtra(.window) creates an NSPanel that auto-hides when it
        // loses key status. Button clicks can trigger that focus loss.
        // Setting becomesKeyOnlyIfNeeded prevents the resign-key cycle.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panel.becomesKeyOnlyIfNeeded = true
    }
}
