import Foundation
import os

// Wire schema v1 is canonical in:
// https://github.com/lucianomariani/tokencap-t-display-s3 (README.md)
// Bump `v` on any breaking change to the JSON shape.

@MainActor
final class DevicePusher {
    static let shared = DevicePusher()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.helsky-labs.tokencap", category: "DevicePusher")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.0
        config.waitsForConnectivity = false
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    func push(usage: UsageResponse, to hostnames: [String]) async {
        let urls = hostnames.compactMap(Self.updateURL(for:))
        guard !urls.isEmpty else { return }

        let payload = Self.payload(from: usage)
        guard let body = try? encoder.encode(payload) else {
            logger.error("Failed to encode payload")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { [self] in await pushOne(url: url, body: body) }
            }
        }
    }

    private func pushOne(url: URL, body: Data) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                logger.debug("push \(url.host ?? "?") OK \(code)")
            } else {
                logger.warning("push \(url.host ?? "?") HTTP \(code)")
            }
        } catch {
            logger.warning("push \(url.host ?? "?") failed: \(error.localizedDescription)")
        }
    }

    // Accepts "tokencap.local", "192.168.1.11", "http://host:8080".
    // Appends /update.
    static func updateURL(for hostname: String) -> URL? {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "http://\(trimmed)"
        guard let base = URL(string: withScheme), base.host?.isEmpty == false else { return nil }
        return base.appendingPathComponent("update")
    }

    static func payload(from usage: UsageResponse) -> DevicePayload {
        func intPct(_ d: Double?) -> Int? { d.map { Int($0.rounded()) } }
        return DevicePayload(
            v: 1,
            ts: Int(Date().timeIntervalSince1970),
            sessionPct: intPct(usage.fiveHour?.utilization),
            sessionResetsAt: usage.fiveHour?.resetsAt,
            weeklyAllPct: intPct(usage.sevenDay?.utilization),
            weeklySonnetPct: intPct(usage.sevenDaySonnet?.utilization),
            weeklyOpusPct: intPct(usage.sevenDayOpus?.utilization),
            weeklyResetsAt: usage.sevenDay?.resetsAt,
            extraEnabled: usage.extraUsage?.isEnabled,
            extraPct: intPct(usage.extraUsage?.utilization),
            extraUsedCents: usage.extraUsage?.usedCredits.map { Int($0.rounded()) },
            extraLimitCents: usage.extraUsage?.monthlyLimit
        )
    }
}

struct DevicePayload: Encodable, Equatable {
    let v: Int
    let ts: Int
    let sessionPct: Int?
    let sessionResetsAt: String?
    let weeklyAllPct: Int?
    let weeklySonnetPct: Int?
    let weeklyOpusPct: Int?
    let weeklyResetsAt: String?
    let extraEnabled: Bool?
    let extraPct: Int?
    let extraUsedCents: Int?
    let extraLimitCents: Int?

    enum CodingKeys: String, CodingKey {
        case v, ts
        case sessionPct = "session_pct"
        case sessionResetsAt = "session_resets_at"
        case weeklyAllPct = "weekly_all_pct"
        case weeklySonnetPct = "weekly_sonnet_pct"
        case weeklyOpusPct = "weekly_opus_pct"
        case weeklyResetsAt = "weekly_resets_at"
        case extraEnabled = "extra_enabled"
        case extraPct = "extra_pct"
        case extraUsedCents = "extra_used_cents"
        case extraLimitCents = "extra_limit_cents"
    }
}
