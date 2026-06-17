import Foundation

/// A source of usage data for one provider (Claude, Codex, …).
///
/// Providers are stateless: token caching, 429 backoff, and polling all live in
/// `AccountMonitor`. A provider only knows how to (1) read a fresh access token
/// for a given credential source and (2) fetch + decode usage for a token.
protocol UsageProvider {
    /// Reads a fresh access token from disk / Keychain. Does not cache.
    /// Throws `UsageError` (e.g. `.oauthLoginRequired`, `.tokenExpired`).
    func readToken(source: CredentialSource) throws -> CachedToken

    /// Fetches and maps usage for a valid token.
    /// On HTTP 401 throws `.httpError(401, _)` so the monitor clears its token cache;
    /// on 429 throws `.rateLimited(retryDate)` with the parsed `Retry-After` (or nil).
    func fetchUsage(token: String) async throws -> AccountUsage
}

extension UsageProvider {
    /// Shared 429 handling: parses `Retry-After` into an absolute date if present.
    func retryDate(from response: HTTPURLResponse) -> Date? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header) {
            return Date().addingTimeInterval(seconds)
        }
        return nil
    }
}

/// Builds the right provider for an account's provider kind.
enum ProviderFactory {
    static func make(for provider: Provider) -> UsageProvider {
        switch provider {
        case .claude: return ClaudeProvider()
        case .codex: return CodexProvider()
        }
    }
}
