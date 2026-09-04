import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let bgHex: UInt32 = 0x141617
    static let bgSidebarHex: UInt32 = 0x17191A
    static let cardHex: UInt32 = 0x1E2123
    static let accentHex: UInt32 = 0xF05423
    static let accentGlowOpacity = 0.4
    static let titleSize: CGFloat = 32
    static let sectionSize: CGFloat = 16

    static let bg = Color(hex: bgHex)
    static let bgSidebar = Color(hex: bgSidebarHex)
    static let card = Color(hex: cardHex)
    static let border = Color.white.opacity(0.07)
    static let accent = Color(hex: accentHex)
    static let accentGlow = accent.opacity(accentGlowOpacity)
    static let brandPurple = Color(hex: 0x7C5CFF)
    static let brandPink = Color(hex: 0xE879A8)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.34)
    static let channelMe = Color(hex: 0x6FA8DC)
    static let fillSubtle = Color.white.opacity(0.08)
    static let fillHover = Color.white.opacity(0.04)
    static let strokeStrong = Color.white.opacity(0.12)
    static let statusListening = Color(hex: 0xE24B4A)
    static let statusProcessing = Color(hex: 0x5B8DEF)
    static let statusDone = Color(hex: 0x4CD981)
    static let statusLoading = Color(hex: 0xE6C35C)
    static let statusFailed = Color(hex: 0xE08A3C)

    static let titleFont = Font.system(size: titleSize, weight: .semibold, design: .serif)
    static let meetingTitleFont = Font.system(size: 28, weight: .bold)
    static let sectionFont = Font.system(size: sectionSize, weight: .semibold)

    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
    static let radiusOverlay: CGFloat = 24

    static let fontSmall = Font.caption2
    static let fontCaption = Font.caption
    static let fontBody = Font.callout

    static let motionFast: TimeInterval = 0.08
    static let motionNormal: TimeInterval = 0.15
    private static let avatarPalette: [Color] = [
        Color(hex: 0x8A6D3B), Color(hex: 0xA85B32), Color(hex: 0x5B7A6A),
        Color(hex: 0x6B5B95), Color(hex: 0x3F6F8A), Color(hex: 0x9A4F4F),
    ]

    static func avatarColor(for key: String) -> Color {
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return avatarPalette[hash % avatarPalette.count]
    }

    static func dayHeader(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusM

    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(cornerRadius: CGFloat = Theme.radiusM) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}

struct HoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var cornerRadius: CGFloat = Theme.radiusS

    func body(content: Content) -> some View {
        content
            .background(
                hovering ? Theme.fillHover : .clear,
                in: RoundedRectangle(cornerRadius: cornerRadius))
            .animation(
                reduceMotion ? nil : .easeOut(duration: Theme.motionFast), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = Theme.radiusS) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }

    func recordGlow() -> some View {
        shadow(color: Theme.accentGlow, radius: 10)
    }
}

struct AvatarView: View {
    let letterSource: String?
    var fallbackIcon = "doc.text"
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(
                letterSource.map { Theme.avatarColor(for: $0).opacity(0.85) }
                    ?? Theme.fillSubtle)
            .frame(width: size, height: size)
            .overlay {
                if let source = letterSource, let first = source.first {
                    Text(String(first).uppercased())
                        .font(.system(size: size * 0.48, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
    }
}
