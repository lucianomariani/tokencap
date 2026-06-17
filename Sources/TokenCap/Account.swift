import Foundation

// MARK: - Provider

/// An AI subscription whose usage TokenCap can monitor.
enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// SF Symbol used as the provider glyph in the Usage tab.
    var iconName: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Terminal command that re-authenticates this provider's CLI.
    var loginCommand: String {
        switch self {
        case .claude: return "claude login"
        case .codex: return "codex login"
        }
    }

    /// Human-readable description of the `.auto` credential source.
    var autoSourceLabel: String {
        switch self {
        case .claude: return "Auto (detect / Keychain)"
        case .codex: return "Auto (~/.codex/auth.json)"
        }
    }
}

// MARK: - Credential Source

/// Where an account's credentials come from.
/// `.auto` uses the provider's default discovery (Claude: detect dir / Keychain;
/// Codex: `~/.codex/auth.json`). `.directory` points at a specific config dir.
enum CredentialSource: Codable, Equatable {
    case auto
    case directory(String)

    var customDirectory: String? {
        if case let .directory(path) = self, !path.isEmpty { return path }
        return nil
    }
}

// MARK: - Account

/// A single monitored account: a provider + where to read its credentials + a label.
struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var provider: Provider
    var source: CredentialSource

    init(id: UUID = UUID(), label: String, provider: Provider, source: CredentialSource = .auto) {
        self.id = id
        self.label = label
        self.provider = provider
        self.source = source
    }

    /// Short tag for the compact multi-segment menu bar (e.g. "P", "Wo").
    /// Falls back to the provider initial when the label is empty.
    var menuAbbreviation: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(provider.displayName.prefix(1)).uppercased()
        }
        return String(trimmed.prefix(2))
    }
}

// MARK: - Cached Token

/// An access token plus its expiry, shared across providers.
struct CachedToken {
    let token: String
    let expiresAt: Date

    var isValid: Bool { Date() < expiresAt }
}
