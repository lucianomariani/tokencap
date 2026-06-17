import Foundation
import Combine

/// Monitors a single account: owns its token cache, 429 backoff, and published
/// usage/error state. One instance per `Account`, driven by a `UsageProvider`.
@MainActor
final class AccountMonitor: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var account: Account
    @Published var usage: AccountUsage?
    @Published var lastUpdated: Date?
    @Published var error: UsageError?
    @Published var isLoading: Bool = false

    private var provider: UsageProvider
    private var cachedToken: CachedToken?
    private var retryAfter: Date?
    private var consecutiveRateLimits: Int = 0
    private var lastTrackedLevel: UsageLevel?

    init(account: Account) {
        self.id = account.id
        self.account = account
        self.provider = ProviderFactory.make(for: account.provider)
    }

    /// Applies edited account metadata in place. Clears caches when the provider
    /// or credential source changes so stale tokens/usage don't linger.
    func update(account: Account) {
        let providerChanged = account.provider != self.account.provider
        let sourceChanged = account.source != self.account.source
        self.account = account
        if providerChanged { provider = ProviderFactory.make(for: account.provider) }
        if providerChanged || sourceChanged {
            cachedToken = nil
            usage = nil
            error = nil
            retryAfter = nil
            consecutiveRateLimits = 0
            lastTrackedLevel = nil
        }
    }

    // MARK: - Token

    private func readToken() throws -> String {
        if let cached = cachedToken, cached.isValid { return cached.token }
        cachedToken = nil
        let fresh = try provider.readToken(source: account.source)
        cachedToken = fresh
        return fresh.token
    }

    // MARK: - Fetch

    func fetchUsage(force: Bool = false) async {
        // Skip if still backing off from a previous 429 (force bypasses).
        if !force, let retryAfter, Date() < retryAfter { return }
        if let retryAfter, Date() >= retryAfter,
           Date().timeIntervalSince(retryAfter) > 120 {
            consecutiveRateLimits = 0
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let token = try readToken()
            let result = try await provider.fetchUsage(token: token)

            consecutiveRateLimits = 0
            retryAfter = nil
            usage = result
            lastUpdated = Date()
            error = nil

            let level = UsageLevel.from(result.headlineUtilization)
            if level != lastTrackedLevel {
                AnalyticsService.shared.track("usage_level_changed", data: [
                    "provider": account.provider.rawValue,
                    "level": level.description,
                    "utilization": "\(Int(result.headlineUtilization))",
                ])
                lastTrackedLevel = level
            }
        } catch let error as UsageError {
            handle(error)
        } catch {
            self.error = .unexpected(error.localizedDescription)
            AnalyticsService.shared.track("usage_error", data: [
                "provider": account.provider.rawValue,
                "type": "unexpected",
            ])
        }
    }

    private func handle(_ error: UsageError) {
        switch error {
        case .httpError(401, _):
            cachedToken = nil
            self.error = error
        case .rateLimited(let suggested):
            applyRateLimitBackoff(suggested: suggested)
            self.error = .rateLimited(retryAfter)  // expose computed date for the countdown UI
        default:
            self.error = error
        }
        AnalyticsService.shared.track("usage_error", data: [
            "provider": account.provider.rawValue,
            "type": error.analyticsLabel,
        ])
    }

    /// Exponential backoff on 429. Uses the provider-parsed `Retry-After` date if
    /// present, otherwise 2min → 4min → 8min, capped at 10min.
    private func applyRateLimitBackoff(suggested: Date?) {
        consecutiveRateLimits += 1
        if let suggested {
            retryAfter = suggested
        } else {
            let backoff = min(120 * pow(2.0, Double(consecutiveRateLimits - 1)), 600)
            retryAfter = Date().addingTimeInterval(backoff)
        }
    }

    // MARK: - Computed

    var headlineUtilization: Double { usage?.headlineUtilization ?? 0 }
    var usageLevel: UsageLevel { UsageLevel.from(headlineUtilization) }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case claudeCodeNotInstalled
    case oauthLoginRequired
    case unsupportedFormat
    case tokenExpired(Date)
    case invalidResponse
    case rateLimited(Date?)
    case httpError(Int, String)
    case unexpected(String)

    var isTokenIssue: Bool {
        switch self {
        case .claudeCodeNotInstalled, .oauthLoginRequired, .unsupportedFormat, .tokenExpired:
            return true
        default:
            return false
        }
    }

    var iconName: String {
        switch self {
        case .claudeCodeNotInstalled: return "key.fill"
        case .oauthLoginRequired: return "person.badge.key.fill"
        case .unsupportedFormat: return "doc.questionmark.fill"
        case .tokenExpired: return "clock.arrow.circlepath"
        case .rateLimited: return "hourglass"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var analyticsLabel: String {
        switch self {
        case .claudeCodeNotInstalled: return "claude_not_installed"
        case .oauthLoginRequired: return "oauth_login_required"
        case .unsupportedFormat: return "unsupported_format"
        case .tokenExpired: return "token_expired"
        case .invalidResponse: return "invalid_response"
        case .rateLimited: return "rate_limited"
        case .httpError(let code, _): return "http_\(code)"
        case .unexpected: return "unexpected"
        }
    }

    var errorDescription: String? {
        switch self {
        case .claudeCodeNotInstalled:
            return "Not found"
        case .oauthLoginRequired:
            return "Login required"
        case .unsupportedFormat:
            return "Unsupported credential format"
        case .tokenExpired:
            return "Session expired"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited(let retryDate):
            if let retryDate {
                let seconds = Int(retryDate.timeIntervalSinceNow)
                let minutes = max(1, (seconds + 30) / 60)
                return "Rate limited — retrying in ~\(minutes)min"
            }
            return "Rate limited — backing off"
        case .httpError(let code, _):
            return "API error (HTTP \(code))"
        case .unexpected(let msg):
            return msg
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .claudeCodeNotInstalled:
            return "Install the CLI and log in to authenticate."
        case .oauthLoginRequired:
            return "Run the provider's login command in your terminal to authenticate."
        case .unsupportedFormat:
            return "Re-authenticate by logging in again."
        case .tokenExpired:
            return "Open the provider's app/CLI to refresh your session."
        case .httpError(401, _):
            return "Open the provider's app/CLI to refresh your session."
        case .rateLimited:
            return "Polling will resume automatically."
        default:
            return nil
        }
    }
}
