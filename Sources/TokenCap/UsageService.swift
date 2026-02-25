import Foundation
import Combine

@MainActor
final class UsageService: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastUpdated: Date?
    @Published var error: UsageError?
    @Published var isLoading: Bool = false

    private let credentialsPath: String
    private let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var pollTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.credentialsPath = "\(home)/.claude/.credentials.json"
    }

    // MARK: - Token Management

    func readAccessToken() throws -> String {
        let url = URL(fileURLWithPath: credentialsPath)

        guard FileManager.default.fileExists(atPath: credentialsPath) else {
            throw UsageError.credentialsNotFound
        }

        let data = try Data(contentsOf: url)
        let credentials = try JSONDecoder().decode(CredentialsFile.self, from: data)

        if credentials.claudeAiOauth.isExpired {
            throw UsageError.tokenExpired(credentials.claudeAiOauth.expirationDate)
        }

        return credentials.claudeAiOauth.accessToken
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
            request.setValue("tokencap/0.1.0", forHTTPHeaderField: "User-Agent")
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

        } catch let error as UsageError {
            self.error = error
        } catch {
            self.error = .unexpected(error.localizedDescription)
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
    case credentialsNotFound
    case tokenExpired(Date)
    case invalidResponse
    case httpError(Int, String)
    case unexpected(String)

    var isTokenIssue: Bool {
        switch self {
        case .credentialsNotFound, .tokenExpired: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "Claude Code not found"
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
        case .credentialsNotFound:
            return "Install Claude Code and run `claude login` to authenticate."
        case .tokenExpired:
            return "Open Claude Code to refresh your session."
        case .httpError(401, _):
            return "Open Claude Code to refresh your session."
        default:
            return nil
        }
    }
}
