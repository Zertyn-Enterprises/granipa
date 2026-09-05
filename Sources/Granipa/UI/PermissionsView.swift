import SwiftUI

enum LanguageChipStatus: Equatable {
    case checking
    case installed
    case absent

    var label: String {
        switch self {
        case .checking: "Checking"
        case .installed: "Installed"
        case .absent: "Not installed"
        }
    }

    var accessibilityStatus: String {
        switch self {
        case .checking: "checking"
        case .installed: "installed"
        case .absent: "not installed"
        }
    }

    static func resolve(knownInstalled: Set<String>?, localeID: String) -> LanguageChipStatus {
        guard let knownInstalled else { return .checking }
        return knownInstalled.contains(localeID) ? .installed : .absent
    }
}

enum LanguageInstallProbe {
    static func taskID(localeIDs: [String], refreshTick: Int) -> String {
        "\(localeIDs.joined(separator: ","))#\(refreshTick)"
    }

    static func shouldClearKnown(checkedLocales: [String], visibleLocales: [String]) -> Bool {
        checkedLocales != visibleLocales
    }

    static func isStale(requested: [String], visible: [String]) -> Bool {
        requested != visible
    }
}

struct PermissionsSettings: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var center = PermissionCenter()
    @State private var isRefreshing = true

    private var health: PermissionHealth {
        PermissionHealth(snapshot: PermissionSnapshot(center: center, isRefreshing: isRefreshing))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    PermissionHealthStrip(health: health) {
                        guard let kind = health.firstActionable else { return }
                        if reduceMotion {
                            proxy.scrollTo(kind, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: Theme.motionNormal)) {
                                proxy.scrollTo(kind, anchor: .center)
                            }
                        }
                    }
                    requiredSection
                    bottomCards
                    footer
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task { await rescan() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await center.refresh() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Grant the permissions Grañipa needs to capture and transcribe meetings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                Task { await rescan() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "Checking" : "Rescan all")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .granipaSecondaryControl()
            .controlSize(.small)
            .disabled(isRefreshing)
            .accessibilityLabel("Rescan permissions")
            .help("Re-read permission status from macOS. Does not create a system-audio tap.")
        }
        .accessibilityElement(children: .contain)
    }

    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Required permissions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            PermissionRowsCard(
                health: health,
                onAction: perform,
                onOpenPane: openPermissionPane)
            PermissionLegend()
        }
    }

    private var bottomCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                PermissionLanguagesCard()
                PermissionPrivacyCard()
            }
            VStack(spacing: 12) {
                PermissionLanguagesCard()
                PermissionPrivacyCard()
            }
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                footerCopy
                Spacer(minLength: 8)
                footerActions
            }
            VStack(alignment: .leading, spacing: 8) {
                footerCopy
                footerActions
            }
        }
        .padding(.top, 4)
    }

    private var footerCopy: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
            Text("Permissions are managed by macOS. You can also update them in System Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button("Open System Settings") {
                openPermissionPane(PermissionCenter.securityPane)
            }
            .granipaSecondaryControl()
            .controlSize(.small)
            .accessibilityLabel("Open System Settings")

            Button("Show welcome tour again…") {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Show welcome tour again")
        }
    }

    private func rescan() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await center.refresh()
    }

    private func perform(_ row: PermissionRowModel) {
        Task { await performPermissionAction(row, center: center) }
    }
}

struct PermissionsListView: View {
    @State private var center = PermissionCenter()
    @State private var isRefreshing = true

    private var health: PermissionHealth {
        PermissionHealth(snapshot: PermissionSnapshot(center: center, isRefreshing: isRefreshing))
    }

    var body: some View {
        PermissionRowsCard(
            health: health,
            onAction: { row in
                Task { await performPermissionAction(row, center: center) }
            },
            onOpenPane: openPermissionPane)
            .task {
                isRefreshing = true
                await center.refresh()
                isRefreshing = false
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                Task { await center.refresh() }
            }
    }
}

private struct PermissionHealthStrip: View {
    let health: PermissionHealth
    let onFix: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                identity
                stripDivider
                dots
                    .accessibilityHidden(true)
                if health.showsFixRecommended {
                    stripDivider
                    fixButton
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    identity
                    Spacer(minLength: 0)
                    if health.showsFixRecommended { fixButton }
                }
                dots
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: Theme.radiusL)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission health, \(health.headline), \(health.detail)")
    }

    private var identity: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(shieldColor.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(shieldColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Permission health")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    Text(health.headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Circle()
                        .fill(shieldColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(health.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: 12) {
            ForEach(health.rows) { row in
                VStack(spacing: 6) {
                    Image(systemName: row.kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            row.tone == .granted ? Theme.textSecondary : Theme.accent)
                        .frame(width: 22, height: 18)
                    Circle()
                        .fill(toneColor(row.tone, state: row.state))
                        .frame(width: 6, height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.kind.title), \(row.statusLabel)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fixButton: some View {
        Button(action: onFix) {
            Text("Fix recommended")
                .font(.system(size: 12, weight: .semibold))
        }
        .granipaPrimaryControl()
        .controlSize(.small)
        .accessibilityLabel("Fix recommended")
        .help("Jump to the first permission that still needs attention.")
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 36)
            .accessibilityHidden(true)
    }

    private var shieldColor: Color {
        if health.snapshot.isRefreshing { return Theme.statusLoading }
        if health.attentionCount == 0 { return Theme.statusDone }
        return Theme.statusFailed
    }
}

private struct PermissionRowsCard: View {
    let health: PermissionHealth
    let onAction: (PermissionRowModel) -> Void
    let onOpenPane: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(health.rows.enumerated()), id: \.element.id) { index, row in
                PermissionRowView(
                    row: row,
                    highlighted: health.firstActionable == row.kind && !health.snapshot.isRefreshing,
                    isPrimaryAction: health.firstActionable == row.kind,
                    onAction: { onAction(row) },
                    onOpenPane: { onOpenPane(row.kind.settingsPane) })
                    .id(row.kind)
                if index < health.rows.count - 1 {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.leading, 50)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .card(cornerRadius: Theme.radiusM)
    }
}

private struct PermissionRowView: View {
    let row: PermissionRowModel
    var highlighted = false
    var isPrimaryAction = false
    let onAction: () -> Void
    let onOpenPane: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: row.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(
                    Theme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.kind.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(row.kind.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PermissionStatusBadge(row: row)

            if row.probing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking system audio permission")
            } else if let title = row.actionTitle {
                actionButton(title)
            }

            Button(action: onOpenPane) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Open the System Settings pane for \(row.kind.title).")
            .accessibilityLabel("Open System Settings for \(row.kind.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(highlighted ? Theme.accent.opacity(0.08) : .clear)
        .overlay(alignment: .leading) {
            if highlighted {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2)
            }
        }
        .hoverHighlight(cornerRadius: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.kind.title), \(row.statusLabel). \(row.kind.summary)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    @ViewBuilder
    private func actionButton(_ title: String) -> some View {
        let button = Button(title, action: onAction)
            .controlSize(.small)
            .accessibilityLabel(actionAccessibilityLabel(title))
            .help(actionHelp)
        if isPrimaryAction {
            button
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func actionAccessibilityLabel(_ title: String) -> String {
        switch row.action {
        case .request: "Request \(row.kind.title)"
        case .checkSystemAudio: "Check system audio permission"
        case .openSettings: "Open System Settings"
        case .none: title
        }
    }

    private var actionHelp: String {
        switch row.action {
        case .checkSystemAudio:
            "Creates a brief audio tap — macOS asks for the permission if it was never granted."
        case .request:
            "Ask macOS for \(row.kind.title) access."
        case .openSettings:
            "Open the System Settings pane for \(row.kind.title)."
        case .none:
            row.kind.title
        }
    }
}

private struct PermissionStatusBadge: View {
    let row: PermissionRowModel

    var body: some View {
        let color = toneColor(row.tone, state: row.state)
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(row.statusLabel)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct PermissionLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legendItem(Theme.statusDone, "Granted")
            legendItem(Theme.statusListening, "Denied")
            legendItem(Theme.statusFailed, "Unchecked")
            legendItem(Theme.statusLoading, "Not asked")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: Granted, Denied, Unchecked, Not asked")
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
    }
}

private struct PermissionLanguagesCard: View {
    @AppStorage("probeLocales") private var probeLocalesRaw = "en-US,es-ES"
    @State private var installedIDs: Set<String>?
    @State private var checkedLocaleIDs: [String] = []
    @State private var refreshTick = 0

    private var localeIDs: [String] {
        LanguageDetection.parseProbeLocales(probeLocalesRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Languages")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                "Automatic detection uses up to \(LanguageDetection.maxProbeLocales) locales. Change them in Settings → General."
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(localeIDs, id: \.self) { id in
                    let status = LanguageChipStatus.resolve(
                        knownInstalled: installedIDs, localeID: id)
                    let name = languageName(id)
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        chipAccessory(status, name: name)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.fillSubtle, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name) \(status.accessibilityStatus)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(cornerRadius: Theme.radiusM)
        .task(id: LanguageInstallProbe.taskID(localeIDs: localeIDs, refreshTick: refreshTick)) {
            await refreshInstalled()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshTick += 1
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
        ) { _ in
            refreshTick += 1
        }
    }

    @ViewBuilder
    private func chipAccessory(_ status: LanguageChipStatus, name: String) -> some View {
        switch status {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.statusDone)
                .help("\(name) installed")
        case .checking, .absent:
            Text(status.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func refreshInstalled() async {
        let requested = localeIDs
        if LanguageInstallProbe.shouldClearKnown(
            checkedLocales: checkedLocaleIDs, visibleLocales: requested)
        {
            installedIDs = nil
        }
        var installed: Set<String> = []
        for id in requested {
            if Task.isCancelled { return }
            if await SpeechModels.isInstalled(locale: Locale(identifier: id)) {
                installed.insert(id)
            }
        }
        if Task.isCancelled { return }
        if LanguageInstallProbe.isStale(requested: requested, visible: localeIDs) {
            return
        }
        installedIDs = installed
        checkedLocaleIDs = requested
    }

    private func languageName(_ id: String) -> String {
        let locale = Locale(identifier: id)
        if let code = locale.language.languageCode?.identifier,
            let name = Locale.current.localizedString(forLanguageCode: code)
        {
            return name.capitalized
        }
        return Locale.current.localizedString(forIdentifier: id)?.capitalized ?? id
    }
}

private struct PermissionPrivacyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System & privacy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            policyRow(
                icon: "cpu",
                title: "On-device by default",
                detail: "Meetings transcribe on this Mac unless you enable a cloud engine.")
            policyRow(
                icon: "internaldrive",
                title: "Local storage",
                detail: "Recordings and history stay on this Mac.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(cornerRadius: Theme.radiusM)
        .accessibilityElement(children: .contain)
    }

    private func policyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private func toneColor(_ tone: PermissionTone, state: PermissionState) -> Color {
    switch state {
    case .granted: Theme.statusDone
    case .denied: Theme.statusListening
    case .unchecked: Theme.statusFailed
    case .notDetermined:
        switch tone {
        case .unknown: Theme.statusLoading
        case .granted: Theme.statusDone
        case .actionNeeded: Theme.statusFailed
        }
    }
}

@MainActor
private func performPermissionAction(_ row: PermissionRowModel, center: PermissionCenter) async {
    switch row.action {
    case .none:
        return
    case .request:
        switch row.kind {
        case .microphone: await center.requestMicrophone()
        case .calendar: await center.requestCalendar()
        case .notifications: await center.requestNotifications()
        default: return
        }
    case .openSettings:
        openPermissionPane(row.kind.settingsPane)
    case .checkSystemAudio:
        await center.probeSystemAudio()
    }
}

private func openPermissionPane(_ pane: String) {
    if let url = URL(string: pane) {
        NSWorkspace.shared.open(url)
    }
}
