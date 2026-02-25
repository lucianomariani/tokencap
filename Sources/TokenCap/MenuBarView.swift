import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "gauge.with.needle")
                    .font(.title3)
                Text("TokenCap")
                    .font(.headline)
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 4)

            if let error = service.error {
                errorSection(error)
            }

            if let usage = service.usage {
                usageSection(usage)
            } else if service.error == nil {
                Text("Loading usage data...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            // Footer
            footerSection
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Usage Section

    @ViewBuilder
    private func usageSection(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Session (5-hour)
            if let fiveHour = usage.fiveHour {
                UsageRow(
                    label: "Session",
                    sublabel: "5-hour window",
                    utilization: fiveHour.utilization,
                    resetDate: fiveHour.resetDate
                )
            }

            // Weekly (All)
            if let sevenDay = usage.sevenDay {
                UsageRow(
                    label: "Weekly (All)",
                    sublabel: "7-day window",
                    utilization: sevenDay.utilization,
                    resetDate: sevenDay.resetDate
                )
            }

            // Weekly (Sonnet) - only if present
            if let sonnet = usage.sevenDaySonnet {
                UsageRow(
                    label: "Weekly (Sonnet)",
                    sublabel: "7-day window",
                    utilization: sonnet.utilization,
                    resetDate: sonnet.resetDate
                )
            }

            // Weekly (Opus) - only if present
            if let opus = usage.sevenDayOpus {
                UsageRow(
                    label: "Weekly (Opus)",
                    sublabel: "7-day window",
                    utilization: opus.utilization,
                    resetDate: opus.resetDate
                )
            }

            // Extra Usage
            if let extra = usage.extraUsage, extra.isEnabled {
                Divider()
                extraUsageSection(extra)
            }
        }
    }

    // MARK: - Extra Usage

    @ViewBuilder
    private func extraUsageSection(_ extra: ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Extra Usage")
                    .font(.subheadline.weight(.medium))
            }

            if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                HStack {
                    Text(String(format: "$%.2f / $%d", used / 100, limit / 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let util = extra.utilization {
                        Text("\(Int(util))%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(colorForUtilization(util))
                    }
                }
            } else if let used = extra.usedCredits {
                Text(String(format: "$%.2f used", used / 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private func errorSection(_ error: UsageError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: error.isTokenIssue ? "key.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error.isTokenIssue ? .orange : .yellow)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.localizedDescription)
                        .font(.caption.weight(.medium))
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if error.isTokenIssue {
                Button {
                    openTerminalWithClaude()
                } label: {
                    Label("Open Terminal", systemImage: "terminal.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func openTerminalWithClaude() {
        let script = """
        tell application "Terminal"
            activate
            do script "claude"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let lastUpdated = service.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                Task { await service.fetchUsage() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Helpers

    private func colorForUtilization(_ value: Double) -> Color {
        switch UsageLevel.from(value) {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// MARK: - Usage Row Component

struct UsageRow: View {
    let label: String
    let sublabel: String
    let utilization: Double
    let resetDate: Date?

    private var level: UsageLevel {
        UsageLevel.from(utilization)
    }

    private var barColor: Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(barColor)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * min(utilization, 100) / 100), height: 6)
                }
            }
            .frame(height: 6)

            // Reset time
            if let resetDate {
                Text("Resets \(resetDate.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
