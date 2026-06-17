import Foundation

/// Reads OpenAI Codex CLI credentials (`~/.codex/auth.json`) and fetches usage
/// from the reverse-engineered ChatGPT backend usage endpoint.
///
/// ⚠️ The endpoint host/path, required headers, the `auth.json` field layout, and
/// the response JSON shape are all reverse-engineered. They MUST be confirmed
/// against a real, logged-in Codex CLI before relying on this in production.
/// See the plan's "Risks" section. Token refresh is out of scope: an expired
/// token surfaces a re-auth error rather than refreshing silently.
struct CodexProvider: UsageProvider {
    private let apiURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!

    // MARK: - Token

    func readToken(source: CredentialSource) throws -> CachedToken {
        let path = Self.authPath(for: source)
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.claudeCodeNotInstalled  // reused generic "not found / log in" state
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let auth: CodexAuthFile
        do {
            auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        } catch {
            throw UsageError.unsupportedFormat
        }

        guard let accessToken = auth.tokens?.accessToken, !accessToken.isEmpty else {
            throw UsageError.oauthLoginRequired
        }

        let expiry = Self.jwtExpiry(accessToken) ?? Date().addingTimeInterval(50 * 60)
        if Date() >= expiry {
            throw UsageError.tokenExpired(expiry)
        }
        return CachedToken(token: accessToken, expiresAt: expiry)
    }

    // MARK: - Fetch

    func fetchUsage(token: String) async throws -> AccountUsage {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("tokencap/\(version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw UsageError.rateLimited(retryDate(from: http)) }
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw UsageError.httpError(http.statusCode, body)
        }
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data).toAccountUsage()
    }

    // MARK: - Path resolution

    static func authPath(for source: CredentialSource) -> String {
        if let custom = source.customDirectory {
            return resolvingSymlinks("\(custom)/auth.json")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return resolvingSymlinks("\(home)/.codex/auth.json")
    }

    static var defaultAuthExists: Bool {
        FileManager.default.fileExists(atPath: authPath(for: .auto))
    }

    private static func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Extracts the `exp` claim (seconds epoch) from a JWT access token, if present.
    static func jwtExpiry(_ jwt: String) -> Date? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to a multiple of 4 for base64 decoding.
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - auth.json shape

/// Subset of `~/.codex/auth.json` we need. Extra fields are ignored.
struct CodexAuthFile: Codable {
    let tokens: CodexTokens?

    enum CodingKeys: String, CodingKey {
        case tokens
    }
}

struct CodexTokens: Codable {
    let accessToken: String?
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountId = "account_id"
    }
}
