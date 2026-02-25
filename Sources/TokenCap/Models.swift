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

    var isExpired: Bool {
        let expirationDate = Date(timeIntervalSince1970: Double(expiresAt) / 1000.0)
        return Date() >= expirationDate
    }

    var expirationDate: Date {
        Date(timeIntervalSince1970: Double(expiresAt) / 1000.0)
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

struct UsageBucket: Codable {
    let utilization: Double
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt)
    }

    var utilizationColor: UsageLevel {
        UsageLevel.from(utilization)
    }
}

struct ExtraUsage: Codable {
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

// MARK: - Usage Level (color coding)

enum UsageLevel {
    case low      // < 50% green
    case medium   // 50-80% yellow
    case high     // > 80% red

    static func from(_ utilization: Double) -> UsageLevel {
        if utilization > 80 {
            return .high
        } else if utilization >= 50 {
            return .medium
        } else {
            return .low
        }
    }
}
