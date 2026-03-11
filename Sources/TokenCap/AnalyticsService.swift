import Foundation
import AppKit

/// Lightweight Umami analytics client for anonymous, privacy-respecting event tracking.
/// All events are fire-and-forget — failures are silently ignored to never impact the app.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let websiteID = "a9b94dba-2442-4c1a-be15-e717a11f9321"
    private let endpoint = URL(string: "https://analytics.helsky-labs.com/api/send")!
    private let origin = "https://tokencap.app"
    private let sessionID = UUID().uuidString
    private let appVersion: String

    private init() {
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public API

    func track(_ event: String, data: [String: String]? = nil) {
        guard SettingsManager.shared.analyticsEnabled else { return }

        let payload = EventPayload(
            website: websiteID,
            hostname: "tokencap.app",
            url: "/app/\(event)",
            title: "TokenCap",
            language: Locale.current.language.languageCode?.identifier ?? "en",
            screen: screenResolution,
            name: event,
            data: data
        )

        let body = SendBody(type: "event", payload: payload)

        Task.detached(priority: .utility) { [endpoint, origin, appVersion] in
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("TokenCap/\(appVersion)", forHTTPHeaderField: "User-Agent")
                request.setValue(origin, forHTTPHeaderField: "Origin")
                request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
                request.timeoutInterval = 10
                request.httpBody = try JSONEncoder().encode(body)

                let (_, _) = try await URLSession.shared.data(for: request)
            } catch {
                // Silently ignore — analytics should never impact the app
            }
        }
    }

    // MARK: - Private

    private var screenResolution: String {
        guard let screen = NSScreen.main else { return "0x0" }
        let size = screen.frame.size
        return "\(Int(size.width))x\(Int(size.height))"
    }
}

// MARK: - Umami Payload

private struct SendBody: Encodable {
    let type: String
    let payload: EventPayload
}

private struct EventPayload: Encodable {
    let website: String
    let hostname: String
    let url: String
    let title: String
    let language: String
    let screen: String
    let name: String
    let data: [String: String]?
}
