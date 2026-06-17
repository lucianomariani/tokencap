import XCTest
@testable import TokenCap

@MainActor
final class TokenCapTests: XCTestCase {

    // MARK: - Migration

    func testMigrationWithCustomDirProducesDirectorySource() {
        let accounts = SettingsManager.migratedAccounts(customConfigDir: "/Users/me/dotfiles/claude")
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].provider, .claude)
        XCTAssertEqual(accounts[0].source, .directory("/Users/me/dotfiles/claude"))
    }

    func testMigrationWithoutCustomDirProducesAutoSource() {
        XCTAssertEqual(SettingsManager.migratedAccounts(customConfigDir: nil)[0].source, .auto)
        XCTAssertEqual(SettingsManager.migratedAccounts(customConfigDir: "")[0].source, .auto)
    }

    // MARK: - Claude response mapping

    func testClaudeResponseMapsToAccountUsage() throws {
        let json = """
        {
            "five_hour": { "utilization": 42.5, "resets_at": "2026-06-17T20:00:00.000Z" },
            "seven_day": { "utilization": 70.0, "resets_at": "2026-06-22T00:00:00.000Z" },
            "seven_day_sonnet": { "utilization": 65.0, "resets_at": null },
            "seven_day_opus": { "utilization": 30.0, "resets_at": null },
            "extra_usage": { "is_enabled": true, "monthly_limit": 5000, "used_credits": 1250.0, "utilization": 25.0 }
        }
        """
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        let usage = response.toAccountUsage()

        XCTAssertEqual(usage.primary?.utilization, 42.5)
        XCTAssertEqual(usage.secondary?.utilization, 70.0)
        XCTAssertEqual(usage.breakdown.map(\.label), ["Sonnet", "Opus"])
        XCTAssertEqual(usage.breakdown.first?.bucket.utilization, 65.0)
        XCTAssertEqual(usage.extra?.isEnabled, true)
        XCTAssertEqual(usage.extra?.monthlyLimit, 5000)
    }

    func testHeadlineUtilizationPrefersPrimaryThenWorstBucket() {
        let withPrimary = AccountUsage(
            primary: UsageBucket(utilization: 10, resetsAt: nil),
            secondary: UsageBucket(utilization: 90, resetsAt: nil)
        )
        XCTAssertEqual(withPrimary.headlineUtilization, 10)

        let noPrimary = AccountUsage(
            secondary: UsageBucket(utilization: 55, resetsAt: nil),
            breakdown: [LabeledBucket(label: "Opus", bucket: UsageBucket(utilization: 88, resetsAt: nil))]
        )
        XCTAssertEqual(noPrimary.headlineUtilization, 88)

        XCTAssertEqual(AccountUsage().headlineUtilization, 0)
    }

    // MARK: - Codex response mapping

    func testCodexResponseMapsWindowsAndResolvesRelativeReset() throws {
        let json = """
        {
            "primary": { "used_percent": 40.0, "resets_in_seconds": 3600 },
            "secondary": { "used_percent": 80.0, "resets_at": "2026-06-22T00:00:00.000Z" }
        }
        """
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
        let usage = response.toAccountUsage()

        XCTAssertEqual(usage.primary?.utilization, 40.0)
        XCTAssertEqual(usage.secondary?.utilization, 80.0)
        XCTAssertEqual(usage.secondary?.resetsAt, "2026-06-22T00:00:00.000Z")
        // Relative reset normalized into a future absolute timestamp.
        XCTAssertNotNil(usage.primary?.resetsAt)
        XCTAssertNotNil(usage.primary?.resetDate)
        XCTAssertEqual(usage.breakdown.count, 0)
    }

    // MARK: - JWT expiry

    func testJwtExpiryParsesExpClaim() {
        let exp: Double = 1_900_000_000
        let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp])
        let segment = payload.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let jwt = "header.\(segment).signature"

        let parsed = CodexProvider.jwtExpiry(jwt)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, exp, accuracy: 1)
    }

    func testJwtExpiryReturnsNilForGarbage() {
        XCTAssertNil(CodexProvider.jwtExpiry("not-a-jwt"))
    }

    // MARK: - Device payload

    func testDevicePayloadPullsSonnetAndOpusFromBreakdown() {
        let usage = AccountUsage(
            primary: UsageBucket(utilization: 42, resetsAt: "2026-06-17T20:00:00.000Z"),
            secondary: UsageBucket(utilization: 70, resetsAt: "2026-06-22T00:00:00.000Z"),
            breakdown: [
                LabeledBucket(label: "Sonnet", bucket: UsageBucket(utilization: 65, resetsAt: nil)),
                LabeledBucket(label: "Opus", bucket: UsageBucket(utilization: 30, resetsAt: nil)),
            ],
            extra: ExtraUsage(isEnabled: true, monthlyLimit: 5000, usedCredits: 1250, utilization: 25)
        )
        let payload = DevicePusher.payload(from: usage)

        XCTAssertEqual(payload.v, 1)
        XCTAssertEqual(payload.sessionPct, 42)
        XCTAssertEqual(payload.weeklyAllPct, 70)
        XCTAssertEqual(payload.weeklySonnetPct, 65)
        XCTAssertEqual(payload.weeklyOpusPct, 30)
        XCTAssertEqual(payload.extraEnabled, true)
        XCTAssertEqual(payload.extraPct, 25)
    }

    // MARK: - Codable round-trips

    func testAccountCodableRoundTrip() throws {
        let accounts = [
            Account(label: "Personal", provider: .claude, source: .auto),
            Account(label: "Work", provider: .claude, source: .directory("/tmp/work")),
            Account(label: "AI", provider: .codex, source: .auto),
        ]
        let data = try JSONEncoder().encode(accounts)
        let decoded = try JSONDecoder().decode([Account].self, from: data)
        XCTAssertEqual(decoded, accounts)
    }

    func testMenuAbbreviation() {
        XCTAssertEqual(Account(label: "Personal", provider: .claude).menuAbbreviation, "Pe")
        XCTAssertEqual(Account(label: "", provider: .codex).menuAbbreviation, "C")
        XCTAssertEqual(Account(label: "", provider: .claude).menuAbbreviation, "C")
    }
}
