import Foundation

// MARK: - Credentials

struct CredentialsFile: Codable {
    let claudeAiOauth: OAuthCredentials
}

struct OAuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64 // milliseconds epoch
    let subscriptionType: String?
    let rateLimitTier: String?

    var expirationDate: Date {
        Date(timeIntervalSince1970: Double(expiresAt) / 1000.0)
    }

    var isExpired: Bool {
        Date() >= expirationDate
    }
}

// MARK: - Usage API Response

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDayOauthApps: UsageBucket?
    let sevenDayCowork: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct UsageBucket: Codable, Equatable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt)
    }

    var resetTimeRemaining: String? {
        guard let date = resetDate else { return nil }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Int?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Common Account Usage

/// Provider-agnostic usage shape that the UI renders. Both Claude and Codex
/// map their native responses into this so the Usage tab stays provider-blind.
struct AccountUsage: Equatable {
    var primary: UsageBucket?                 // 5-hour rolling window
    var secondary: UsageBucket?               // 7-day window (all models)
    var breakdown: [LabeledBucket]            // per-model / per-category rows
    var extra: ExtraUsage?

    init(primary: UsageBucket? = nil,
         secondary: UsageBucket? = nil,
         breakdown: [LabeledBucket] = [],
         extra: ExtraUsage? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.breakdown = breakdown
        self.extra = extra
    }

    /// Utilization that drives the menu bar / icon color for this account.
    /// Prefers the 5-hour window, falling back to the worst available bucket.
    var headlineUtilization: Double {
        if let primary { return primary.utilization }
        var candidates: [Double] = []
        if let secondary { candidates.append(secondary.utilization) }
        candidates.append(contentsOf: breakdown.map { $0.bucket.utilization })
        if let extraUtil = extra?.utilization { candidates.append(extraUtil) }
        return candidates.max() ?? 0
    }
}

struct LabeledBucket: Equatable {
    let label: String
    let bucket: UsageBucket
}

extension UsageResponse {
    func toAccountUsage() -> AccountUsage {
        var breakdown: [LabeledBucket] = []
        if let s = sevenDaySonnet { breakdown.append(LabeledBucket(label: "Sonnet", bucket: s)) }
        if let o = sevenDayOpus { breakdown.append(LabeledBucket(label: "Opus", bucket: o)) }
        if let a = sevenDayOauthApps { breakdown.append(LabeledBucket(label: "OAuth Apps", bucket: a)) }
        if let c = sevenDayCowork { breakdown.append(LabeledBucket(label: "Cowork", bucket: c)) }
        return AccountUsage(
            primary: fiveHour,
            secondary: sevenDay,
            breakdown: breakdown,
            extra: extraUsage
        )
    }
}

// MARK: - Codex Usage API Response

/// Response from the reverse-engineered Codex backend usage endpoint
/// (`/backend-api/codex/usage`). Field names mirror the ChatGPT backend's
/// rate-limit window shape and MUST be confirmed against live data.
struct CodexUsageResponse: Codable {
    let primary: CodexRateLimit?       // 5-hour window
    let secondary: CodexRateLimit?     // 7-day window

    enum CodingKeys: String, CodingKey {
        case primary = "primary"
        case secondary = "secondary"
    }

    func toAccountUsage() -> AccountUsage {
        AccountUsage(
            primary: primary?.toBucket(),
            secondary: secondary?.toBucket(),
            breakdown: [],
            extra: nil
        )
    }
}

struct CodexRateLimit: Codable {
    let usedPercent: Double?
    let resetsAt: String?       // ISO8601, when present
    let resetsInSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case resetsInSeconds = "resets_in_seconds"
    }

    func toBucket() -> UsageBucket {
        UsageBucket(utilization: usedPercent ?? 0, resetsAt: resolvedResetsAt)
    }

    /// Codex sometimes reports a relative reset (`resets_in_seconds`) instead of
    /// an absolute timestamp; normalize to the ISO8601 string `UsageBucket` expects.
    private var resolvedResetsAt: String? {
        if let resetsAt { return resetsAt }
        guard let secs = resetsInSeconds, secs > 0 else { return nil }
        let date = Date().addingTimeInterval(secs)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Usage Level (color coding)

enum UsageLevel: Equatable, CustomStringConvertible {
    case low      // < 50% green
    case medium   // 50-80% yellow
    case high     // > 80% red

    var description: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    static func from(_ utilization: Double) -> UsageLevel {
        if utilization >= 80 {
            return .high
        } else if utilization >= 50 {
            return .medium
        } else {
            return .low
        }
    }
}
