import SwiftUI

@main
struct TokenCapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var usageService = UsageService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: usageService)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: menuBarIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarIconColor, .primary)
            Text(usageService.menuBarText)
                .font(.caption.monospacedDigit())
        }
        .onAppear {
            usageService.startPolling(interval: 60)
        }
    }

    // MARK: - Menu Bar Icon

    private var menuBarIcon: String {
        switch usageService.sessionUsageLevel {
        case .low: return "gauge.with.needle"
        case .medium: return "gauge.with.needle"
        case .high: return "gauge.with.needle.fill"
        }
    }

    private var menuBarIconColor: Color {
        switch usageService.sessionUsageLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
}
