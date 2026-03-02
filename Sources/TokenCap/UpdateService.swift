import Foundation
import AppKit

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseURL: URL?
    @Published var downloadURL: URL?
    @Published var isChecking = false

    let currentVersion: String

    private let lastCheckKey = "UpdateService.lastCheckTimestamp"
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let apiURL = URL(string: "https://api.github.com/repos/helsky-labs/tokencap/releases/latest")!

    private init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public API

    /// Debounced check — skips if last check was less than 24h ago.
    func checkIfNeeded() async {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let elapsed = Date().timeIntervalSince1970 - lastCheck
        guard elapsed >= checkInterval else { return }
        await checkForUpdates()
    }

    /// Always runs — for manual button clicks.
    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        AnalyticsService.shared.track("update_check", data: ["version": currentVersion])

        do {
            var request = URLRequest(url: apiURL)
            request.setValue("TokenCap/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            let tagVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            if isNewer(tagVersion, than: currentVersion) {
                latestVersion = tagVersion
                releaseURL = URL(string: release.htmlURL)
                downloadURL = release.assets
                    .first { $0.browserDownloadURL.hasSuffix(".dmg") }
                    .flatMap { URL(string: $0.browserDownloadURL) }
                updateAvailable = true
                AnalyticsService.shared.track("update_available", data: [
                    "current": currentVersion,
                    "latest": tagVersion,
                ])
            } else {
                updateAvailable = false
            }
        } catch {
            // Silent failure — update checks should never disrupt the app
        }
    }

    /// Opens the download URL (DMG if available, otherwise release page).
    func openDownload() {
        guard let url = downloadURL ?? releaseURL else { return }
        AnalyticsService.shared.track("update_download_clicked", data: [
            "version": latestVersion,
            "url_type": downloadURL != nil ? "dmg" : "release_page",
        ])
        NSWorkspace.shared.open(url)
    }

    // MARK: - Semver Comparison

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

// MARK: - GitHub API Types

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case browserDownloadURL = "browser_download_url"
    }
}
