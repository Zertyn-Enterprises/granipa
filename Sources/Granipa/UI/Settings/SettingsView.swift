import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, dictation, shortcuts, permissions, ai, extras, integrations

    var id: String { rawValue }

    /// Single source for the pane Settings opens on (the old first tab).
    static let initialSelection = SettingsSection.general

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        case .ai: "AI"
        case .extras: "Extras"
        case .integrations: "Integrations"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "mic"
        case .shortcuts: "keyboard"
        case .permissions: "lock.shield"
        case .ai: "wand.and.stars"
        case .extras: "puzzlepiece"
        case .integrations: "network"
        }
    }

    var caption: String {
        switch self {
        case .general: "Meeting language, detection, recording"
        case .dictation: "Hold-to-talk, engine and rewrite"
        case .shortcuts: "Hotkeys and window actions"
        case .permissions: "Access and system permissions"
        case .ai: "Providers and note templates"
        case .extras: "Clipboard and windows"
        case .integrations: "Local API and webhooks"
        }
    }

    var subPages: [SettingsSubPage] {
        switch self {
        case .ai: [.providers, .templates]
        case .extras: [.clipboardAndOCR, .windows]
        case .integrations: [.api, .webhooks]
        case .general, .dictation, .shortcuts, .permissions: []
        }
    }
}

enum SettingsSubPage: String, Hashable, Identifiable {
    case providers, templates
    case clipboardAndOCR, windows
    case api, webhooks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "Providers"
        case .templates: "Templates"
        case .clipboardAndOCR: "Clipboard & OCR"
        case .windows: "Windows"
        case .api: "API"
        case .webhooks: "Webhooks"
        }
    }
}

enum SettingsLayout {
    /// Readable column for form sections. Permissions fill the remaining width.
    static let contentMaxWidth: CGFloat = 760
}

/// Drafts and section selection for the embedded Settings screen. Owned by
/// MainWindow so leaving Settings unmounts panes but keeps unsaved edits.

struct SettingsSession {
    var section = SettingsSection.initialSelection
    var aiPane = SettingsSubPage.providers
    var extrasPane = SettingsSubPage.clipboardAndOCR
    var integrationsPane = SettingsSubPage.api
    var dictationKeyDrafts = DictationKeyDrafts()
    var webhookDrafts = EditorDrafts<Webhook>()
    var templateDrafts = EditorDrafts<MeetingTemplate>()
}

/// Unsaved Dictation credential drafts, hoisted above the section switch so
/// navigating away and back keeps what was typed (main-window lifetime only).

struct DictationKeyDrafts {
    var museKey = ""
    var keySaved: Bool?
    var spaceXAIKey = ""
    var spaceXAIKeySaved: Bool?
    var customKey = ""
    var customKeySaved: Bool?
    private var loadedFromKeychain = false

    /// Seeds drafts from the keychain once per main-window lifetime; remounts keep edits.
    mutating func loadOnce(_ read: (String) -> String?) {
        guard !loadedFromKeychain else { return }
        museKey = read(KeychainStore.museAPIKeyAccount) ?? ""
        spaceXAIKey = read(KeychainStore.spaceXAIKeyAccount) ?? ""
        customKey = read(KeychainStore.rewriteCustomKeyAccount) ?? ""
        loadedFromKeychain = true
    }
}

/// Unsaved editor drafts keyed by item id, hoisted above the pane switches so
/// section/subpage navigation keeps edits for the lifetime of the main window.
/// Reads fall back to the persisted item until the user edits.

struct EditorDrafts<Item: Identifiable> {
    private var drafts: [Item.ID: Item] = [:]

    subscript(item: Item) -> Item {
        get { drafts[item.id] ?? item }
        set { drafts[item.id] = newValue }
    }
}

struct SettingsView: View {
    @Binding var session: SettingsSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        page
            .animation(
                reduceMotion ? nil : .easeOut(duration: Theme.motionNormal),
                value: session.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
    }

    // switch keeps only the selected pane instantiated
    @ViewBuilder
    private var page: some View {
        switch session.section {
        case .general:
            SettingsPage(
                title: "General",
                subtitle: "Meeting language, detection, recording and startup."
            ) {
                GeneralSettings()
            }
        case .dictation:
            SettingsPage(
                title: "Dictation",
                subtitle: "Hold-to-talk dictation: shortcut, language, engine and instant rewrite."
            ) {
                DictationSettings(drafts: $session.dictationKeyDrafts)
            }
        case .shortcuts:
            SettingsPage(
                title: "Shortcuts",
                subtitle: "Rebind the macro key and every productivity or window shortcut."
            ) {
                ShortcutsSettings()
            }
        case .permissions:
            PermissionsSettings()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.bg)
                .transition(.opacity)
        case .ai:
            SettingsPage(
                title: "AI",
                subtitle: "Notes providers, speaker identification and note templates."
            ) {
                SettingsSubNav(pages: SettingsSection.ai.subPages, selection: $session.aiPane)
                if session.aiPane == .templates {
                    TemplateSettings(drafts: $session.templateDrafts)
                } else {
                    AISettings()
                }
            }
        case .extras:
            SettingsPage(
                title: "Extras",
                subtitle: "Clipboard history, text capture and window snapping."
            ) {
                SettingsSubNav(pages: SettingsSection.extras.subPages, selection: $session.extrasPane)
                if session.extrasPane == .windows {
                    WindowSettings()
                } else {
                    ProductivitySettings()
                }
            }
        case .integrations:
            SettingsPage(
                title: "Integrations",
                subtitle: "Local REST API and outgoing webhooks."
            ) {
                SettingsSubNav(
                    pages: SettingsSection.integrations.subPages,
                    selection: $session.integrationsPane)
                if session.integrationsPane == .webhooks {
                    WebhookSettings(drafts: $session.webhookDrafts)
                } else {
                    APISettings()
                }
            }
        }
    }
}

struct SettingsSidebar: View {
    let selection: SettingsSection
    let isRecording: Bool
    let select: (SettingsSection) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 34)

            Button(action: onBack) {
                Label("Back to app", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 10)
            .help("Back to app")
            .accessibilityLabel("Back to app")
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Customize how Grañipa works for you.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(SettingsSection.allCases) { section in
                SettingsNavItem(
                    title: section.title,
                    caption: section.caption,
                    icon: section.icon,
                    isActive: selection == section
                ) {
                    select(section)
                }
                .accessibilityLabel(section.title)
            }

            Spacer(minLength: 12)

            if isRecording {
                HStack(spacing: 7) {
                    Circle().fill(Theme.statusListening).frame(width: 7, height: 7)
                    Text("Recording")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            Text(versionLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 8)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgSidebar)
    }

    private var versionLabel: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Grañipa \($0)" } ?? "Grañipa"
    }
}

private struct SettingsNavItem: View {
    let title: String
    let caption: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Theme.fontCaption.weight(.semibold))
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
            }
        }
        .overlay(alignment: .leading) {
            if isActive {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3, height: 16)
            }
        }
        .hoverHighlight(cornerRadius: 10)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .transition(.opacity)
    }
}

private struct SettingsSubNav: View {
    let pages: [SettingsSubPage]
    @Binding var selection: SettingsSubPage

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(pages) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
