import Foundation
import Combine

@MainActor
final class UsageService: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastUpdated: Date?
    @Published var error: UsageError?
    @Published var isLoading: Bool = false

    private let settings: SettingsManager
    private let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var pollTimer: Timer?
    private var lastTrackedLevel: UsageLevel?

    init(settings: SettingsManager) {
        self.settings = settings
    }

    // MARK: - Token Management

    func readAccessToken() throws -> String {
        let credentialsPath = settings.credentialsPath
        let url = URL(fileURLWithPath: credentialsPath)
        let claudeDir = (credentialsPath as NSString).deletingLastPathComponent
        let dirExists = FileManager.default.fileExists(atPath: claudeDir)

        guard FileManager.default.fileExists(atPath: credentialsPath) else {
            throw dirExists ? UsageError.oauthLoginRequired : UsageError.claudeCodeNotInstalled
        }

        let data = try Data(contentsOf: url)

        do {
            let credentials = try JSONDecoder().decode(CredentialsFile.self, from: data)
            if credentials.claudeAiOauth.isExpired {
                throw UsageError.tokenExpired(credentials.claudeAiOauth.expirationDate)
            }
            return credentials.claudeAiOauth.accessToken
        } catch is DecodingError {
            throw UsageError.unsupportedFormat
        }
    }

    // MARK: - API Fetching

    func fetchUsage() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try readAccessToken()

            var request = URLRequest(url: apiURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("tokencap/1.2.1", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw UsageError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                throw UsageError.httpError(httpResponse.statusCode, body)
            }

            let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)
            self.usage = usageResponse
            self.lastUpdated = Date()
            self.error = nil

            let currentLevel = sessionUsageLevel
            if currentLevel != lastTrackedLevel {
                AnalyticsService.shared.track("usage_level_changed", data: [
                    "level": currentLevel.description,
                    "utilization": "\(Int(sessionUtilization))",
                ])
                lastTrackedLevel = currentLevel
            }

        } catch let error as UsageError {
            self.error = error
            AnalyticsService.shared.track("usage_error", data: [
                "type": error.analyticsLabel,
            ])
        } catch {
            self.error = .unexpected(error.localizedDescription)
            AnalyticsService.shared.track("usage_error", data: ["type": "unexpected"])
        }
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 60) {
        stopPolling()

        // Fetch immediately
        Task { await fetchUsage() }

        // Then poll at interval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchUsage()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Computed Properties

    var sessionUtilization: Double {
        usage?.fiveHour?.utilization ?? 0
    }

    var sessionUsageLevel: UsageLevel {
        UsageLevel.from(sessionUtilization)
    }

    var menuBarText: String {
        guard let usage else { return "--%" }

        if let fiveHour = usage.fiveHour {
            return "\(Int(fiveHour.utilization))%"
        }
        return "---%"
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case claudeCodeNotInstalled
    case oauthLoginRequired
    case unsupportedFormat
    case tokenExpired(Date)
    case invalidResponse
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
        case .httpError(let code, _): return "http_\(code)"
        case .unexpected: return "unexpected"
        }
    }

    var errorDescription: String? {
        switch self {
        case .claudeCodeNotInstalled:
            return "Claude Code not found"
        case .oauthLoginRequired:
            return "OAuth login required"
        case .unsupportedFormat:
            return "Unsupported credential format"
        case .tokenExpired:
            return "Session expired"
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let code, _):
            return "API error (HTTP \(code))"
        case .unexpected(let msg):
            return msg
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .claudeCodeNotInstalled:
            return "Install Claude Code and run `claude login` to authenticate."
        case .oauthLoginRequired:
            return "Run `claude login` in your terminal to authenticate."
        case .unsupportedFormat:
            return "Try running `claude login` to re-authenticate."
        case .tokenExpired:
            return "Open Claude Code to refresh your session."
        case .httpError(401, _):
            return "Open Claude Code to refresh your session."
        default:
            return nil
        }
    }
}
