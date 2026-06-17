import SwiftUI

// MARK: - Brand Colors (adaptive)

extension Color {
    static let brand = Color(red: 0.851, green: 0.482, blue: 0.247) // #D97B3F
    static let statusGreen = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let statusYellow = Color(red: 1.0, green: 0.722, blue: 0.0) // #FFB800
    static let statusRed = Color(red: 1.0, green: 0.231, blue: 0.188) // #FF3B30

    static func statusColor(for level: UsageLevel) -> Color {
        switch level {
        case .low: return .statusGreen
        case .medium: return .statusYellow
        case .high: return .statusRed
        }
    }
}

// MARK: - Tab

enum MenuTab: String, CaseIterable {
    case usage = "Usage"
    case settings = "Settings"
}

// MARK: - Main View

struct MenuBarView: View {
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var settings: SettingsManager
    @ObservedObject var updateService: UpdateService
    @ObservedObject var notifications: NotificationService
    @ObservedObject var devicePusher: DevicePusher
    @State private var selectedTab: MenuTab = .usage

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            tabBar

            ScrollView {
                Group {
                    switch selectedTab {
                    case .usage:
                        usageTab
                    case .settings:
                        settingsTab
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 260, maxHeight: 600)

            Divider()
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.brand.opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay(brandIcon(size: 18))

            Text("TokenCap")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brand)

            Spacer()

            if coordinator.anyLoading {
                ProgressView()
                    .controlSize(.small)
            } else if !coordinator.allDisconnected {
                Circle()
                    .fill(Color.statusColor(for: coordinator.worstLevel))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.brand : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                        AnalyticsService.shared.track("tab_changed", data: ["tab": tab.rawValue])
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Usage Tab

    private var usageTab: some View {
        VStack(spacing: 0) {
            if coordinator.monitors.isEmpty {
                emptyAccountsCard
                    .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(coordinator.monitors) { monitor in
                        AccountUsageView(monitor: monitor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var emptyAccountsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No accounts configured")
                .font(.system(size: 13, weight: .semibold))
            Text("Add an account in Settings to start monitoring usage.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("GENERAL")

                VStack(spacing: 0) {
                    settingRow {
                        Text("Launch at login")
                            .font(.system(size: 13))
                    } control: {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .tint(.brand)
                    }

                    Divider()

                    settingRow {
                        Text("Poll interval")
                            .font(.system(size: 13))
                    } control: {
                        Picker("", selection: $settings.pollInterval) {
                            Text("30s").tag(30.0)
                            Text("60s").tag(60.0)
                            Text("2min").tag(120.0)
                            Text("5min").tag(300.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                    }

                    Divider()

                    settingRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anonymous analytics")
                                .font(.system(size: 13))
                            Text("Help improve TokenCap")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    } control: {
                        Toggle("", isOn: $settings.analyticsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .tint(.brand)
                    }
                }
            }

            accountsSection

            // Notifications
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("NOTIFICATIONS")

                settingRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage alerts")
                            .font(.system(size: 13))
                        Text("Notify at thresholds")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } control: {
                    Toggle("", isOn: $settings.notificationsEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(.brand)
                }

                if settings.notificationsEnabled {
                    thresholdGrid
                    testAlertsSection
                }
            }

            devicesSection

            // About
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("ABOUT")

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brand.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(brandIcon(size: 30))

                    Text("TokenCap")
                        .font(.system(size: 15, weight: .bold))

                    Text("Version \(updateService.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    if updateService.updateAvailable {
                        updateBanner
                    }

                    checkForUpdatesButton
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
    }

    // MARK: - Accounts Section

    @ViewBuilder
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("ACCOUNTS")
                Text("Monitor multiple Claude and Codex accounts")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if settings.accounts.isEmpty {
                Text("No accounts configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(settings.accounts) { account in
                        AccountSettingsRow(
                            account: accountBinding(for: account.id),
                            monitor: coordinator.monitor(for: account.id),
                            onRemove: { settings.removeAccount(id: account.id) }
                        )
                    }
                }
            }

            Menu {
                Button("Claude account") { settings.addAccount(provider: .claude) }
                Button("Codex account") { settings.addAccount(provider: .codex) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("Add account")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.brand)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func accountBinding(for id: UUID) -> Binding<Account> {
        Binding(
            get: { settings.accounts.first { $0.id == id } ?? Account(label: "", provider: .claude) },
            set: { settings.updateAccount($0) }
        )
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)

                Text("Version \(updateService.latestVersion) available")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Button {
                updateService.openDownload()
            } label: {
                Text("Download Update")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private var checkForUpdatesButton: some View {
        Button {
            AnalyticsService.shared.track("manual_update_check")
            Task { await updateService.checkForUpdates() }
        } label: {
            HStack(spacing: 6) {
                if updateService.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                Text("Check for Updates")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(updateService.isChecking)
    }

    // MARK: - Test Alerts

    private var testAlertsSection: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Test alert sounds")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(notifications.testableThresholds, id: \.self) { threshold in
                    Button {
                        notifications.playTestSound(for: threshold)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text("\(threshold)%")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Threshold Grid

    private var thresholdGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(SettingsManager.allThresholds, id: \.self) { threshold in
                let isActive = settings.enabledThresholds.contains(threshold)
                let level = UsageLevel.from(Double(threshold))

                Button {
                    settings.toggleThreshold(threshold)
                } label: {
                    Text("\(threshold)%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? Color.statusColor(for: level) : Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            if coordinator.allDisconnected {
                Text("Disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.statusRed)
                    .lineLimit(1)
            } else if let lastUpdated = coordinator.latestUpdate {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button {
                    Task { await coordinator.fetchAll(force: true) }
                    AnalyticsService.shared.track("manual_refresh")
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Devices

    @ViewBuilder
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("DEVICES")
                Text("Push usage to T-Display-S3 boards on your LAN")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if settings.deviceHostnames.isEmpty {
                Text("No devices configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(settings.deviceHostnames.indices, id: \.self) { index in
                        deviceRow(at: index)
                    }
                }
            }

            Button {
                settings.deviceHostnames.append("")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("Add device")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.brand)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func deviceRow(at index: Int) -> some View {
        let hostname = (index < settings.deviceHostnames.count) ? settings.deviceHostnames[index] : ""
        let state = devicePusher.reachability[hostname] ?? .unknown

        HStack(spacing: 6) {
            Circle()
                .fill(dotColor(for: state))
                .frame(width: 8, height: 8)

            TextField("hostname or IP", text: hostnameBinding(at: index))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { submitRow(at: index) }

            Button {
                removeDevice(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func hostnameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < settings.deviceHostnames.count else { return "" }
                return settings.deviceHostnames[index]
            },
            set: { newValue in
                guard index < settings.deviceHostnames.count else { return }
                var hosts = settings.deviceHostnames
                hosts[index] = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.deviceHostnames = hosts
            }
        )
    }

    // Pressing Enter in a row pushes the current usage to that one board
    // (or pings GET / if no poll has happened yet) so the dot updates.
    // Poll-driven pushes still fan out via the coordinator's primary Claude account.
    private func submitRow(at index: Int) {
        guard index < settings.deviceHostnames.count else { return }
        let hostname = settings.deviceHostnames[index]
        guard !hostname.isEmpty else { return }
        if let usage = coordinator.primaryClaudeMonitor?.usage {
            Task { await devicePusher.push(usage: usage, to: [hostname]) }
        } else {
            Task { await devicePusher.testConnection(hostname: hostname) }
        }
    }

    private func removeDevice(at index: Int) {
        guard index < settings.deviceHostnames.count else { return }
        settings.deviceHostnames.remove(at: index)
    }

    private func dotColor(for state: DevicePusher.ReachabilityState) -> Color {
        switch state {
        case .unknown: return Color.secondary.opacity(0.4)
        case .checking: return Color.statusYellow
        case .reachable: return Color.statusGreen
        case .unreachable: return Color.statusRed
        }
    }
}

// MARK: - Per-Account Usage View

/// Renders one account's usage. Observes its own monitor so per-account updates
/// refresh independently.
struct AccountUsageView: View {
    @ObservedObject var monitor: AccountMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountHeader

            if let usage = monitor.usage {
                if let primary = usage.primary {
                    sectionTitle("SESSION")
                    gaugeRow(label: "5-Hour Window", bucket: primary)
                }

                let hasWeekly = usage.secondary != nil || !usage.breakdown.isEmpty
                if hasWeekly {
                    sectionTitle("WEEKLY")
                        .padding(.top, 4)

                    if let secondary = usage.secondary {
                        gaugeRow(label: "All Models", bucket: secondary)
                    }
                    ForEach(usage.breakdown, id: \.label) { item in
                        gaugeRow(label: item.label, bucket: item.bucket)
                    }
                }

                if let extra = usage.extra, extra.isEnabled {
                    extraUsageCard(extra)
                        .padding(.top, 4)
                }

                if let error = monitor.error {
                    accountErrorCard(error, provider: monitor.account.provider)
                }
            } else if let error = monitor.error {
                accountErrorCard(error, provider: monitor.account.provider)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: monitor.account.provider.iconName)
                .font(.system(size: 11))
                .foregroundStyle(Color.brand)
            Text(monitor.account.label.isEmpty ? monitor.account.provider.displayName : monitor.account.label)
                .font(.system(size: 13, weight: .bold))
            Text(monitor.account.provider.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            if monitor.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var statusColor: Color {
        if monitor.error != nil && monitor.usage == nil { return .statusRed }
        if monitor.usage != nil { return Color.statusColor(for: monitor.usageLevel) }
        return Color.secondary.opacity(0.4)
    }
}

// MARK: - Account Settings Row

/// One editable account row in Settings: status dot, label, provider picker,
/// credential source, and a remove button. Mirrors the Devices list pattern.
struct AccountSettingsRow: View {
    @Binding var account: Account
    let monitor: AccountMonitor?
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if let monitor {
                    AccountStatusDot(monitor: monitor)
                } else {
                    Circle().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                }

                TextField("Label", text: $account.label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Picker("", selection: $account.provider) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
                .onChange(of: account.provider) { _, _ in
                    // A custom dir for one provider is meaningless for another.
                    if account.source.customDirectory != nil { account.source = .auto }
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(sourceLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if account.source.customDirectory != nil {
                    Button {
                        account.source = .auto
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    browseForDirectory()
                } label: {
                    Text("Browse")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sourceLabel: String {
        account.source.customDirectory ?? account.provider.autoSourceLabel
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = account.provider == .claude
            ? "Select a Claude config directory (contains .credentials.json)"
            : "Select a Codex config directory (contains auth.json)"
        panel.directoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)

        if panel.runModal() == .OK, let url = panel.url {
            account.source = .directory(url.path)
        }
    }
}

/// Live status dot for an account row, observing its monitor.
struct AccountStatusDot: View {
    @ObservedObject var monitor: AccountMonitor

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        if monitor.isLoading { return .statusYellow }
        if monitor.error != nil && monitor.usage == nil { return .statusRed }
        if monitor.usage != nil { return .statusGreen }
        return Color.secondary.opacity(0.4)
    }
}

// MARK: - Shared rendering helpers (used by MenuBarView and AccountUsageView)

private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .tracking(0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private func gaugeRow(label: String, bucket: UsageBucket) -> some View {
    let level = UsageLevel.from(bucket.utilization)
    let color = Color.statusColor(for: level)
    let fraction = min(bucket.utilization, 100) / 100

    return HStack(spacing: 12) {
        ZStack {
            Circle()
                .inset(by: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 5)

            Circle()
                .inset(by: 6)
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(bucket.utilization))")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))

            if let remaining = bucket.resetTimeRemaining {
                Text("Resets in \(remaining)")
                    .font(.system(size: 11))
                    .foregroundStyle(level == .high ? Color.statusRed : Color.secondary.opacity(0.8))
            }
        }

        Spacer()

        Text("\(Int(bucket.utilization))%")
            .font(.system(size: 18, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
}

private func extraUsageCard(_ extra: ExtraUsage) -> some View {
    let extraLevel: UsageLevel = extra.utilization.map { UsageLevel.from($0) } ?? .low
    let extraColor = Color.statusColor(for: extraLevel)
    let tintColor: Color = extraLevel == .low ? .brand : Color.statusColor(for: extraLevel)

    return HStack(spacing: 10) {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(0.05))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(tintColor)
            )

        VStack(alignment: .leading, spacing: 2) {
            Text("Extra Usage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tintColor)

            if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                Text(String(format: "$%.2f / $%d", used / 100, limit / 100))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let used = extra.usedCredits {
                Text(String(format: "$%.2f used", used / 100))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()

        if let util = extra.utilization {
            Text("\(Int(util))%")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(extraColor)
        }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(tintColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
        RoundedRectangle(cornerRadius: 10)
            .stroke(tintColor.opacity(0.2), lineWidth: 1)
    )
}

private func accountErrorCard(_ error: UsageError, provider: Provider) -> some View {
    let isWarning = if case .rateLimited = error { true } else { false }
    let tintColor = isWarning ? Color.statusYellow : Color.statusRed

    return VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: error.iconName)
                .font(.system(size: 14))
                .foregroundStyle(tintColor)

            Text(error.localizedDescription)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tintColor)
        }

        if let suggestion = error.recoverySuggestion {
            Text(suggestion)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }

        if error.isTokenIssue {
            Button {
                openTerminal(command: provider.loginCommand)
            } label: {
                Text("Open Terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: 6))
        }
    }
    .padding(14)
    .background(tintColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
        RoundedRectangle(cornerRadius: 10)
            .stroke(tintColor.opacity(0.2), lineWidth: 1)
    )
}

private func brandIcon(size: CGFloat) -> some View {
    Group {
        if let url = Bundle.module.url(forResource: "tokencap-icon-128", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "gauge.with.needle.fill")
                .font(.system(size: size * 0.7))
                .foregroundStyle(Color.brand)
        }
    }
}

private func settingRow<Label: View, Control: View>(
    @ViewBuilder label: () -> Label,
    @ViewBuilder control: () -> Control
) -> some View {
    HStack {
        label()
        Spacer()
        control()
    }
    .padding(.vertical, 8)
}

@MainActor
private func openTerminal(command: String) {
    AnalyticsService.shared.track("open_terminal")
    let script = """
    tell application "Terminal"
        activate
        do script "\(command)"
    end tell
    """
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
