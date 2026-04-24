import Foundation
import AppKit

/// Lightweight Umami analytics client for anonymous, privacy-respecting event tracking.
/// All events are fire-and-forget — failures are silently ignored to never impact the app.
///
/// Configuration is read at launch from (in order of precedence):
///   1. Process environment variables (useful for `swift run` in development):
///      - TOKENCAP_ANALYTICS_WEBSITE_ID
///      - TOKENCAP_ANALYTICS_ENDPOINT   (e.g. https://your-umami.example.com/api/send)
///      - TOKENCAP_ANALYTICS_ORIGIN     (e.g. https://yourapp.example.com)
///   2. Info.plist keys (baked into release builds):
///      - TCAnalyticsWebsiteID
///      - TCAnalyticsEndpoint
///      - TCAnalyticsOrigin
///
/// If any required value is missing, `track()` is a no-op even when the user has
/// opted in via Settings. See README.md → "Tracking app usage" for details.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let config: Config?
    private let sessionID = UUID().uuidString
    private let appVersion: String

    private init() {
        self.config = Config.load()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public API

    func track(_ event: String, data: [String: String]? = nil) {
        guard SettingsManager.shared.analyticsEnabled, let config else { return }

        let payload = EventPayload(
            website: config.websiteID,
            hostname: config.hostname,
            url: "/app/\(event)",
            title: "TokenCap",
            language: Locale.current.language.languageCode?.identifier ?? "en",
            screen: screenResolution,
            name: event,
            data: data
        )

        let body = SendBody(type: "event", payload: payload)

        Task.detached(priority: .utility) { [endpoint = config.endpoint, origin = config.origin, appVersion] in
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

// MARK: - Config

private struct Config {
    let websiteID: String
    let endpoint: URL
    let origin: String
    let hostname: String

    static func load() -> Config? {
        guard let websiteID = value(env: "TOKENCAP_ANALYTICS_WEBSITE_ID", plist: "TCAnalyticsWebsiteID"),
              let endpointString = value(env: "TOKENCAP_ANALYTICS_ENDPOINT", plist: "TCAnalyticsEndpoint"),
              let endpoint = URL(string: endpointString),
              let origin = value(env: "TOKENCAP_ANALYTICS_ORIGIN", plist: "TCAnalyticsOrigin")
        else { return nil }

        let hostname = URL(string: origin)?.host ?? "tokencap.local"
        return Config(websiteID: websiteID, endpoint: endpoint, origin: origin, hostname: hostname)
    }

    private static func value(env: String, plist: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        if let v = Bundle.main.infoDictionary?[plist] as? String, !v.isEmpty { return v }
        return nil
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
