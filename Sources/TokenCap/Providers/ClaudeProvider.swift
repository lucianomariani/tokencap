import Foundation

/// Reads Claude Code OAuth credentials and fetches usage from Anthropic's
/// undocumented OAuth usage endpoint. Lifted from the original single-account
/// `UsageService`; behavior (file-first, Keychain fallback, beta header,
/// 401/429 handling) is preserved.
struct ClaudeProvider: UsageProvider {
    private let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // MARK: - Token

    func readToken(source: CredentialSource) throws -> CachedToken {
        let credentialsPath = Self.credentialsPath(for: source)

        // File-based credentials first — avoids macOS Keychain prompts when present.
        if FileManager.default.fileExists(atPath: credentialsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: credentialsPath))
            do {
                let credentials = try JSONDecoder().decode(CredentialsFile.self, from: data)
                if credentials.claudeAiOauth.isExpired {
                    throw UsageError.tokenExpired(credentials.claudeAiOauth.expirationDate)
                }
                return CachedToken(token: credentials.claudeAiOauth.accessToken,
                                   expiresAt: credentials.claudeAiOauth.expirationDate)
            } catch is DecodingError {
                throw UsageError.unsupportedFormat
            }
        }

        // Fall back to macOS Keychain (Claude Code 1.0.33+) only for auto sources;
        // a custom directory implies file-based credentials.
        if case .auto = source, let keychainResult = Self.readTokenFromKeychain() {
            switch keychainResult {
            case .success(let token): return token
            case .failure(let error): throw error
            }
        }

        let dir = (credentialsPath as NSString).deletingLastPathComponent
        let dirExists = FileManager.default.fileExists(atPath: dir)
        throw dirExists ? UsageError.oauthLoginRequired : UsageError.claudeCodeNotInstalled
    }

    /// Reads OAuth token from macOS Keychain via the `security` CLI (stable code
    /// signature → "Always Allow" persists, avoiding repeated prompts).
    private static func readTokenFromKeychain() -> Result<CachedToken, UsageError>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-a", NSUserName(),
            "-w",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let jsonData = raw.data(using: .utf8) else {
            return nil
        }

        guard let credentials = try? JSONDecoder().decode(CredentialsFile.self, from: jsonData) else {
            return .failure(.unsupportedFormat)
        }
        if credentials.claudeAiOauth.isExpired {
            return .failure(.tokenExpired(credentials.claudeAiOauth.expirationDate))
        }
        return .success(CachedToken(token: credentials.claudeAiOauth.accessToken,
                                    expiresAt: credentials.claudeAiOauth.expirationDate))
    }

    // MARK: - Fetch

    func fetchUsage(token: String) async throws -> AccountUsage {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        return try JSONDecoder().decode(UsageResponse.self, from: data).toAccountUsage()
    }

    // MARK: - Path resolution

    /// Resolves the `.credentials.json` path for a credential source.
    /// `.auto` priority: auto-detected dir > default `~/.claude`.
    static func credentialsPath(for source: CredentialSource) -> String {
        if let custom = source.customDirectory {
            return resolvingSymlinks("\(custom)/.credentials.json")
        }
        if let detected = detectedConfigDir {
            return resolvingSymlinks("\(detected)/.credentials.json")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return resolvingSymlinks("\(home)/.claude/.credentials.json")
    }

    /// First known location containing `.credentials.json`, or nil.
    static var detectedConfigDir: String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.claude", "\(home)/.config/claude"]
        for dir in candidates {
            let resolved = resolvingSymlinks("\(dir)/.credentials.json")
            if fm.fileExists(atPath: resolved) { return resolvingSymlinks(dir) }
        }
        return nil
    }

    private static func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
